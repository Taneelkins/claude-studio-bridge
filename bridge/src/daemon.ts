/**
 * Persistent daemon. Runs ONLY the bridge HTTP server (no MCP/stdio), so the
 * Studio plugin always has one stable thing to connect to — independent of any
 * Claude Code chat. Installed as a macOS LaunchAgent (auto-start at login,
 * auto-restart on crash). Per-chat MCP servers forward tool calls here via
 * POST /invoke, so chats can come and go without ever dropping the connection.
 */
import { StudioBridge } from "./bridge.js";
import { log } from "./log.js";

const RETRY_MS = 3000;

async function main(): Promise<void> {
  const bridge = new StudioBridge();

  // Keep trying to own the port. If a chat instance currently holds it (e.g.
  // the daemon was just installed), we grab it the moment that chat releases it,
  // then hold it permanently.
  for (;;) {
    try {
      await bridge.start();
      log("daemon: owns the bridge port — the Studio connection is now permanent");
      return; // listening; the http server keeps the process alive
    } catch (err) {
      const e = err as NodeJS.ErrnoException;
      if (e.code === "EADDRINUSE") {
        log(`daemon: port busy (a chat holds it?); retrying in ${RETRY_MS}ms`);
        await new Promise((r) => setTimeout(r, RETRY_MS));
      } else {
        log("daemon: fatal:", String(err));
        process.exit(1);
      }
    }
  }
}

main();
