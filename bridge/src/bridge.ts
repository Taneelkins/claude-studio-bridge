/**
 * StudioBridge — the HTTP long-poll server that the Roblox Studio plugin talks to.
 *
 * The plugin cannot accept incoming connections, so communication is inverted:
 *   - Plugin long-polls  GET  /request   -> we hand it the next queued command.
 *   - Plugin posts back   POST /response  -> we resolve the matching tool call.
 *
 * MCP tool handlers call `bridge.call(tool, args)` which returns a promise that
 * settles when the plugin reports back (or times out).
 */
import http from "node:http";
import { randomUUID } from "node:crypto";
import { log } from "./log.js";

const PORT = Number(process.env.STUDIO_BRIDGE_PORT ?? 44755);
/** How long to hold an idle GET /request before replying 423 (plugin retries). */
const LONGPOLL_MS = 25_000;
/** Default time a tool call waits for the plugin before giving up. */
const COMMAND_TIMEOUT_MS = 60_000;
/** Treat the plugin as gone if there's no poll and no parked long-poll for this long. */
const STALE_MS = 30_000;

interface StudioMessage {
  id: string;
  args: Record<string, unknown>;
}

interface PendingCommand {
  message: StudioMessage;
  resolve: (text: string) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
}

interface Waiter {
  deliver: (cmd: PendingCommand | null) => void;
}

export class StudioBridge {
  /** Commands queued, waiting for the plugin to pick them up. */
  private queue: PendingCommand[] = [];
  /** Commands handed to the plugin, awaiting a /response. Keyed by id. */
  private inflight = new Map<string, PendingCommand>();
  /** Parked GET /request handlers waiting for a command to appear. */
  private waiters: Waiter[] = [];
  private server?: http.Server;
  private lastPollAt = 0;

  start(): Promise<void> {
    return new Promise((resolve, reject) => {
      const server = http.createServer((req, res) => this.route(req, res));
      server.on("error", reject);
      server.listen(PORT, "127.0.0.1", () => {
        log(`HTTP bridge listening on http://127.0.0.1:${PORT}`);
        resolve();
      });
      this.server = server;
    });
  }

  get connected(): boolean {
    // A healthy plugin is either parked in a long-poll (a waiter) or polled recently.
    return this.waiters.length > 0 || Date.now() - this.lastPollAt < STALE_MS;
  }

  /**
   * Invoke a tool inside Studio. Resolves with the plugin's textual response,
   * rejects on plugin-reported failure or timeout. `timeoutMs` lets slow tools
   * (e.g. play-mode runs) wait longer than the default.
   */
  call(tool: string, args: unknown, timeoutMs: number = COMMAND_TIMEOUT_MS): Promise<string> {
    return new Promise((resolve, reject) => {
      // Fail fast when Studio clearly isn't there instead of hanging for the full timeout.
      if (this.lastPollAt === 0 || (this.waiters.length === 0 && Date.now() - this.lastPollAt > STALE_MS)) {
        reject(
          new Error(
            "Roblox Studio isn't connected. Open Studio with the Claude Bridge " +
              "plugin enabled (click the Claude toolbar button), then retry.",
          ),
        );
        return;
      }

      const id = randomUUID();
      const message: StudioMessage = { id, args: { [tool]: args ?? {} } };
      const timer = setTimeout(() => {
        this.inflight.delete(id);
        this.queue = this.queue.filter((c) => c.message.id !== id);
        reject(
          new Error(
            `Timed out after ${timeoutMs}ms waiting for Studio. ` +
              `Is Roblox Studio open with the Claude Bridge plugin enabled?`,
          ),
        );
      }, timeoutMs);

      const cmd: PendingCommand = { message, resolve, reject, timer };

      const waiter = this.waiters.shift();
      if (waiter) {
        this.inflight.set(id, cmd);
        waiter.deliver(cmd);
      } else {
        this.queue.push(cmd);
      }
    });
  }

  private route(req: http.IncomingMessage, res: http.ServerResponse): void {
    const url = req.url ?? "";
    if (req.method === "GET" && url.startsWith("/request")) {
      this.handlePoll(req, res);
    } else if (req.method === "POST" && url.startsWith("/response")) {
      this.handleResponse(req, res);
    } else if (req.method === "POST" && url.startsWith("/invoke")) {
      this.handleInvoke(req, res);
    } else if (req.method === "GET" && url.startsWith("/health")) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, connected: this.connected }));
    } else {
      res.writeHead(404);
      res.end();
    }
  }

  /**
   * POST /invoke — lets another bridge instance (one that couldn't bind the port)
   * run a tool through this owner. Body: {tool, args, timeoutMs}.
   */
  private handleInvoke(req: http.IncomingMessage, res: http.ServerResponse): void {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", async () => {
      try {
        const { tool, args, timeoutMs } = JSON.parse(body) as {
          tool: string;
          args: unknown;
          timeoutMs?: number;
        };
        const response = await this.call(tool, args, timeoutMs);
        this.sendJson(res, 200, { success: true, response });
      } catch (err) {
        this.sendJson(res, 200, { success: false, error: (err as Error).message });
      }
    });
  }

  /** GET /request — plugin long-poll. */
  private handlePoll(req: http.IncomingMessage, res: http.ServerResponse): void {
    this.lastPollAt = Date.now();

    const ready = this.queue.shift();
    if (ready) {
      this.inflight.set(ready.message.id, ready);
      this.sendJson(res, 200, ready.message);
      return;
    }

    // Nothing queued — park until a command arrives or we time out.
    let settled = false;
    const waiter: Waiter = {
      deliver: (cmd) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        if (cmd) {
          this.sendJson(res, 200, cmd.message);
        } else {
          res.writeHead(423); // Locked: nothing yet, plugin retries immediately
          res.end();
        }
      },
    };

    const timeout = setTimeout(() => {
      this.removeWaiter(waiter);
      waiter.deliver(null);
    }, LONGPOLL_MS);

    req.on("close", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      this.removeWaiter(waiter);
    });

    this.waiters.push(waiter);
  }

  /** POST /response — plugin reports a command result. */
  private handleResponse(
    req: http.IncomingMessage,
    res: http.ServerResponse,
  ): void {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      res.writeHead(200);
      res.end();
      try {
        const data = JSON.parse(body) as {
          id: string;
          success: boolean;
          response: unknown;
        };
        const cmd = this.inflight.get(data.id);
        if (!cmd) return;
        this.inflight.delete(data.id);
        clearTimeout(cmd.timer);
        const text =
          typeof data.response === "string"
            ? data.response
            : JSON.stringify(data.response);
        if (data.success) cmd.resolve(text);
        else cmd.reject(new Error(text || "Studio reported an error"));
      } catch (err) {
        log("malformed /response body:", String(err));
      }
    });
  }

  private removeWaiter(waiter: Waiter): void {
    const i = this.waiters.indexOf(waiter);
    if (i >= 0) this.waiters.splice(i, 1);
  }

  private sendJson(res: http.ServerResponse, status: number, body: unknown): void {
    const payload = JSON.stringify(body);
    res.writeHead(status, { "content-type": "application/json" });
    res.end(payload);
  }
}
