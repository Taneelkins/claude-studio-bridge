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

// Pretend to be the plugin: pull one command, post back a canned response.
async function actAsPluginOnce(makeResponse) {
  for (let i = 0; i < 80; i++) {
    const res = await fetch(BASE + "/request", { method: "GET" });
    if (res.status === 200) {
      const cmd = await res.json();
      await fetch(BASE + "/response", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: cmd.id, success: true, response: makeResponse(cmd) }),
      });
      return cmd;
    }
    if (res.status !== 423) await sleep(100);
  }
  throw new Error("plugin sim: no command arrived");
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
  check(`tools/list returns 10 tools (${names.length})`, names.length === 10);
  check("includes run_code", names.includes("run_code"));
  check("includes set_script_source", names.includes("set_script_source"));

  const health = await (await fetch(BASE + "/health")).json();
  check("health endpoint ok", health.ok === true);

  // Full round-trip through a tool call.
  const callPromise = rpc("tools/call", {
    name: "get_tree",
    arguments: { path: "game", depth: 1 },
  });
  const cmd = await actAsPluginOnce((c) =>
    JSON.stringify({ echoedArgs: c.args, tree: { name: "Game", className: "DataModel" } }),
  );
  check("plugin received {get_tree:{...}}", !!cmd.args.get_tree && cmd.args.get_tree.path === "game");

  const result = await callPromise;
  const text = result.result?.content?.[0]?.text ?? "";
  check("tool result flows back to Claude", text.includes("DataModel") && text.includes("get_tree"));

  // Error propagation: plugin reports failure.
  const errPromise = rpc("tools/call", { name: "delete_instance", arguments: { path: "game" } });
  await (async () => {
    for (let i = 0; i < 80; i++) {
      const res = await fetch(BASE + "/request", { method: "GET" });
      if (res.status === 200) {
        const c = await res.json();
        await fetch(BASE + "/response", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ id: c.id, success: false, response: "Refusing to destroy the DataModel" }),
        });
        return;
      }
      if (res.status !== 423) await sleep(100);
    }
  })();
  const errResult = await errPromise;
  check("plugin errors surface as isError", errResult.result?.isError === true);

  console.log(failures === 0 ? "\n🎉 ALL CHECKS PASSED" : `\n${failures} CHECK(S) FAILED`);
  child.kill();
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  child.kill();
  process.exit(1);
});
