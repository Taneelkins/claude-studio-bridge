/**
 * Small JSON stores kept outside the repo in ~/.claude-studio-bridge (override
 * with STUDIO_BRIDGE_HOME), so they survive rebuilds and never get committed:
 *
 *   config.json    — Open Cloud API key + default asset creator (written by
 *                    scripts/set-api-key.mjs, chmod 600). ROBLOX_API_KEY env wins.
 *   bindings.json  — which Studio each chat is linked to, keyed by Claude Code
 *                    session id, so a resumed chat reconnects to the same place.
 *   assets.json    — ledger of every asset uploaded through the bridge, so the
 *                    same file isn't uploaded twice and ids are easy to look up.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const HOME_DIR =
  process.env.STUDIO_BRIDGE_HOME || path.join(os.homedir(), ".claude-studio-bridge");

function file(name: string): string {
  return path.join(HOME_DIR, name);
}

export function readJson<T>(name: string, fallback: T): T {
  try {
    return JSON.parse(fs.readFileSync(file(name), "utf8")) as T;
  } catch {
    return fallback;
  }
}

/** Atomic write (tmp + rename) so concurrent chats never see a half-written file. */
export function writeJson(name: string, data: unknown, mode = 0o600): void {
  fs.mkdirSync(HOME_DIR, { recursive: true });
  const tmp = `${file(name)}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), { mode });
  fs.renameSync(tmp, file(name));
}

// ---------- config ----------

export interface Creator {
  type: "user" | "group";
  id: number;
}

export interface BridgeConfig {
  apiKey?: string;
  /** Default owner for uploads when the linked place's owner can't be used. */
  creator?: Creator;
}

export function loadConfig(): BridgeConfig {
  const cfg = readJson<BridgeConfig>("config.json", {});
  if (process.env.ROBLOX_API_KEY) cfg.apiKey = process.env.ROBLOX_API_KEY;
  return cfg;
}

// ---------- chat <-> studio bindings ----------

export interface Binding {
  studioId?: string;
  placeId?: number;
  label: string;
  updatedAt: string;
}

/** Stable per-chat key. Claude Code passes the chat's session id to MCP servers. */
export const SESSION_KEY = process.env.CLAUDE_CODE_SESSION_ID || `pid-${process.pid}`;

export function loadBinding(): Binding | undefined {
  return readJson<Record<string, Binding>>("bindings.json", {})[SESSION_KEY];
}

export function saveBinding(binding: Binding | undefined): void {
  const all = readJson<Record<string, Binding>>("bindings.json", {});
  if (binding) all[SESSION_KEY] = binding;
  else delete all[SESSION_KEY];
  // Keep the file from growing forever: drop links untouched for 60 days.
  const cutoff = Date.now() - 60 * 24 * 3600_000;
  for (const [k, b] of Object.entries(all)) {
    if (Date.parse(b.updatedAt) < cutoff) delete all[k];
  }
  writeJson("bindings.json", all);
}

/** How many OTHER chats are linked to each placeId (for list_studios). */
export function otherChatsByPlace(): Map<number, number> {
  const counts = new Map<number, number>();
  for (const [k, b] of Object.entries(readJson<Record<string, Binding>>("bindings.json", {}))) {
    if (k === SESSION_KEY || !b.placeId) continue;
    counts.set(b.placeId, (counts.get(b.placeId) ?? 0) + 1);
  }
  return counts;
}

// ---------- asset ledger ----------

export interface AssetRecord {
  assetId: string;
  /** For images uploaded as Decals: the underlying Image id you put in ImageLabel.Image etc. */
  imageId?: string;
  type: string;
  name: string;
  file?: string;
  sha256?: string;
  creator?: Creator;
  placeId?: number;
  method: "open-cloud" | "studio";
  uploadedAt: string;
}

export function loadAssets(): AssetRecord[] {
  return readJson<AssetRecord[]>("assets.json", []);
}

export function addAsset(rec: AssetRecord): void {
  const all = loadAssets();
  all.push(rec);
  writeJson("assets.json", all);
}

export function updateAsset(assetId: string, patch: Partial<AssetRecord>): void {
  const all = loadAssets();
  const rec = all.find((a) => a.assetId === assetId);
  if (!rec) return;
  Object.assign(rec, patch);
  writeJson("assets.json", all);
}
