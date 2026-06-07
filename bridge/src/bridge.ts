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
/** How long a tool call waits for the plugin before giving up. */
const COMMAND_TIMEOUT_MS = 60_000;
/** Plugin is considered connected if it polled within this window. */
const CONNECTED_WINDOW_MS = 5_000;

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
    return Date.now() - this.lastPollAt < CONNECTED_WINDOW_MS;
  }

  /**
   * Invoke a tool inside Studio. Resolves with the plugin's textual response,
   * rejects on plugin-reported failure or timeout.
   */
  call(tool: string, args: unknown): Promise<string> {
    return new Promise((resolve, reject) => {
      const id = randomUUID();
      const message: StudioMessage = { id, args: { [tool]: args ?? {} } };
      const timer = setTimeout(() => {
        this.inflight.delete(id);
        this.queue = this.queue.filter((c) => c.message.id !== id);
        reject(
          new Error(
            `Timed out after ${COMMAND_TIMEOUT_MS}ms waiting for Studio. ` +
              `Is Roblox Studio open with the Claude Bridge plugin enabled?`,
          ),
        );
      }, COMMAND_TIMEOUT_MS);

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
    } else if (req.method === "GET" && url.startsWith("/health")) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, connected: this.connected }));
    } else {
      res.writeHead(404);
      res.end();
    }
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
