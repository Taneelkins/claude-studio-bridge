/**
 * Entry point. Claude Code spawns one of these per session. To support several
 * chats at once, instances coordinate over the single bridge port:
 *
 *   - OWNER  — first to bind 127.0.0.1:44755. Serves the Studio plugin directly
 *              and exposes POST /invoke for siblings.
 *   - CLIENT — port already taken, so it forwards every tool call to the owner's
 *              /invoke. This way every open chat can drive Studio, not just one.
 *
 * Either way the MCP server (stdio) comes up so Claude sees the tools.
 */
import { StudioBridge } from "./bridge.js";
import { startMcp, type Invoke, type ListStudios } from "./mcp.js";
import { log } from "./log.js";

const PORT = Number(process.env.STUDIO_BRIDGE_PORT ?? 44755);

/** CLIENT-mode invoke: forward the tool call to whichever instance owns the port. */
const forwardToOwner: Invoke = async (tool, args, timeoutMs, target) => {
  const ms = timeoutMs ?? 60_000;
  let res: Response;
  try {
    res = await fetch(`http://127.0.0.1:${PORT}/invoke`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ tool, args, timeoutMs: ms, target }),
      signal: AbortSignal.timeout(ms + 5_000),
    });
  } catch {
    throw new Error(
      "Couldn't reach the bridge that owns the Studio connection. The chat that " +
        "started it may have closed — reopen/restart Claude Code.",
    );
  }
  const data = (await res.json()) as { success: boolean; response?: string; error?: string };
  if (!data.success) throw new Error(data.error || "Studio reported an error");
  return data.response ?? "";
};

/** CLIENT-mode studio list: ask the owner which Studios are connected. */
const listFromOwner: ListStudios = async () => {
  const res = await fetch(`http://127.0.0.1:${PORT}/studios`, { signal: AbortSignal.timeout(5_000) });
  if (res.status === 404) {
    throw new Error(
      "The bridge daemon is an older version without multi-Studio support. Restart it: " +
        "launchctl kickstart -k gui/$(id -u)/com.claudebridge.daemon",
    );
  }
  return ((await res.json()) as { studios: Awaited<ReturnType<ListStudios>> }).studios;
};

async function main(): Promise<void> {
  const bridge = new StudioBridge();
  let invoke: Invoke;
  let listStudios: ListStudios = listFromOwner;

  try {
    await bridge.start();
    invoke = (tool, args, timeoutMs, target) => bridge.call(tool, args, timeoutMs, target);
    listStudios = async () => bridge.list();
    log("owner mode — bound the port; serving the Studio plugin directly");
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === "EADDRINUSE") {
      invoke = forwardToOwner;
      log("client mode — another instance owns the port; forwarding tool calls to it");
    } else {
      log("Failed to start HTTP bridge:", String(err));
      invoke = forwardToOwner; // best effort
    }
  }

  await startMcp(invoke, listStudios);
}

main().catch((err) => {
  log("fatal:", String(err));
  process.exit(1);
});
