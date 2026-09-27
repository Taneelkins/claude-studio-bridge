// End-to-end test of the bridge with no Studio required.
// Speaks MCP JSON-RPC over stdio while simulating the Studio plugin over HTTP,
// proving the full Claude -> MCP -> bridge -> plugin loop, AND that a second
// (client-mode) instance forwards its calls through the owner.
//
//   node smoke-test.mjs   (run from the bridge/ folder after `npm run build`)
import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

// Use an isolated port (override via STUDIO_BRIDGE_PORT) so this never collides
// with a real Studio plugin polling the default 44755.
const PORT = Number(process.env.STUDIO_BRIDGE_PORT ?? 44799);
process.env.STUDIO_BRIDGE_PORT = String(PORT);
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
process.env.STUDIO_BRIDGE_HOME = fs.mkdtempSync(path.join(os.tmpdir(), "bridge-smoke-"));
const BASE = `http://127.0.0.1:${PORT}`;

// MCP stdio client bound to a spawned bridge process.
function makeClient(child) {
  let buf = "";
  const pending = new Map();
  let nextId = 1;
  child.stdout.on("data", (chunk) => {
    buf += chunk.toString();
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      let m;
      try { m = JSON.parse(line); } catch { continue; }
      if (m.id != null && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    }
  });
  const rpc = (method, params) =>
    new Promise((res) => {
      const id = nextId++;
      pending.set(id, res);
      child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  const notify = (m, p) => child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: m, params: p }) + "\n");
  return { rpc, notify };
}

async function handshake(c, name) {
  await c.rpc("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name, version: "1.0.0" },
  });
  c.notify("notifications/initialized", {});
}

// Simulated Studio plugins: continuous long-poll loops, like the real one.
// Each identifies itself (studio id + place info) exactly as the v2 plugin does.
const responders = {};
const received = [];
let pluginRunning = true;
async function pluginLoop(studioId, info) {
  const header = encodeURIComponent(JSON.stringify(info));
  while (pluginRunning) {
    let res;
    try { res = await fetch(`${BASE}/request?studio=${studioId}`, { headers: { "x-studio-info": header } }); }
    catch { await sleep(100); continue; }
    if (res.status === 200) {
      const cmd = await res.json();
      received.push({ studioId, cmd });
      const tool = Object.keys(cmd.args)[0];
      const r = responders[tool] ? responders[tool](cmd.args[tool], studioId) : { ok: false, text: `no responder for ${tool}` };
      await fetch(BASE + "/response", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: cmd.id, success: r.ok, response: r.text }),
      });
    } else if (res.status !== 423) {
      await sleep(100);
    }
  }
}

const text = (r) => r.result?.content?.[0]?.text ?? "";

let failures = 0;
const check = (label, cond) => {
  console.log(`${cond ? "✅" : "❌"} ${label}`);
  if (!cond) failures++;
};

const spawnChat = (session) =>
  spawn("node", ["dist/index.js"], {
    stdio: ["pipe", "pipe", "inherit"],
    env: { ...process.env, CLAUDE_CODE_SESSION_ID: session },
  });
const owner = spawnChat("chat-owner");
let clientProc;

async function main() {
  await sleep(600);
  const ownerClient = makeClient(owner);
  await handshake(ownerClient, "smoke-owner");

  const tools = await ownerClient.rpc("tools/list", {});
  const names = (tools.result?.tools ?? []).map((t) => t.name);
  check(`tools/list returns 27 tools (${names.length})`, names.length === 27);
  for (const n of ["run_code", "set_script_source", "run_in_play_mode", "play_control", "list_studios", "select_studio", "upload_asset", "edit_script"]) {
    check(`includes ${n}`, names.includes(n));
  }

  responders.get_tree = (args, studioId) => ({
    ok: true,
    text: JSON.stringify({ echoedArgs: args, studioId, tree: { name: "Game", className: "DataModel" } }),
  });
  responders.run_in_play_mode = () => ({
    ok: true,
    text: JSON.stringify({ mode: "start_play", result: { success: true, logs: [{ level: "output", message: "hi from play" }], errorCount: 0 } }),
  });
  responders.delete_instance = () => ({ ok: false, text: "Refusing to destroy the DataModel" });
  pluginLoop("studioA", { placeId: 111, gameId: 1, placeName: "Mighty", creatorId: 7, creatorType: "Group" });
  await sleep(300);

  const health = await (await fetch(BASE + "/health")).json();
  check("health shows connected", health.ok === true && health.connected === true);

  const tree = await ownerClient.rpc("tools/call", { name: "get_tree", arguments: { path: "game", depth: 1 } });
  check("owner: get_tree round-trips", (tree.result?.content?.[0]?.text ?? "").includes("DataModel"));

  const play = await ownerClient.rpc("tools/call", { name: "run_in_play_mode", arguments: { code: "print('x')", timeout: 5 } });
  check("owner: run_in_play_mode round-trips", (play.result?.content?.[0]?.text ?? "").includes("hi from play"));

  const del = await ownerClient.rpc("tools/call", { name: "delete_instance", arguments: { path: "game" } });
  check("owner: errors surface as isError", del.result?.isError === true);

  check("owner: auto-linked to the only Studio", text(tree).includes("Linked this chat to Mighty"));

  // --- A second Studio connects: the owner chat must stay on its linked Studio ---
  pluginLoop("studioB", { placeId: 222, gameId: 2, placeName: "Other Game", creatorId: 9, creatorType: "User" });
  await sleep(300);
  const studios = await (await fetch(BASE + "/studios")).json();
  check("/studios lists both Studios", studios.studios.filter((s) => s.connected).length === 2);
  for (let i = 0; i < 4; i++) {
    const t = await ownerClient.rpc("tools/call", { name: "get_tree", arguments: {} });
    check(`owner call ${i + 1} stays in linked Studio A`, text(t).includes('"studioId":"studioA"'));
  }
  const listed = await ownerClient.rpc("tools/call", { name: "list_studios", arguments: {} });
  check("list_studios marks the linked Studio", /▶ Mighty/.test(text(listed)) && text(listed).includes("Other Game"));

  // --- Second instance must detect the bound port and forward through the owner ---
  clientProc = spawnChat("chat-client");
  await sleep(600);
  const client = makeClient(clientProc);
  await handshake(client, "smoke-client");
  const beforeCount = received.length;
  const amb = await client.rpc("tools/call", { name: "get_tree", arguments: {} });
  check("client: unlinked with 2 Studios -> refuses to guess", amb.result?.isError === true && text(amb).includes("hasn't picked one"));
  check("client: refused call reached no plugin", received.length === beforeCount);
  const sel = await client.rpc("tools/call", { name: "select_studio", arguments: { studio: "other" } });
  check("client: select_studio by name", text(sel).includes("Linked this chat to Other Game"));
  const ctree = await client.rpc("tools/call", { name: "get_tree", arguments: { path: "game", depth: 1 } });
  check("client: forwards through owner to Studio B", text(ctree).includes('"studioId":"studioB"'));
  const otree = await ownerClient.rpc("tools/call", { name: "get_tree", arguments: {} });
  check("owner: still in Studio A at the same time", text(otree).includes('"studioId":"studioA"'));

  // --- Link persists per chat session: a restarted client chat comes back to B ---
  clientProc.kill();
  clientProc = spawnChat("chat-client");
  await sleep(600);
  const client2 = makeClient(clientProc);
  await handshake(client2, "smoke-client-2");
  const rtree = await client2.rpc("tools/call", { name: "get_tree", arguments: {} });
  check("resumed chat keeps its Studio link", text(rtree).includes('"studioId":"studioB"'));

  // --- Asset ledger: PNG decode + no-key Studio upload path routes to the linked Studio ---
  const png = path.join(process.env.STUDIO_BRIDGE_HOME, "dot.png");
  // 2x1 RGBA PNG: red, transparent blue
  fs.writeFileSync(png, Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADUlEQVR4nGP4z8AARgAO+gL+9R5MqQAAAABJRU5ErkJggg==", "base64"));
  let gotPixels;
  responders.create_image_asset = (a, studioId) => {
    gotPixels = { ...a, studioId };
    return { ok: true, text: JSON.stringify({ assetId: 555, creatorId: 9, creatorType: "User" }) };
  };
  const up = await client2.rpc("tools/call", { name: "upload_asset", arguments: { file_path: png } });
  check("upload_asset (no key) returns the image id", text(up).includes("rbxassetid://555"));
  check("upload went to the chat's Studio (B)", gotPixels?.studioId === "studioB");
  const px = gotPixels ? Buffer.from(gotPixels.pixels_b64, "base64") : Buffer.alloc(0);
  check("PNG decoded to correct RGBA", gotPixels?.width === 2 && px.equals(Buffer.from([255, 0, 0, 255, 0, 0, 255, 0])));
  const up2 = await client2.rpc("tools/call", { name: "upload_asset", arguments: { file_path: png } });
  check("re-uploading the same file is de-duplicated", text(up2).includes("Already uploaded"));
  const ledger = await client2.rpc("tools/call", { name: "list_uploaded_assets", arguments: { query: "dot" } });
  check("ledger lists the upload", text(ledger).includes("555"));

  console.log(failures === 0 ? "\n🎉 ALL CHECKS PASSED" : `\n${failures} CHECK(S) FAILED`);
  cleanup();
  process.exit(failures === 0 ? 0 : 1);
}

function cleanup() {
  pluginRunning = false;
  owner.kill();
  if (clientProc) clientProc.kill();
}

main().catch((e) => {
  console.error(e);
  cleanup();
  process.exit(1);
});
