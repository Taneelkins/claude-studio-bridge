/**
 * export_to_blender: dumps an instance from the linked Studio into a folder that
 * blender/rbx_import.py rebuilds 1:1 in Blender.
 *
 * Everything on the Studio side goes through the plugin's existing run_code
 * (luau/export.luau), so no plugin update is needed. Replies are paged and
 * zstd-compressed to stay ~1 MB per round trip (much bigger posts from Studio stall).
 *
 *   <out_dir>/<Name>/scene.json       nodes (raw Roblox CFrames/sizes), camera, mesh + texture tables
 *   <out_dir>/<Name>/meshes/<id>.bin  EditableMesh geometry, mesh-local
 *   <out_dir>/<Name>/textures/<id>.png
 *   <out_dir>/<Name>/report.md        everything that became a placeholder, and why
 *   <out_dir>/<Name>/rbx_import.py    the importer, so the folder stands alone
 */
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
import { loadConfig } from "./store.js";
import type { StudioCtx } from "./assets.js";

const LUAU = fileURLToPath(new URL("../luau/export.luau", import.meta.url));
const IMPORTER = fileURLToPath(new URL("../../blender/rbx_import.py", import.meta.url));
const SCAN_PAGE = 1500;
const MESH_BATCH = 6;
const IMAGE_BAND_BYTES = 768 * 1024;
const CALL_TIMEOUT = 120_000;

export interface ExportArgs {
  path: string;
  out_dir?: string;
  meshes?: boolean;
  textures?: boolean;
}

interface Node {
  id: number;
  parent?: number;
  name: string;
  class: string;
  path: string;
  kind?: "shape" | "mesh" | "placeholder";
  mesh?: string;
  texture?: string;
  reason?: string;
  surface?: { colorMap: string };
  special?: { texture: string };
  decals?: { class: string; face: string; texture: string }[];
  [key: string]: unknown;
}

interface ScanPage {
  total: number;
  nodes: Node[];
  skipped: Record<string, number>;
  root: string;
  placeId: number;
  creator: { type: string; id: number };
  camera: unknown;
}

function unpack(text: string): any {
  const m = text.match(/\[RETURN\] RBXEXPORT:([A-Za-z0-9+/=]+)/);
  if (!m) {
    const err = text.match(/\[ERROR\] (.*)/);
    throw new Error(`Studio export script failed: ${err ? err[1] : text.slice(0, 500)}`);
  }
  const out = JSON.parse(zlib.zstdDecompressSync(Buffer.from(m[1], "base64")).toString("utf8"));
  if (out.error) throw new Error(out.error);
  return out;
}

const unpackBuffer = (b64: string): Buffer => zlib.zstdDecompressSync(Buffer.from(b64, "base64"));

/** File-safe key for a content id: the number for rbxassetid://123, otherwise a sanitized string. */
function fileKey(id: string): string {
  const n = id.match(/^(?:rbxassetid:\/\/|https?:\/\/www\.roblox\.com\/asset\/\?id=)(\d+)$/i);
  return n ? n[1] : id.replace(/[^A-Za-z0-9._-]+/g, "_").slice(-80);
}

function crc32(buf: Buffer): number {
  return zlib.crc32(buf);
}

function pngChunk(type: string, data: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td) >>> 0);
  return Buffer.concat([len, td, crc]);
}

/** RGBA8 rows -> PNG. */
function encodePng(width: number, height: number, rgba: Buffer): Buffer {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function sniffExt(data: Buffer): string {
  if (data.subarray(0, 4).toString("hex") === "89504e47") return ".png";
  if (data.subarray(0, 2).toString("hex") === "ffd8") return ".jpg";
  if (data.subarray(0, 4).toString("ascii") === "RIFF") return ".webp";
  return ".bin";
}

export async function exportToBlender(args: ExportArgs, ctx: StudioCtx): Promise<string> {
  if (typeof zlib.zstdDecompressSync !== "function" || typeof zlib.crc32 !== "function") {
    throw new Error(`export_to_blender needs Node 22.15 or newer (this is ${process.version}). Update Node, rebuild, restart Claude Code.`);
  }
  const source = fs.readFileSync(LUAU, "utf8");
  const run = async (params: Record<string, unknown>) => {
    const json = JSON.stringify(params);
    if (json.includes("]=====]")) throw new Error("Argument contains an unsupported sequence: ]=====]");
    const command =
      `local Args = game:GetService("HttpService"):JSONDecode([=====[${json}]=====])\n` + source;
    return unpack(await ctx.invoke("run_code", { command }, CALL_TIMEOUT));
  };

  // ---- scan ----
  const nodes: Node[] = [];
  let first: ScanPage | undefined;
  do {
    const page: ScanPage = await run({ mode: "scan", path: args.path, offset: nodes.length, limit: SCAN_PAGE });
    first ??= page;
    nodes.push(...page.nodes);
    if (!page.nodes.length) break;
  } while (nodes.length < first.total);
  if (!first) throw new Error("Scan returned nothing.");

  const rootName = nodes[0]?.name ?? "Export";
  const outRoot = path.resolve(
    (args.out_dir ?? path.join(process.cwd(), "Blender Export")).replace(/^~(?=$|\/)/, process.env.HOME ?? "~"),
  );
  const dir = path.join(outRoot, rootName.replace(/[\/\\:]/g, "_"));
  fs.mkdirSync(path.join(dir, "meshes"), { recursive: true });
  fs.mkdirSync(path.join(dir, "textures"), { recursive: true });

  const report: string[] = [];
  const placeholders: string[] = [];

  // ---- meshes ----
  const meshTable: Record<string, { file?: string; vertices?: number; faces?: number; error?: string }> = {};
  const meshIds = [...new Set(nodes.filter((n) => n.kind === "mesh" && n.mesh).map((n) => n.mesh!))];
  if (args.meshes === false) {
    for (const id of meshIds) meshTable[id] = { error: "mesh export turned off (meshes:false)" };
  } else {
    for (let i = 0; i < meshIds.length; i += MESH_BATCH) {
      const ids = meshIds.slice(i, i + MESH_BATCH);
      let res: Record<string, any>;
      try {
        res = await run({ mode: "meshes", ids });
      } catch (err) {
        res = Object.fromEntries(ids.map((id) => [id, { error: (err as Error).message }]));
      }
      for (const id of ids) {
        const r = res[id] ?? { error: "no reply" };
        if (r.error) {
          meshTable[id] = { error: r.error };
          continue;
        }
        const file = `meshes/${fileKey(id)}.bin`;
        fs.writeFileSync(path.join(dir, file), unpackBuffer(r.data));
        meshTable[id] = { file, vertices: r.vertices, faces: r.faces };
      }
    }
  }
  for (const n of nodes) {
    if (n.kind === "mesh" && (!n.mesh || meshTable[n.mesh]?.error)) {
      n.kind = "placeholder";
      n.reason = n.mesh ? `mesh ${n.mesh} unreadable: ${meshTable[n.mesh].error}` : "MeshPart has no MeshId";
    }
  }

  // ---- textures ----
  const texTable: Record<string, { file?: string; route?: string; error?: string }> = {};
  const texIds = new Set<string>();
  for (const n of nodes) {
    for (const t of [n.texture, n.surface?.colorMap]) if (t) texIds.add(t);
  }
  const cfg = loadConfig() as { apiKey?: string; keys?: Record<string, string> };
  const owner = `${first.creator.type === "Group" ? "group" : "user"}:${first.creator.id}`;
  const apiKey = cfg.keys?.[owner] ?? cfg.apiKey;
  let cloudNote = apiKey ? "" : "no Open Cloud key set";

  const viaOpenCloud = async (id: string): Promise<Buffer> => {
    const num = fileKey(id);
    if (!/^\d+$/.test(num)) throw new Error("not an asset id");
    const r = await fetch(`https://apis.roblox.com/asset-delivery-api/v1/assetId/${num}`, {
      headers: { "x-api-key": apiKey! },
    });
    if (r.status === 401 || r.status === 403) {
      cloudNote = `Open Cloud key can't download assets (HTTP ${r.status}; needs the legacy-asset:manage permission)`;
      throw new Error(cloudNote);
    }
    if (!r.ok) throw new Error(`Open Cloud HTTP ${r.status}`);
    const { location } = (await r.json()) as { location?: string };
    if (!location) throw new Error("Open Cloud returned no download location");
    const data = Buffer.from(await (await fetch(location)).arrayBuffer());
    return data;
  };

  const viaStudio = async (id: string): Promise<Buffer> => {
    const head = await run({ mode: "image", id, y0: 0, rows: 64 });
    const { width, height } = head;
    const rgba = Buffer.alloc(width * height * 4);
    unpackBuffer(head.data).copy(rgba, 0);
    // size the next bands from how well the first one compressed, ~IMAGE_BAND_BYTES on the wire each
    const wirePerRow = Math.max(1, head.data.length / Math.max(1, head.rows));
    const band = Math.max(1, Math.min(Math.floor(IMAGE_BAND_BYTES / wirePerRow), Math.floor((4 * IMAGE_BAND_BYTES) / (width * 4))));
    for (let y = head.rows; y < height; y += band) {
      const part = await run({ mode: "image", id, y0: y, rows: band });
      unpackBuffer(part.data).copy(rgba, y * width * 4);
    }
    return encodePng(width, height, rgba);
  };

  if (args.textures !== false) {
    for (const id of texIds) {
      const errors: string[] = [];
      for (const [route, fetcher] of [
        ["open-cloud", viaOpenCloud],
        ["studio-editableimage", viaStudio],
      ] as const) {
        if (route === "open-cloud" && (!apiKey || cloudNote)) continue;
        try {
          const data = await fetcher(id);
          const file = `textures/${fileKey(id)}${sniffExt(data)}`;
          fs.writeFileSync(path.join(dir, file), data);
          texTable[id] = { file, route };
          break;
        } catch (err) {
          errors.push(`${route}: ${(err as Error).message}`);
        }
      }
      texTable[id] ??= { error: errors.join("; ") || "no route available" };
    }
  } else {
    for (const id of texIds) texTable[id] = { error: "texture export turned off (textures:false)" };
  }

  // ---- write ----
  const scene = {
    format: "rbx-blender-export",
    version: 1,
    source: { placeId: first.placeId, path: first.root, exportedAt: new Date().toISOString() },
    units: "1 stud = 1 Blender unit; CFrames are raw Roblox (Y-up), converted by the importer",
    camera: first.camera,
    meshes: meshTable,
    textures: texTable,
    nodes,
  };
  fs.writeFileSync(path.join(dir, "scene.json"), JSON.stringify(scene));
  fs.copyFileSync(IMPORTER, path.join(dir, "rbx_import.py"));

  const parts = nodes.filter((n) => n.kind);
  const count = (k: string) => parts.filter((n) => n.kind === k).length;
  for (const n of parts.filter((n) => n.kind === "placeholder")) placeholders.push(`- \`${n.path}\` (${n.class}): ${n.reason}`);
  const texOk = Object.values(texTable).filter((t) => t.file);
  const texBad = Object.entries(texTable).filter(([, t]) => !t.file);

  report.push(
    `# Export report: ${rootName}`,
    "",
    `- Source: \`${first.root}\` in place ${first.placeId}, ${scene.source.exportedAt}`,
    `- Parts: ${count("shape")} primitive, ${count("mesh")} mesh, ${count("placeholder")} placeholder; ${nodes.length - parts.length} containers`,
    `- Unique meshes: ${Object.values(meshTable).filter((m) => m.file).length} read, ${Object.values(meshTable).filter((m) => m.error).length} unreadable`,
    `- Textures: ${texOk.length} fetched (${[...new Set(texOk.map((t) => t.route))].join(", ") || "none"}), ${texBad.length} placeholder` +
      (cloudNote && texIds.size ? ` (${cloudNote})` : ""),
    "",
    "## Placeholders",
    ...(placeholders.length ? placeholders : ["- none"]),
    "",
    "## Textures not fetched",
    ...(texBad.length ? texBad.map(([id, t]) => `- ${id}: ${t.error}`) : ["- none"]),
    "",
    "## Not exported (no geometry)",
    ...(Object.keys(first.skipped).length
      ? Object.entries(first.skipped).map(([c, k]) => `- ${k} × ${c}`)
      : ["- none"]),
  );
  const decals = nodes.filter((n) => n.decals?.length);
  if (decals.length) {
    report.push("", "## Decals / Textures on faces (not imported)");
    for (const n of decals) for (const d of n.decals!) report.push(`- \`${n.path}\` ${d.class} on ${d.face}: ${d.texture}`);
  }
  fs.writeFileSync(path.join(dir, "report.md"), report.join("\n") + "\n");

  return [
    `Exported ${first.root} -> ${dir}`,
    ...report.slice(2, 7),
    `Report: ${path.join(dir, "report.md")}`,
    "",
    "Import into Blender:",
    `  live (blender-mcp execute_blender_code):  exec(open(${JSON.stringify(path.join(dir, "rbx_import.py"))}).read()); import_roblox(${JSON.stringify(dir)})`,
    `  headless:  Blender --background --python ${JSON.stringify(path.join(dir, "rbx_import.py"))} -- ${JSON.stringify(dir)} --save ${JSON.stringify(path.join(dir, rootName + ".blend"))}`,
  ].join("\n");
}
