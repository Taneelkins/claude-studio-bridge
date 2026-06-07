/**
 * Entry point. One process plays two roles:
 *   1. HTTP long-poll bridge on 127.0.0.1:44755  (the Studio plugin connects here)
 *   2. MCP server over stdio                       (Claude Code launches this)
 *
 * Claude Code spawns this when a session starts; the plugin connects whenever
 * Studio is open. Tool calls flow Claude -> MCP -> bridge -> plugin -> back.
 */
import { StudioBridge } from "./bridge.js";
import { startMcp } from "./mcp.js";
import { log } from "./log.js";

async function main(): Promise<void> {
  const bridge = new StudioBridge();

  try {
    await bridge.start();
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === "EADDRINUSE") {
      log(
        "Bridge port 44755 is already in use — another bridge instance likely " +
          "owns the Studio connection. This instance's tool calls will time out. " +
          "Close other Claude Code sessions if you need this one to drive Studio.",
      );
    } else {
      log("Failed to start HTTP bridge:", String(err));
    }
  }

  // The MCP server must come up regardless so Claude sees the tools.
  await startMcp(bridge);
}

main().catch((err) => {
  log("fatal:", String(err));
  process.exit(1);
});
