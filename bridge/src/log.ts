/**
 * Logging helper.
 *
 * CRITICAL: stdout is reserved for the MCP stdio JSON-RPC channel. Writing
 * anything to stdout corrupts the protocol and Claude Code will drop the
 * connection. Every diagnostic message MUST go to stderr.
 */
export function log(...args: unknown[]): void {
  const line = args
    .map((a) => (typeof a === "string" ? a : JSON.stringify(a)))
    .join(" ");
  process.stderr.write(`[studio-bridge] ${line}\n`);
}
