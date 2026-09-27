/**
 * MCP server. Registers every tool from the catalogue and forwards each call to
 * the Studio plugin through the bridge. Speaks MCP over stdio (how Claude Code
 * launches and talks to it — one process per chat).
 *
 * Each chat is LINKED to one Studio. The link is stored per Claude Code session
 * id (see store.ts), so it survives resuming the chat, and it's addressed by
 * placeId so it re-finds the place after Studio restarts. With exactly one
 * Studio open, the chat links to it automatically on first use.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { TOOLS } from "./tools.js";
import { log } from "./log.js";
import type { StudioSummary, Target } from "./bridge.js";
import { loadBinding, otherChatsByPlace, saveBinding, SESSION_KEY, type Binding } from "./store.js";
import { assetStatus, listUploaded, uploadAsset, type StudioCtx } from "./assets.js";

/** Runs a tool in Studio. Either bridge.call (owner) or an HTTP forward (client). */
export type Invoke = (tool: string, args: unknown, timeoutMs?: number, target?: Target) => Promise<string>;
export type ListStudios = () => Promise<StudioSummary[]>;

// Tools that can legitimately run far longer than the default 60s and need a
// bigger wait window (play mode has to boot a DataModel, run, and tear down).
const LONG_RUNNING: Record<string, (args: any) => number> = {
  run_in_play_mode: (a) => ((Number(a?.timeout) || 10) + 60) * 1000,
  play_control: () => 30_000,
  insert_asset: () => 90_000,
  publish_model: () => 180_000,
  search_scripts: () => 120_000,
};

type Result = { content: { type: "text"; text: string }[]; isError?: boolean };
const ok = (text: string): Result => ({ content: [{ type: "text", text: text || "(no output)" }] });
const fail = (err: unknown): Result => ({
  content: [{ type: "text", text: `Error: ${err instanceof Error ? err.message : String(err)}` }],
  isError: true,
});

export async function startMcp(invoke: Invoke, listStudios: ListStudios): Promise<void> {
  const server = new McpServer({ name: "roblox-studio", version: "2.0.0" });

  let binding: Binding | undefined = loadBinding();
  const envPlace = Number(process.env.STUDIO_BRIDGE_PLACE_ID) || undefined;

  const link = (s: StudioSummary): Binding => {
    binding = {
      studioId: s.studioId,
      placeId: s.placeId || undefined,
      label: s.label,
      updatedAt: new Date().toISOString(),
    };
    saveBinding(binding);
    return binding;
  };

  /**
   * The Target for this chat. Links automatically when the choice is obvious
   * (only one Studio open, or STUDIO_BRIDGE_PLACE_ID names an open place) and
   * returns a note to prepend so Claude knows it happened.
   */
  const resolveTarget = async (): Promise<{ target?: Target; note?: string }> => {
    if (binding) {
      // Refresh studioId if the linked place reopened in a new Studio session.
      if (binding.placeId) {
        const live = (await listStudios().catch(() => [])).filter(
          (s) => s.connected && s.placeId === binding!.placeId,
        );
        if (live.length === 1 && live[0].studioId !== binding.studioId) link(live[0]);
      }
      return { target: { studioId: binding.studioId, placeId: binding.placeId } };
    }
    const live = (await listStudios().catch(() => [])).filter((s) => s.connected);
    const pick =
      (envPlace && live.filter((s) => s.placeId === envPlace).length === 1
        ? live.find((s) => s.placeId === envPlace)
        : undefined) ?? (live.length === 1 ? live[0] : undefined);
    if (pick) {
      link(pick);
      return {
        target: { studioId: pick.studioId, placeId: pick.placeId || undefined },
        note: `[Linked this chat to ${pick.label}. Use select_studio to change.]`,
      };
    }
    return {};
  };

  const invokeLinked = async (tool: string, args: unknown, timeoutMs?: number) => {
    const { target, note } = await resolveTarget();
    const text = await invoke(tool, args, timeoutMs, target);
    return note ? `${note}\n${text}` : text;
  };

  const ctx: StudioCtx = {
    invoke: (tool, args, timeoutMs) => invokeLinked(tool, args, timeoutMs),
    current: async () => {
      const { target } = await resolveTarget();
      const live = (await listStudios()).filter((s) => s.connected);
      return (
        live.find((s) => s.studioId === target?.studioId) ??
        live.find((s) => target?.placeId && s.placeId === target.placeId)
      );
    },
  };

  // ---------- Studio tools (forwarded to the linked Studio's plugin) ----------

  for (const tool of TOOLS) {
    server.tool(tool.name, tool.description, tool.schema, async (args) => {
      try {
        return ok(await invokeLinked(tool.name, args, LONG_RUNNING[tool.name]?.(args)));
      } catch (err) {
        return fail(err);
      }
    });
  }

  // ---------- Multi-Studio linking ----------

  server.tool(
    "list_studios",
    "List every Roblox Studio window connected to the bridge (place name, placeId, studioId, busy), and show which one THIS chat is linked to. Other chats can be linked to other Studios at the same time.",
    {},
    async () => {
      try {
        const studios = await listStudios();
        const others = otherChatsByPlace();
        const lines = studios.map((s) => {
          const mine =
            binding && (binding.studioId === s.studioId || (binding.placeId && binding.placeId === s.placeId));
          const n = s.placeId ? others.get(s.placeId) ?? 0 : 0;
          return (
            `${mine ? "▶ " : "  "}${s.label}  [studioId ${s.studioId}]` +
            `${s.connected ? "" : " (disconnected)"}${s.busy ? " (busy)" : ""}` +
            `${n ? ` — also linked from ${n} other chat${n > 1 ? "s" : ""}` : ""}`
          );
        });
        const head = binding
          ? `This chat is linked to: ${binding.label}`
          : "This chat isn't linked to a Studio yet (it auto-links if only one is open).";
        return ok([head, "", ...(lines.length ? lines : ["No Studios connected."])].join("\n"));
      } catch (err) {
        return fail(err);
      }
    },
  );

  server.tool(
    "select_studio",
    "Link THIS chat to one Studio so every tool call runs there (other chats keep their own links). Match by placeId, studioId, or part of the place name. The link is remembered when the chat is resumed and survives Studio restarts. Pass studio:\"none\" to unlink.",
    {
      studio: z.string().describe('placeId, studioId, or a case-insensitive part of the place name. "none" unlinks.'),
    },
    async ({ studio }) => {
      try {
        if (studio.toLowerCase() === "none") {
          binding = undefined;
          saveBinding(undefined);
          return ok("Unlinked. This chat will auto-link if exactly one Studio is open.");
        }
        const live = (await listStudios()).filter((s) => s.connected);
        const q = studio.toLowerCase();
        let matches = live.filter((s) => s.studioId === studio || String(s.placeId) === studio);
        if (!matches.length) matches = live.filter((s) => s.placeName.toLowerCase().includes(q));
        if (matches.length !== 1) {
          return fail(
            new Error(
              `${matches.length ? "Ambiguous" : "No match"} for "${studio}". Connected:\n` +
                live.map((s) => `  - ${s.label}  [studioId ${s.studioId}]`).join("\n"),
            ),
          );
        }
        const b = link(matches[0]);
        return ok(`Linked this chat to ${b.label}. (chat ${SESSION_KEY.slice(0, 8)})`);
      } catch (err) {
        return fail(err);
      }
    },
  );

  // ---------- Assets ----------

  server.tool(
    "upload_asset",
    "Upload a local file to Roblox and get back its asset id, ready to use. Images (.png/.jpg/.bmp/.tga) -> returns the imageId for ImageLabel.Image / Texture etc.; audio (.mp3/.ogg/.wav/.flac) -> Sound.SoundId; models (.fbx/.gltf/.glb/.rbxm) -> use insert_asset; video (.mp4/.mov). Owner defaults to the linked place's owner (user or group). With an Open Cloud API key everything works; without one, PNG images still upload through Studio. Identical files are de-duplicated (force:true re-uploads). Every upload is logged for list_uploaded_assets.",
    {
      file_path: z.string().describe("Absolute path to the file on this computer."),
      name: z.string().optional().describe("Asset name (max 50 chars). Default the file name."),
      description: z.string().optional(),
      asset_type: z
        .enum(["Decal", "Image", "Audio", "Model", "Video", "Animation"])
        .optional()
        .describe("Override the type inferred from the extension."),
      creator_type: z.enum(["user", "group"]).optional().describe("Override the owner type."),
      creator_id: z.number().int().optional().describe("Override the owner id (userId or groupId)."),
      force: z.boolean().optional().describe("Upload even if this exact file was uploaded before."),
    },
    async (args) => {
      try {
        return ok(await uploadAsset(args, ctx));
      } catch (err) {
        return fail(err);
      }
    },
  );

  server.tool(
    "get_asset_status",
    "Check an uploaded asset: moderation state (Open Cloud, if a key is set), catalog info from Studio, and what the upload ledger knows (file, imageId, owner).",
    { asset_id: z.string().describe("Asset id.") },
    async ({ asset_id }) => {
      try {
        return ok(await assetStatus(asset_id, ctx));
      } catch (err) {
        return fail(err);
      }
    },
  );

  server.tool(
    "list_uploaded_assets",
    "Search the ledger of everything uploaded through the bridge (name, type, ids, source file). Use it to find an id you uploaded earlier instead of re-uploading.",
    {
      query: z.string().optional().describe("Part of the name / file path, or an exact id."),
      type: z.string().optional().describe('Filter by type, e.g. "Audio", "Decal", "Image", "Model".'),
    },
    async ({ query, type }) => ok(listUploaded(query, type)),
  );

  await server.connect(new StdioServerTransport());
  log(
    `MCP server ready (stdio), chat ${SESSION_KEY}` +
      (binding ? ` linked to ${binding.label}` : " (not linked yet)"),
  );
}
