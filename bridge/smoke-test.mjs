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
const PORT = Number(process.env.STUDIO_BRIDGE_PORT ?? 44755);
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

// Simulated Studio plugin: a continuous long-poll loop, like the real one.
const responders = {};
const received = [];
let pluginRunning = true;
async function pluginLoop() {
  while (pluginRunning) {
    let res;
    try { res = await fetch(BASE + "/request", { method: "GET" }); }
    catch { await sleep(100); continue; }
    if (res.status === 200) {
      const cmd = await res.json();
      received.push(cmd);
      const tool = Object.keys(cmd.args)[0];
      const r = responders[tool] ? responders[tool](cmd.args[tool]) : { ok: false, text: `no responder for ${tool}` };
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

let failures = 0;
const check = (label, cond) => {
  console.log(`${cond ? "✅" : "❌"} ${label}`);
  if (!cond) failures++;
};

const owner = spawn("node", ["dist/index.js"], { stdio: ["pipe", "pipe", "inherit"] });
let clientProc;

async function main() {
  await sleep(600);
  const ownerClient = makeClient(owner);
  await handshake(ownerClient, "smoke-owner");

  const tools = await ownerClient.rpc("tools/list", {});
  const names = (tools.result?.tools ?? []).map((t) => t.name);
  check(`tools/list returns 12 tools (${names.length})`, names.length === 12);
  for (const n of ["run_code", "set_script_source", "run_in_play_mode", "play_control"]) {
    check(`includes ${n}`, names.includes(n));
  }

  responders.get_tree = (args) => ({
    ok: true,
    text: JSON.stringify({ echoedArgs: args, tree: { name: "Game", className: "DataModel" } }),
  });
  responders.run_in_play_mode = () => ({
    ok: true,
    text: JSON.stringify({ mode: "start_play", result: { success: true, logs: [{ level: "output", message: "hi from play" }], errorCount: 0 } }),
  });
  responders.delete_instance = () => ({ ok: false, text: "Refusing to destroy the DataModel" });
  pluginLoop();
  await sleep(300);

  const health = await (await fetch(BASE + "/health")).json();
  check("health shows connected", health.ok === true && health.connected === true);

  const tree = await ownerClient.rpc("tools/call", { name: "get_tree", arguments: { path: "game", depth: 1 } });
  check("owner: get_tree round-trips", (tree.result?.content?.[0]?.text ?? "").includes("DataModel"));

  const play = await ownerClient.rpc("tools/call", { name: "run_in_play_mode", arguments: { code: "print('x')", timeout: 5 } });
  check("owner: run_in_play_mode round-trips", (play.result?.content?.[0]?.text ?? "").includes("hi from play"));

  const del = await ownerClient.rpc("tools/call", { name: "delete_instance", arguments: { path: "game" } });
  check("owner: errors surface as isError", del.result?.isError === true);

  // --- Second instance must detect the bound port and forward through the owner ---
  clientProc = spawn("node", ["dist/index.js"], { stdio: ["pipe", "pipe", "inherit"] });
  await sleep(600);
  const client = makeClient(clientProc);
  await handshake(client, "smoke-client");
  const beforeCount = received.length;
  const ctree = await client.rpc("tools/call", { name: "get_tree", arguments: { path: "game", depth: 1 } });
  check("client: get_tree forwards through owner", (ctree.result?.content?.[0]?.text ?? "").includes("DataModel"));
  check("client: command actually reached the plugin", received.length > beforeCount);

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
