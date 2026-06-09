// Cross-platform: registers (or updates) the roblox-studio MCP server in
// ~/.claude.json, using the Node that runs this script and an absolute entry
// path. Safe merge — preserves everything else in the file.
//
//   node scripts/register-mcp.mjs [absolute-path-to-bridge/dist/index.js]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const entry =
  process.argv[2] || path.resolve(import.meta.dirname, "../bridge/dist/index.js");
const nodePath = process.execPath; // absolute path to *this* device's node
const cfgPath = path.join(os.homedir(), ".claude.json");

let cfg = {};
try {
  cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
} catch {
  // no file yet, or unreadable -> start fresh
}

cfg.mcpServers = cfg.mcpServers || {};
cfg.mcpServers["roblox-studio"] = {
  type: "stdio",
  command: nodePath,
  args: [entry],
};

fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log(`Registered roblox-studio MCP server in ${cfgPath}`);
console.log(`  command: ${nodePath}`);
console.log(`  args:    ${entry}`);
