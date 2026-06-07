// End-to-end test of the bridge with no Studio required.
// Speaks MCP JSON-RPC over stdio to dist/index.js while simulating the Studio
// plugin over HTTP, proving the full Claude -> MCP -> bridge -> plugin loop.
//
//   node smoke-test.mjs   (run from the bridge/ folder after `npm run build`)
import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

const PORT = 44755;
const BASE = `http://127.0.0.1:${PORT}`;

const child = spawn("node", ["dist/index.js"], { stdio: ["pipe", "pipe", "inherit"] });

// --- MCP stdio client (newline-delimited JSON-RPC) ---
let buf = "";
const pending = new Map();
let nextId = 1;
child.stdout.on("data", (chunk) => {
  buf += chunk.toString();
  let idx;
  while ((idx = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue;
    }
    if (msg.id != null && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});
const rpc = (method, params) =>
  new Promise((resolve) => {
    const id = nextId++;
    pending.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
const notify = (method, params) =>
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");

// --- Simulated Studio plugin: a continuous long-poll loop, like the real one ---
const responders = {}; // toolName -> (innerArgs) => { ok, text }
const received = [];
let pluginRunning = true;
async function pluginLoop() {
  while (pluginRunning) {
    let res;
    try {
      res = await fetch(BASE + "/request", { method: "GET" });
    } catch {
      await sleep(100);
      continue;
    }
    if (res.status === 200) {
      const cmd = await res.json();
      received.push(cmd);
      const tool = Object.keys(cmd.args)[0];
      const inner = cmd.args[tool];
      const r = responders[tool] ? responders[tool](inner) : { ok: false, text: `no responder for ${tool}` };
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

async function main() {
  await sleep(600);

  const init = await rpc("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "smoke-test", version: "1.0.0" },
  });
  check("initialize", !!init.result);
  notify("notifications/initialized", {});

  const tools = await rpc("tools/list", {});
  const names = (tools.result?.tools ?? []).map((t) => t.name);
  check(`tools/list returns 12 tools (${names.length})`, names.length === 12);
  for (const n of ["run_code", "set_script_source", "run_in_play_mode", "play_control"]) {
    check(`includes ${n}`, names.includes(n));
  }

  // Set up plugin responders, then start the continuous poll loop and let it
  // establish a connection before issuing tool calls (fail-fast needs a poll).
  responders.get_tree = (args) => ({
    ok: true,
    text: JSON.stringify({ echoedArgs: args, tree: { name: "Game", className: "DataModel" } }),
  });
  responders.run_in_play_mode = () => ({
    ok: true,
    text: JSON.stringify({
      mode: "start_play",
      result: { success: true, logs: [{ level: "output", message: "hi from play" }], errorCount: 0, durationSeconds: 0.2 },
    }),
  });
  responders.delete_instance = () => ({ ok: false, text: "Refusing to destroy the DataModel" });
  pluginLoop();
  await sleep(300);

  const health = await (await fetch(BASE + "/health")).json();
  check("health shows connected", health.ok === true && health.connected === true);

  const tree = await rpc("tools/call", { name: "get_tree", arguments: { path: "game", depth: 1 } });
  const treeText = tree.result?.content?.[0]?.text ?? "";
  check("get_tree round-trips", treeText.includes("DataModel") && treeText.includes("game"));
  check("plugin received {get_tree:{...}}", received.some((c) => c.args.get_tree?.path === "game"));

  const play = await rpc("tools/call", {
    name: "run_in_play_mode",
    arguments: { code: "print('hi from play')", timeout: 5 },
  });
  const playText = play.result?.content?.[0]?.text ?? "";
  check("run_in_play_mode round-trips", playText.includes("hi from play") && playText.includes("success"));

  const del = await rpc("tools/call", { name: "delete_instance", arguments: { path: "game" } });
  check("plugin errors surface as isError", del.result?.isError === true);

  console.log(failures === 0 ? "\n🎉 ALL CHECKS PASSED" : `\n${failures} CHECK(S) FAILED`);
  pluginRunning = false;
  child.kill();
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  pluginRunning = false;
  child.kill();
  process.exit(1);
});
