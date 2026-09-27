/**
 * Asset uploads. Two routes, picked automatically:
 *
 *  1. Open Cloud (needs an API key — run `node scripts/set-api-key.mjs` once):
 *     images, audio, models (.fbx/.gltf/.glb/.rbxm), video, animations.
 *  2. Studio-native, no key: PNG images go through the linked Studio, which
 *     builds an EditableImage and publishes it with AssetService:CreateAssetAsync
 *     as the logged-in Studio user/group.
 *
 * Every upload is recorded in ~/.claude-studio-bridge/assets.json. Re-uploading
 * the identical file returns the existing id instead of making a duplicate.
 */
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { decodePng, isPng } from "./png.js";
import {
  addAsset,
  loadAssets,
  loadConfig,
  updateAsset,
  type AssetRecord,
  type Creator,
} from "./store.js";
import type { StudioSummary } from "./bridge.js";

const OPEN_CLOUD = "https://apis.roblox.com/assets/v1";
const STUDIO_IMAGE_MAX = 1024;

/** Runs a plugin tool in THIS chat's linked Studio. */
export interface StudioCtx {
  invoke: (tool: string, args: unknown, timeoutMs?: number) => Promise<string>;
  /** The linked Studio, if one is connected (undefined otherwise). */
  current: () => Promise<StudioSummary | undefined>;
}

const EXT: Record<string, { type: string; mime: string }> = {
  ".png": { type: "Decal", mime: "image/png" },
  ".jpg": { type: "Decal", mime: "image/jpeg" },
  ".jpeg": { type: "Decal", mime: "image/jpeg" },
  ".bmp": { type: "Decal", mime: "image/bmp" },
  ".tga": { type: "Decal", mime: "image/tga" },
  ".mp3": { type: "Audio", mime: "audio/mpeg" },
  ".ogg": { type: "Audio", mime: "audio/ogg" },
  ".wav": { type: "Audio", mime: "audio/wav" },
  ".flac": { type: "Audio", mime: "audio/flac" },
  ".fbx": { type: "Model", mime: "model/fbx" },
  ".gltf": { type: "Model", mime: "model/gltf+json" },
  ".glb": { type: "Model", mime: "model/gltf-binary" },
  ".rbxm": { type: "Model", mime: "model/x-rbxm" },
  ".rbxmx": { type: "Model", mime: "model/x-rbxm" },
  ".mp4": { type: "Video", mime: "video/mp4" },
  ".mov": { type: "Video", mime: "video/mov" },
};

export interface UploadArgs {
  file_path: string;
  name?: string;
  description?: string;
  asset_type?: string;
  creator_type?: "user" | "group";
  creator_id?: number;
  force?: boolean;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Decides who will own the upload: explicit args > linked place's owner > config > Studio user. */
function pickCreator(args: UploadArgs, studio?: StudioSummary): Creator | undefined {
  if (args.creator_type && args.creator_id) return { type: args.creator_type, id: args.creator_id };
  if (studio?.placeId && studio.creatorId) {
    return { type: studio.creatorType === "Group" ? "group" : "user", id: studio.creatorId };
  }
  const cfg = loadConfig();
  if (cfg.creator) return cfg.creator;
  if (studio?.userId) return { type: "user", id: studio.userId };
  return undefined;
}

/** Decal and Image uploads of the same picture are interchangeable for de-duplication. */
function sameKind(a: string, b: string): boolean {
  const norm = (t: string) => (t === "Image" ? "Decal" : t);
  return norm(a) === norm(b);
}

function contentId(id: string): string {
  return `rbxassetid://${id}`;
}

function describe(rec: AssetRecord, reused: boolean): string {
  const lines = [
    reused
      ? `Already uploaded earlier (same file) — reusing it. Pass force:true to upload again.`
      : `Uploaded "${rec.name}" as ${rec.type} via ${rec.method === "studio" ? "Studio" : "Open Cloud"}.`,
    `assetId: ${rec.assetId}`,
  ];
  if (rec.imageId) {
    lines.push(`imageId: ${rec.imageId}   <- use this for ImageLabel.Image / Decal.Texture / etc.`);
    lines.push(`content: ${contentId(rec.imageId)}`);
  } else if (rec.type === "Decal") {
    lines.push(
      `imageId: (not resolved yet — call resolve_image_id with ${rec.assetId} once Studio is connected)`,
    );
  } else {
    lines.push(`content: ${contentId(rec.assetId)}`);
  }
  if (rec.creator) lines.push(`owner: ${rec.creator.type} ${rec.creator.id}`);
  lines.push(`Moderation may take a minute; get_asset_status shows the state.`);
  return lines.join("\n");
}

// ---------- Open Cloud ----------

async function openCloudUpload(
  apiKey: string,
  data: Buffer,
  fileName: string,
  mime: string,
  assetType: string,
  name: string,
  description: string,
  creator: Creator,
): Promise<string> {
  const request = {
    assetType,
    displayName: name.slice(0, 50),
    description: description.slice(0, 1000),
    creationContext: {
      creator: creator.type === "group" ? { groupId: String(creator.id) } : { userId: String(creator.id) },
    },
  };
  const form = new FormData();
  form.append("request", JSON.stringify(request));
  form.append("fileContent", new Blob([new Uint8Array(data)], { type: mime }), fileName);

  const res = await fetch(`${OPEN_CLOUD}/assets`, {
    method: "POST",
    headers: { "x-api-key": apiKey },
    body: form,
  });
  const body = (await res.json().catch(() => ({}))) as any;
  if (!res.ok) {
    throw new Error(
      `Open Cloud rejected the upload (HTTP ${res.status}): ${body.message ?? JSON.stringify(body)}` +
        (res.status === 401 || res.status === 403
          ? `\nCheck the API key has the "assets" API (Read + Write) and that it's allowed for ${creator.type} ${creator.id}.`
          : ""),
    );
  }

  // The create call returns a long-running operation; poll it for the asset id.
  let op = body;
  const opId = op.operationId ?? String(op.path ?? "").split("/").pop();
  const deadline = Date.now() + 120_000;
  while (!op.done) {
    if (Date.now() > deadline) throw new Error(`Upload still processing after 2 min (operation ${opId}).`);
    await sleep(1500);
    const r = await fetch(`${OPEN_CLOUD}/operations/${opId}`, { headers: { "x-api-key": apiKey } });
    op = await r.json();
  }
  if (op.error) throw new Error(`Upload failed: ${op.error.message ?? JSON.stringify(op.error)}`);
  const assetId = op.response?.assetId;
  if (!assetId) throw new Error(`Upload finished without an asset id: ${JSON.stringify(op)}`);
  return String(assetId);
}

/** Decal id -> Image id, via Studio (loads the Decal and reads its Texture). Retries while it processes. */
export async function resolveImageId(ctx: StudioCtx, decalId: string): Promise<string | undefined> {
  for (let attempt = 0; attempt < 6; attempt++) {
    try {
      const out = JSON.parse(await ctx.invoke("resolve_image_id", { asset_id: Number(decalId) }, 30_000));
      if (out.imageId) {
        updateAsset(decalId, { imageId: String(out.imageId) });
        return String(out.imageId);
      }
    } catch {
      // not ready yet / Studio not connected
    }
    await sleep(2500);
  }
  return undefined;
}

// ---------- entry points ----------

export async function uploadAsset(args: UploadArgs, ctx: StudioCtx): Promise<string> {
  const file = path.resolve(args.file_path.replace(/^~(?=$|\/)/, process.env.HOME ?? "~"));
  if (!fs.existsSync(file)) throw new Error(`File not found: ${file}`);
  const data = fs.readFileSync(file);
  const ext = path.extname(file).toLowerCase();
  const kind = EXT[ext];
  if (!kind && !args.asset_type) {
    throw new Error(`Don't know what asset type ${ext} is. Pass asset_type, or use one of: ${Object.keys(EXT).join(" ")}`);
  }
  const assetType = args.asset_type ?? kind.type;
  const mime = kind?.mime ?? "application/octet-stream";
  const name = args.name ?? path.basename(file, ext);
  const description = args.description ?? "";
  const sha256 = createHash("sha256").update(data).digest("hex");

  const studio = await ctx.current().catch(() => undefined);
  const creator = pickCreator(args, studio);

  if (!args.force) {
    const prior = loadAssets().find(
      (a) =>
        a.sha256 === sha256 &&
        sameKind(a.type, assetType) &&
        (!creator || !a.creator || (a.creator.type === creator.type && a.creator.id === creator.id)),
    );
    if (prior) {
      if (prior.type === "Decal" && !prior.imageId) prior.imageId = await resolveImageId(ctx, prior.assetId);
      return describe(prior, true);
    }
  }

  const { apiKey } = loadConfig();
  let rec: AssetRecord;

  if (apiKey) {
    if (!creator) {
      throw new Error(
        "Don't know who should own this asset. Link a published place (select_studio), pass " +
          "creator_type + creator_id, or set a default with scripts/set-api-key.mjs.",
      );
    }
    const assetId = await openCloudUpload(apiKey, data, path.basename(file), mime, assetType, name, description, creator);
    rec = {
      assetId, type: assetType, name, file, sha256, creator,
      placeId: studio?.placeId || undefined, method: "open-cloud", uploadedAt: new Date().toISOString(),
    };
    addAsset(rec);
    if (assetType === "Decal") rec.imageId = await resolveImageId(ctx, assetId);
  } else if (assetType === "Decal" || assetType === "Image") {
    // No key: publish through Studio as an Image asset (logged-in Studio account).
    if (!isPng(data)) {
      throw new Error(
        "Without an Open Cloud API key only PNG images can be uploaded (through Studio). " +
          `Convert it first (e.g. \`sips -s format png "${file}" --out out.png\`) or set up a key: node scripts/set-api-key.mjs`,
      );
    }
    const img = decodePng(data);
    if (img.width > STUDIO_IMAGE_MAX || img.height > STUDIO_IMAGE_MAX) {
      throw new Error(
        `Studio uploads are limited to ${STUDIO_IMAGE_MAX}x${STUDIO_IMAGE_MAX}; this is ${img.width}x${img.height}. ` +
          `Resize (e.g. \`sips -Z 1024 "${file}" --out small.png\`) or set up an API key (up to 8000x8000).`,
      );
    }
    const out = JSON.parse(
      await ctx.invoke(
        "create_image_asset",
        {
          width: img.width,
          height: img.height,
          pixels_b64: img.pixels.toString("base64"),
          name,
          description,
          creator_type: creator?.type,
          creator_id: creator?.id,
        },
        180_000,
      ),
    );
    rec = {
      assetId: String(out.assetId), imageId: String(out.assetId), type: "Image", name, file, sha256,
      creator: out.creatorId ? { type: out.creatorType === "Group" ? "group" : "user", id: out.creatorId } : creator,
      placeId: studio?.placeId || undefined, method: "studio", uploadedAt: new Date().toISOString(),
    };
    addAsset(rec);
  } else {
    throw new Error(
      `Uploading ${assetType} files needs an Open Cloud API key (Studio can only publish images and in-place models itself).\n` +
        `One-time setup: create a key at https://create.roblox.com/dashboard/credentials with the "assets" API ` +
        `(Read + Write), then run in a terminal:  node ~/claude-studio-bridge/scripts/set-api-key.mjs`,
    );
  }
  return describe(rec, false);
}

export async function assetStatus(assetId: string, ctx: StudioCtx): Promise<string> {
  const { apiKey } = loadConfig();
  const known = loadAssets().find((a) => a.assetId === assetId || a.imageId === assetId);
  const parts: string[] = [];
  if (known) parts.push(`Ledger: ${JSON.stringify(known)}`);
  if (apiKey) {
    const r = await fetch(
      `${OPEN_CLOUD}/assets/${assetId}?readMask=assetType,displayName,description,moderationResult,revisionId,creationContext`,
      { headers: { "x-api-key": apiKey } },
    );
    parts.push(`Open Cloud (HTTP ${r.status}): ${await r.text()}`);
  }
  try {
    parts.push(`Studio product info: ${await ctx.invoke("get_asset_info", { asset_id: Number(assetId) })}`);
  } catch (e) {
    if (!apiKey) parts.push(`Studio lookup failed: ${(e as Error).message}`);
  }
  return parts.join("\n\n") || "Nothing known about that asset.";
}

export function listUploaded(query?: string, type?: string): string {
  const q = query?.toLowerCase();
  const rows = loadAssets().filter(
    (a) =>
      (!type || a.type.toLowerCase() === type.toLowerCase()) &&
      (!q || a.name.toLowerCase().includes(q) || (a.file ?? "").toLowerCase().includes(q) || a.assetId === query),
  );
  if (!rows.length) return "No uploaded assets match.";
  return rows
    .slice(-100)
    .map((a) =>
      `${a.name} — ${a.type} ${a.assetId}` +
      (a.imageId && a.imageId !== a.assetId ? ` (image ${a.imageId})` : "") +
      ` — ${a.uploadedAt.slice(0, 10)}${a.file ? ` — ${a.file}` : ""}`,
    )
    .join("\n");
}
