// Run export_to_blender from a terminal, through the running bridge (daemon or a chat).
//   node scripts/export-to-blender.mjs <instance path> [out_dir] [placeId]
// e.g. node scripts/export-to-blender.mjs Workspace.AssetBaseplate.Carriage ~/Desktop/exports
// Needs the bridge built (cd bridge && npm run build) and Studio connected.
import { exportToBlender } from "../bridge/dist/export.js";

const [, , instancePath, outDir, placeId] = process.argv;
if (!instancePath) {
  console.error("usage: node scripts/export-to-blender.mjs <instance path> [out_dir] [placeId]");
  process.exit(1);
}
const port = Number(process.env.STUDIO_BRIDGE_PORT) || 44755;
const base = `http://127.0.0.1:${port}`;

const studios = (await (await fetch(`${base}/studios`)).json()).studios.filter((s) => s.connected);
const studio = placeId ? studios.find((s) => String(s.placeId) === placeId) : studios.length === 1 ? studios[0] : undefined;
if (!studio) {
  console.error(
    studios.length
      ? `Pick a Studio by placeId:\n${studios.map((s) => `  ${s.placeId}  ${s.label}`).join("\n")}`
      : "No Studio connected to the bridge.",
  );
  process.exit(1);
}
const target = { studioId: studio.studioId, placeId: studio.placeId };

const ctx = {
  invoke: async (tool, args, timeoutMs) => {
    const res = await fetch(`${base}/invoke`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ tool, args, timeoutMs, target }),
    });
    const body = await res.json();
    if (!body.success) throw new Error(body.error);
    return body.response;
  },
  current: async () => studio,
};

const started = Date.now();
console.log(await exportToBlender({ path: instancePath, out_dir: outDir }, ctx));
console.log(`(${((Date.now() - started) / 1000).toFixed(1)}s)`);
