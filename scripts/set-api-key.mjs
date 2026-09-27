// One-time setup for asset uploads through Open Cloud (audio, models, big
// images, video). Stores the key in ~/.claude-studio-bridge/config.json with
// owner-only permissions — never in the repo, never pasted into a chat.
//
//   node scripts/set-api-key.mjs            (prompts, input hidden)
//   node scripts/set-api-key.mjs --clear    (removes the key)
//
// Create the key at https://create.roblox.com/dashboard/credentials :
//   API System: "Assets" -> Read + Write. Add your IP or 0.0.0.0/0 to the allowlist.
//   For a group game, create the key under the GROUP (or give it group access)
//   so uploads can be owned by the group.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

const dir = process.env.STUDIO_BRIDGE_HOME || path.join(os.homedir(), ".claude-studio-bridge");
const file = path.join(dir, "config.json");
let cfg = {};
try {
  cfg = JSON.parse(fs.readFileSync(file, "utf8"));
} catch {}

function save() {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2), { mode: 0o600 });
  fs.chmodSync(file, 0o600);
}

if (process.argv.includes("--clear")) {
  delete cfg.apiKey;
  save();
  console.log(`Removed the API key from ${file}`);
  process.exit(0);
}

function ask(question, hidden = false) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) {
      rl._writeToOutput = (s) => {
        if (s.includes(question)) rl.output.write(s);
        else rl.output.write("*");
      };
    }
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write("\n");
      resolve(answer.trim());
    });
  });
}

const key = await ask("Open Cloud API key (input hidden): ", true);
if (!key) {
  console.log("No key entered; nothing changed.");
  process.exit(1);
}

// Quick sanity check against Open Cloud (a 404 for a bogus operation means the key was accepted).
const probe = await fetch("https://apis.roblox.com/assets/v1/operations/00000000-0000-0000-0000-000000000000", {
  headers: { "x-api-key": key },
}).catch(() => undefined);
if (probe && (probe.status === 401 || probe.status === 403)) {
  console.log(`Warning: Roblox rejected this key (HTTP ${probe.status}). Check it has the Assets API and your IP is allowed.`);
}

cfg.apiKey = key;

const who = await ask(
  "Default owner when no place is linked — 'user <id>' or 'group <id>' (Enter to skip; uploads normally go to the linked place's owner): ",
);
const m = /^(user|group)\s+(\d+)$/i.exec(who);
if (m) cfg.creator = { type: m[1].toLowerCase(), id: Number(m[2]) };

save();
console.log(`Saved to ${file} (readable only by you). Chats pick it up on the next upload — no restart needed.`);
