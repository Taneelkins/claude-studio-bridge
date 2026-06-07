/**
 * MCP server. Registers every tool from the catalogue and forwards each call to
 * the Studio plugin through the bridge. Speaks MCP over stdio (how Claude Code
 * launches and talks to it).
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StudioBridge } from "./bridge.js";
import { TOOLS } from "./tools.js";
import { log } from "./log.js";

export async function startMcp(bridge: StudioBridge): Promise<void> {
  const server = new McpServer({
    name: "roblox-studio",
    version: "1.0.0",
  });

  for (const tool of TOOLS) {
    server.tool(tool.name, tool.description, tool.schema, async (args) => {
      try {
        const text = await bridge.call(tool.name, args);
        return { content: [{ type: "text", text: text || "(no output)" }] };
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error: ${(err as Error).message}` }],
          isError: true,
        };
      }
    });
  }

  await server.connect(new StdioServerTransport());
  log(`MCP server ready with ${TOOLS.length} tools (stdio)`);
}
