# Claude Studio Bridge

Wires **Claude Code** directly into **Roblox Studio** with full Explorer access.
Claude can read your place's hierarchy, inspect properties, read and edit scripts,
create/delete/move instances, set properties, and run arbitrary Luau — all live in
your open place.

## How it works

A Studio plugin can't accept incoming connections, so communication is inverted:
the plugin long-polls a tiny local server, and Claude talks to that server over MCP.

```
┌──────────────┐   MCP / stdio   ┌─────────────────────┐  HTTP long-poll  ┌────────────────┐
│  Claude Code │ ───────────────▶│  bridge (Node/TS)   │◀────────────────▶│ Studio plugin  │
│  (you, here) │                 │  :44755 + MCP tools │   GET /request   │ (Luau, modular)│
└──────────────┘                 └─────────────────────┘   POST /response └────────────────┘
```

Claude calls a tool → the bridge queues a command → the plugin (polling) picks it
up, runs it against the DataModel, and posts the result back → Claude sees it.

- **`bridge/`** — Node/TypeScript. One process is both the MCP server (stdio, launched
  by Claude Code) and the HTTP bridge on `127.0.0.1:44755` (the plugin connects here).
- **`plugin/`** — the Studio plugin, modular Luau, built with Rojo into a `.rbxm`.

## Tools Claude gets

| Tool | What it does |
|------|--------------|
| `get_tree` | Explore the Explorer hierarchy under a path |
| `get_properties` | Read properties + attributes of an instance |
| `search_instances` | Find instances by name substring and/or class |
| `get_script_source` | Read a script's full source |
| `set_script_source` | Replace a script's source (live editor buffer) |
| `create_instance` | Create an instance under a parent, with properties |
| `delete_instance` | Destroy an instance and its descendants |
| `set_properties` | Set properties / rename / reparent |
| `run_code` | Execute arbitrary Luau in edit mode, capture output |
| `get_console_output` | Return recent output/warnings/errors |
| `run_in_play_mode` | Start a real playtest, run test Luau in it, capture output/errors, auto-stop |
| `play_control` | Manually start/stop a playtest (`start_play` / `run_server` / `stop`) |

Every mutating call is wrapped in a single **undo step** (Ctrl/Cmd-Z reverts it).

### Self-verification (play mode)

`run_in_play_mode` is what lets Claude check its own work at runtime without you
present. It starts a real playtest, injects a server-side test script that runs your
Luau, captures every print/warning/error (and any return value), then automatically
ends the test and returns structured JSON:

```jsonc
{ "success": true, "ranWithoutError": true, "logs": [...], "errors": [],
  "errorCount": 0, "durationSeconds": 0.4, "timedOut": false, "returned": "42" }
```

So Claude can, e.g., write a module, then run
`require(game.ServerScriptService.MyModule).doThing()` in an actual running game and
read back whether it worked. `mode` is `start_play` (Play Solo, has a Player) or
`run_server` (Run, server only). It works because `StudioTestService:ExecutePlayModeAsync`
yields until the in-game `EndTest` fires — that's the channel results cross back on.

## Setup (already done on this machine)

The installer steps below have already run; they're here for reference / other machines.

1. **Build the bridge**
   ```bash
   cd bridge && npm install && npm run build
   ```
2. **Build the plugin into your Studio Plugins folder**
   ```bash
   ./scripts/build-plugin.sh
   # -> ~/Documents/Roblox/Plugins/ClaudeBridge.rbxm
   ```
3. **Register the MCP server with Claude Code** — added to `~/.claude.json` as
   `mcpServers.roblox-studio` (absolute paths to node + `bridge/dist/index.js`).
   A portable copy lives in [`.mcp.json`](.mcp.json) — drop it into any project
   folder you open Claude Code in to enable the tools there.

## Using it

1. **Restart Roblox Studio** and open a place. The **Claude Bridge** plugin
   auto-loads and connects (look for a `Claude` toolbar with a *Claude Bridge*
   button — it's active/highlighted when connected, and prints
   `[Claude Bridge] Connected` to the Output window).
2. **Restart Claude Code** so it launches the MCP server. The `roblox-studio`
   tools will appear.
3. The **first** time Claude reads or edits a script, Studio prompts you to grant
   the plugin **script-modification permission** — click *Allow*, then retry.
4. Ask away, e.g.:
   - "What's in ServerScriptService?"
   - "Read the PlayerData module and add a save-on-leave handler."
   - "Create a red neon Part named Beacon at (0, 50, 0) in Workspace."
   - "Find every script that references `DataStoreService`."

### Property value format

Primitives pass through. Roblox datatypes use a tagged object:

```jsonc
{ "__type": "Vector3", "x": 0, "y": 50, "z": 0 }
{ "__type": "Color3", "r": 1, "g": 0, "b": 0 }        // or {"hex":"#ff0000"}
{ "__type": "UDim2", "xScale": 0, "xOffset": 100, "yScale": 0, "yOffset": 50 }
{ "__type": "CFrame", "x": 0, "y": 5, "z": 0, "orientation": { "x": 0, "y": 90, "z": 0 } }
{ "__type": "Enum", "value": "Material.Neon" }
{ "__type": "Instance", "path": "game.Workspace.Part" }
```

Anything not covered? `run_code` is the escape hatch — Claude can do it in raw Luau.

## After editing the code

- Changed `plugin/src/**`? Re-run `./scripts/build-plugin.sh`, then restart Studio
  (or toggle the plugin button off/on).
- Changed `bridge/src/**`? Run `cd bridge && npm run build`, then restart Claude Code.

## Verifying / testing

- **Bridge logic, no Studio needed:** `cd bridge && npm run build && node smoke-test.mjs`
  (simulates both Claude and the plugin; should print `🎉 ALL CHECKS PASSED`).
- **Live connection:** run the bridge standalone with `cd bridge && npm start`, open
  Studio, then `curl http://127.0.0.1:44755/health` → `{"ok":true,"connected":true}`
  once the plugin is polling.

## Troubleshooting

- **Tools don't appear in Claude Code** — fully quit and reopen Claude Code so it
  re-reads `~/.claude.json`. Confirm the entry: `grep -A4 roblox-studio ~/.claude.json`.
- **"Timed out waiting for Studio"** — Studio isn't open, the plugin is toggled off,
  or HTTP is blocked. Check the Output window for `[Claude Bridge]` messages.
- **Plugin can't reach the bridge** — make sure Studio may make HTTP requests:
  Game Settings → Security → *Allow HTTP Requests*, or run in the command bar:
  ```lua
  game:GetService("HttpService").HttpEnabled = true
  ```
- **Can't read/write scripts** — grant the plugin script-modification permission
  when prompted (Plugin management dialog), then retry.
- **Node path changed (nvm upgrade)** — update the `command` path in `~/.claude.json`
  and `.mcp.json` to the new `which node`.
- **Port 44755 in use** — another bridge instance (e.g. a second Claude Code session)
  owns it. Close the other session, or set `STUDIO_BRIDGE_PORT` on both ends.

## Security

This gives Claude **full read/write** to whatever place is open in Studio, including
running arbitrary Luau. Changes are undoable, but treat it like any tool with write
access — keep it pointed at projects you're actively working on. Toggle the plugin
button off to cut the connection instantly.
