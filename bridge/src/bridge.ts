/**
 * StudioBridge — the HTTP long-poll server that Roblox Studio plugins talk to.
 *
 * The plugin cannot accept incoming connections, so communication is inverted:
 *   - Plugin long-polls  GET  /request?studio=<id>  -> we hand it the next command for THAT Studio.
 *   - Plugin posts back   POST /response            -> we resolve the matching tool call.
 *
 * Several Studio windows can be connected at once. Each gets its own queue, so a
 * command only ever runs in the Studio it was addressed to (never "whichever
 * polled first"). Chats pick their Studio with a Target (see resolveTarget).
 *
 * MCP tool handlers call `bridge.call(tool, args, timeoutMs, target)` which
 * returns a promise that settles when the plugin reports back (or times out).
 */
import http from "node:http";
import { randomUUID } from "node:crypto";
import { log } from "./log.js";

const PORT = Number(process.env.STUDIO_BRIDGE_PORT ?? 44755);
/** How long to hold an idle GET /request before replying 423 (plugin retries). */
const LONGPOLL_MS = 25_000;
/** Default time a tool call waits for the plugin before giving up. */
const COMMAND_TIMEOUT_MS = 60_000;
/** Treat a Studio as gone if there's no poll and no parked long-poll for this long. */
const STALE_MS = 30_000;
/** Forget a disconnected Studio entirely after this long. */
const FORGET_MS = 10 * 60_000;
/** Largest request body we accept (asset pixel payloads can be several MB). */
const MAX_BODY_BYTES = 64 * 1024 * 1024;

/** Id used for plugins older than v2 that don't identify themselves. */
export const LEGACY_STUDIO_ID = "legacy";

/** What a plugin reports about itself on every poll. */
export interface StudioInfo {
  placeId: number;
  gameId: number;
  placeName: string;
  creatorId?: number;
  creatorType?: string;
  userId?: number;
  pluginVersion?: string;
}

/** Public snapshot of a connected Studio, returned by /studios. */
export interface StudioSummary extends StudioInfo {
  studioId: string;
  label: string;
  connected: boolean;
  busy: boolean;
  lastSeenSecondsAgo: number;
}

/** How a chat addresses a Studio. studioId wins; placeId re-finds it after a Studio restart. */
export interface Target {
  studioId?: string;
  placeId?: number;
}

interface StudioMessage {
  id: string;
  args: Record<string, unknown>;
}

interface PendingCommand {
  message: StudioMessage;
  studioId: string;
  resolve: (text: string) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
}

interface Waiter {
  deliver: (cmd: PendingCommand | null) => void;
}

interface StudioConn {
  id: string;
  info: StudioInfo;
  /** Commands queued, waiting for this plugin to pick them up. */
  queue: PendingCommand[];
  /** Parked GET /request handlers waiting for a command to appear. */
  waiters: Waiter[];
  lastPollAt: number;
  /** Commands handed to this plugin and not answered yet. */
  busy: number;
}

export function studioLabel(info: StudioInfo): string {
  const name = info.placeName || "Unnamed place";
  return info.placeId ? `${name} (place ${info.placeId})` : `${name} (unpublished)`;
}

export class StudioBridge {
  private studios = new Map<string, StudioConn>();
  /** Commands handed to a plugin, awaiting a /response. Keyed by id. */
  private inflight = new Map<string, PendingCommand>();
  private server?: http.Server;

  start(): Promise<void> {
    return new Promise((resolve, reject) => {
      const server = http.createServer((req, res) => this.route(req, res));
      server.on("error", reject);
      server.listen(PORT, "127.0.0.1", () => {
        log(`HTTP bridge listening on http://127.0.0.1:${PORT}`);
        setInterval(() => this.forgetOld(), 60_000).unref();
        resolve();
      });
      this.server = server;
    });
  }

  private isConnected(s: StudioConn): boolean {
    // Healthy = parked in a long-poll, polled recently, or busy running a command
    // (a long playtest blocks the plugin's poll loop but it's still alive).
    return s.waiters.length > 0 || s.busy > 0 || Date.now() - s.lastPollAt < STALE_MS;
  }

  get connected(): boolean {
    return this.list().some((s) => s.connected);
  }

  list(): StudioSummary[] {
    const now = Date.now();
    return [...this.studios.values()].map((s) => ({
      ...s.info,
      studioId: s.id,
      label: studioLabel(s.info),
      connected: this.isConnected(s),
      busy: s.busy > 0,
      lastSeenSecondsAgo: Math.round((now - s.lastPollAt) / 1000),
    }));
  }

  /**
   * Picks the Studio a call should run in. Throws a descriptive error (listing
   * what IS connected) rather than guessing when the choice is ambiguous.
   */
  resolveTarget(target?: Target): StudioConn {
    const live = [...this.studios.values()].filter((s) => this.isConnected(s));
    const describe = () =>
      live.length
        ? "Connected Studios:\n" +
          live.map((s) => `  - ${studioLabel(s.info)}  [studioId ${s.id}]`).join("\n")
        : "No Studio is connected. Open Studio with the Claude Bridge plugin enabled.";

    if (target?.studioId) {
      const s = this.studios.get(target.studioId);
      if (s && this.isConnected(s)) return s;
    }
    if (target?.placeId) {
      const matches = live.filter((s) => s.info.placeId === target.placeId);
      if (matches.length === 1) return matches[0];
      if (matches.length > 1) {
        throw new Error(
          `Place ${target.placeId} is open in ${matches.length} Studio windows; ` +
            `select one by studioId with select_studio.\n${describe()}`,
        );
      }
    }
    if (target?.studioId || target?.placeId) {
      throw new Error(
        `This chat is linked to a Studio that isn't connected right now ` +
          `(${target.placeId ? `place ${target.placeId}` : `studio ${target.studioId}`}). ` +
          `Open it in Studio, or switch with select_studio.\n${describe()}`,
      );
    }
    if (live.length === 1) return live[0];
    if (live.length === 0) {
      throw new Error(
        "Roblox Studio isn't connected. Open Studio with the Claude Bridge " +
          "plugin enabled (click the Claude toolbar button), then retry.",
      );
    }
    throw new Error(
      `${live.length} Studios are connected and this chat hasn't picked one. ` +
        `Use list_studios / select_studio first. (Older chats: type /mcp and ` +
        `Reconnect roblox-studio to get studio selection.)\n${describe()}`,
    );
  }

  /**
   * Invoke a tool inside Studio. Resolves with the plugin's textual response,
   * rejects on plugin-reported failure or timeout. `timeoutMs` lets slow tools
   * (e.g. play-mode runs) wait longer than the default.
   */
  call(
    tool: string,
    args: unknown,
    timeoutMs: number = COMMAND_TIMEOUT_MS,
    target?: Target,
  ): Promise<string> {
    return new Promise((resolve, reject) => {
      let studio: StudioConn;
      try {
        studio = this.resolveTarget(target);
      } catch (err) {
        reject(err);
        return;
      }

      const id = randomUUID();
      const message: StudioMessage = { id, args: { [tool]: args ?? {} } };
      const timer = setTimeout(() => {
        if (this.inflight.delete(id)) studio.busy = Math.max(0, studio.busy - 1);
        studio.queue = studio.queue.filter((c) => c.message.id !== id);
        reject(
          new Error(
            `Timed out after ${timeoutMs}ms waiting for ${studioLabel(studio.info)}. ` +
              `Is that Studio open with the Claude Bridge plugin enabled?`,
          ),
        );
      }, timeoutMs);

      const cmd: PendingCommand = { message, studioId: studio.id, resolve, reject, timer };

      const waiter = studio.waiters.shift();
      if (waiter) {
        this.markInflight(studio, cmd);
        waiter.deliver(cmd);
      } else {
        studio.queue.push(cmd);
      }
    });
  }

  private markInflight(studio: StudioConn, cmd: PendingCommand): void {
    this.inflight.set(cmd.message.id, cmd);
    studio.busy++;
  }

  private route(req: http.IncomingMessage, res: http.ServerResponse): void {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    const p = url.pathname;
    if (req.method === "GET" && p === "/request") {
      this.handlePoll(req, res, url);
    } else if (req.method === "POST" && p === "/response") {
      this.handleResponse(req, res);
    } else if (req.method === "POST" && p === "/invoke") {
      this.handleInvoke(req, res);
    } else if (req.method === "GET" && p === "/studios") {
      this.sendJson(res, 200, { studios: this.list() });
    } else if (req.method === "GET" && p === "/health") {
      this.sendJson(res, 200, {
        ok: true,
        connected: this.connected,
        studios: this.list().filter((s) => s.connected).map((s) => s.label),
      });
    } else {
      res.writeHead(404);
      res.end();
    }
  }

  private readBody(req: http.IncomingMessage, cb: (body: string | null) => void): void {
    const chunks: Buffer[] = [];
    let size = 0;
    let tooBig = false;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) tooBig = true;
      else chunks.push(chunk);
    });
    req.on("end", () => cb(tooBig ? null : Buffer.concat(chunks).toString("utf8")));
  }

  /**
   * POST /invoke — lets another bridge instance (a chat that couldn't bind the
   * port) run a tool through this owner. Body: {tool, args, timeoutMs, target}.
   */
  private handleInvoke(req: http.IncomingMessage, res: http.ServerResponse): void {
    this.readBody(req, async (body) => {
      try {
        if (body === null) throw new Error("Request body too large");
        const { tool, args, timeoutMs, target } = JSON.parse(body) as {
          tool: string;
          args: unknown;
          timeoutMs?: number;
          target?: Target;
        };
        const response = await this.call(tool, args, timeoutMs, target);
        this.sendJson(res, 200, { success: true, response });
      } catch (err) {
        this.sendJson(res, 200, { success: false, error: (err as Error).message });
      }
    });
  }

  /** Reads the plugin's self-description (v2+) or falls back to the legacy identity. */
  private identify(req: http.IncomingMessage, url: URL): StudioConn {
    const id = url.searchParams.get("studio") || LEGACY_STUDIO_ID;
    let info: StudioInfo = { placeId: 0, gameId: 0, placeName: "Studio (old plugin — rebuild it)" };
    const raw = req.headers["x-studio-info"];
    if (typeof raw === "string") {
      try {
        info = { ...info, ...(JSON.parse(decodeURIComponent(raw)) as StudioInfo) };
      } catch {
        // keep defaults
      }
    }
    let s = this.studios.get(id);
    if (!s) {
      s = { id, info, queue: [], waiters: [], lastPollAt: 0, busy: 0 };
      this.studios.set(id, s);
      log(`studio connected: ${studioLabel(info)} [${id}]`);
    } else {
      s.info = info; // place can be published / renamed mid-session
    }
    return s;
  }

  /** GET /request — plugin long-poll. */
  private handlePoll(req: http.IncomingMessage, res: http.ServerResponse, url: URL): void {
    const studio = this.identify(req, url);
    studio.lastPollAt = Date.now();

    const ready = studio.queue.shift();
    if (ready) {
      this.markInflight(studio, ready);
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
      this.removeWaiter(studio, waiter);
      waiter.deliver(null);
    }, LONGPOLL_MS);

    req.on("close", () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      this.removeWaiter(studio, waiter);
      studio.lastPollAt = Date.now();
    });

    studio.waiters.push(waiter);
  }

  /** POST /response — plugin reports a command result. */
  private handleResponse(req: http.IncomingMessage, res: http.ServerResponse): void {
    this.readBody(req, (body) => {
      res.writeHead(200);
      res.end();
      if (body === null) return;
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
        const studio = this.studios.get(cmd.studioId);
        if (studio) {
          studio.busy = Math.max(0, studio.busy - 1);
          studio.lastPollAt = Date.now();
        }
        const text =
          typeof data.response === "string" ? data.response : JSON.stringify(data.response);
        if (data.success) cmd.resolve(text);
        else cmd.reject(new Error(text || "Studio reported an error"));
      } catch (err) {
        log("malformed /response body:", String(err));
      }
    });
  }

  private forgetOld(): void {
    const now = Date.now();
    for (const [id, s] of this.studios) {
      if (!this.isConnected(s) && now - s.lastPollAt > FORGET_MS && s.queue.length === 0) {
        this.studios.delete(id);
        log(`studio forgotten: ${studioLabel(s.info)} [${id}]`);
      }
    }
  }

  private removeWaiter(studio: StudioConn, waiter: Waiter): void {
    const i = studio.waiters.indexOf(waiter);
    if (i >= 0) studio.waiters.splice(i, 1);
  }

  private sendJson(res: http.ServerResponse, status: number, body: unknown): void {
    const payload = JSON.stringify(body);
    res.writeHead(status, { "content-type": "application/json" });
    res.end(payload);
  }
}
