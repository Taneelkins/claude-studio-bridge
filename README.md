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
| `edit_script` | Replace an exact snippet in a script (no full-file resend) |
| `search_scripts` | Grep every script's source → `{path, line, text}` |
| `get_selection` / `set_selection` | Read / set what's selected in the Explorer |
| `undo` / `redo` | Step Studio's change history |
| `list_studios` / `select_studio` | See connected Studios; link this chat to one |
| `upload_asset` | Upload a local image/audio/model/video → asset id (+ image id) |
| `get_asset_status` | Moderation state + catalog info for an asset |
| `list_uploaded_assets` | Search the ledger of everything uploaded through the bridge |
| `insert_asset` | Insert any asset by id (model, mesh, sound, image…) |
| `get_asset_info` | Catalog info for any asset id |
| `resolve_image_id` | Decal id → the Image id `ImageLabel.Image` needs |
| `publish_model` | Publish an instance from the place as a Model asset |

`get_script_source` also takes `start_line` / `end_line` for numbered excerpts.

## Multiple Studios, one link per chat

Every Studio window identifies itself (place name, placeId, a per-session studioId)
and gets its **own command queue** on the bridge. A command only ever runs in the
Studio it was addressed to.

Each Claude Code chat is **linked** to one Studio:
- With only one Studio open, a chat links to it automatically on first use.
- With several open, an unlinked chat refuses to guess. Call `select_studio`
  (by place name, placeId, or studioId), and `list_studios` shows the choices.
- The link is stored per chat session in `~/.claude-studio-bridge/bindings.json`,
  so a resumed chat reconnects to the same place. It's matched by placeId, so it
  survives restarting Studio.
- Different chats can drive different Studios at the same time.
- Optional per-project default: set `STUDIO_BRIDGE_PLACE_ID` in that project's
  `.mcp.json` `env` and chats there auto-link to that place.

## Assets

`upload_asset` takes a file path on this computer and returns ready-to-use ids:

| File | Becomes | Use it as |
|------|---------|-----------|
| .png .jpg .bmp .tga | Decal → **imageId** resolved automatically | `ImageLabel.Image`, `Decal.Texture`, … = `rbxassetid://<imageId>` |
| .mp3 .ogg .wav .flac | Audio | `Sound.SoundId` |
| .fbx .gltf .glb .rbxm | Model | `insert_asset` |
| .mp4 .mov | Video | `VideoFrame.Video` |

The asset's owner defaults to the **linked place's owner**, so group games get
group-owned assets. Identical files are de-duplicated, and every upload is logged in
`~/.claude-studio-bridge/assets.json` (`list_uploaded_assets`).

**Two upload routes, picked automatically:**
1. **Open Cloud** (recommended, does everything). One-time setup: create a key at
   <https://create.roblox.com/dashboard/credentials> with the **Assets** API (Read + Write),
   create it under the group for group games, then run in a terminal:
   ```bash
   node scripts/set-api-key.mjs
   ```
   The key is stored in `~/.claude-studio-bridge/config.json` (chmod 600), not in the repo.
2. **No key:** PNG images up to 1024×1024 still upload *through Studio*
   (EditableImage + `AssetService:CreateAssetAsync`, as the logged-in Studio account).
   `publish_model` also needs no key.

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
   # -> ~/Documents/Roblox/Plugins/TaruTools.rbxm
   ```
3. **Register the MCP server with Claude Code** — added to `~/.claude.json` as
   `mcpServers.roblox-studio` (absolute paths to node + `bridge/dist/index.js`).
   A portable copy lives in [`.mcp.json`](.mcp.json) — drop it into any project
   folder you open Claude Code in to enable the tools there.
4. **Install the always-on daemon** (recommended) — a tiny background service that
   permanently owns the bridge port, so the Studio connection stays up no matter how
   many Claude Code chats you open or close. Auto-starts at login, auto-restarts on crash:
   ```bash
   ./scripts/install-daemon.sh      # remove later with ./scripts/uninstall-daemon.sh
   ```
   Without it, chats elect one of themselves as the owner, and closing *that* chat drops
   the link until another is elected. With it, that never happens.

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
- Changed the plugin and want other devices to get it? Rebuild the shipped artifact:
  `rojo build plugin/default.project.json -o release/TaruTools.rbxm`, then commit it.

## Transfer to another machine

The code is on GitHub; only the per-device glue (paths, plugin folder, auto-start) needs
setting up. The plugin ships **prebuilt** in `release/TaruTools.rbxm`, so the target
device doesn't need Rojo — only Node.js.

### Windows
In PowerShell (Node.js must be installed):
```powershell
git clone https://github.com/Taneelkins/claude-studio-bridge
cd claude-studio-bridge
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```
This builds the bridge, copies the plugin to `%LOCALAPPDATA%\Roblox\Plugins`, registers the
MCP server in `%USERPROFILE%\.claude.json`, and installs the always-on daemon as a Scheduled
Task `ClaudeBridgeDaemon` (starts at logon, restarts on crash). Then restart Claude Code and
open Studio.
- Verify daemon: `Invoke-RestMethod http://127.0.0.1:44755/health`
- Uninstall daemon: `Unregister-ScheduledTask -TaskName ClaudeBridgeDaemon -Confirm:$false`

### Another Mac
```bash
git clone https://github.com/Taneelkins/claude-studio-bridge
cd claude-studio-bridge/bridge && npm install && npm run build && cd ..
cp release/TaruTools.rbxm ~/Documents/Roblox/Plugins/
node scripts/register-mcp.mjs     # registers MCP with this device's node + paths
./scripts/install-daemon.sh       # always-on daemon (LaunchAgent)
```

`register-mcp.mjs` auto-detects the device's own Node path and the repo location, so there's
nothing to hand-edit per machine.

### Moving a single conversation between machines
Claude Code keeps chats as `~/.claude/projects/<encoded-abs-path>/<session-id>.jsonl`, keyed
by the project's absolute path (which differs across OSes). To carry one chat over: copy its
`.jsonl` into the matching project folder on the target machine. Because the old machine's
paths are baked into the transcript, rewrite them first with:
```bash
node scripts/port-conversation.mjs <in.jsonl> <out.jsonl> "/old/path=>C:\new\path" [...]
```
It parses each line as JSON, so the output stays valid regardless of path separators. Keep the
output filename equal to the session id. (Note: Claude Code chats are local files; unlike
Claude.ai web chats they don't auto-sync. The built-in `claude remote-control` lets you drive
one machine's live session from another device instead.)

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
- **"N Studios are connected and this chat hasn't picked one"** — call `select_studio`.
  An *old* chat (started before v2) can't select: type `/mcp` in it and Reconnect
  `roblox-studio`.
- **Studio shows as "old plugin"** in `list_studios` — restart that Studio so it
  loads the rebuilt plugin.
- **Multiple Claude Code chats** — supported. With the **daemon** installed (recommended;
  `./scripts/install-daemon.sh`), it permanently owns the port and every chat forwards to
  it, so you can open/close chats freely without dropping the connection. Without the
  daemon, chats elect an owner among themselves and closing *that* chat drops the link
  until another is elected. (Override the port on all ends with `STUDIO_BRIDGE_PORT`.)
- **Connection keeps dropping when chats close** — install the daemon (above); that's
  exactly what it fixes. Check it's alive: `curl -s localhost:44755/health` and
  `tail ~/claude-studio-bridge/bridge/daemon.log`.

## Security

This gives Claude **full read/write** to whatever place is open in Studio, including
running arbitrary Luau. Changes are undoable, but treat it like any tool with write
access — keep it pointed at projects you're actively working on. Toggle the plugin
button off to cut the connection instantly.
