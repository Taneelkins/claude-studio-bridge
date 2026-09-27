/**
 * Tool catalogue. Each entry is exposed to Claude as an MCP tool and forwarded
 * verbatim to the Studio plugin, which has a handler of the same name.
 *
 * Tool names are snake_case on both sides (here and in plugin/src/Tools).
 */
import { z } from "zod";

export interface ToolDef {
  name: string;
  description: string;
  schema: z.ZodRawShape;
}

/** Shared explainer for the JSON value format the plugin understands. */
const VALUE_FORMAT = `Property values: primitives (number/string/bool) pass through. Roblox datatypes use a tagged object:
- Vector3: {"__type":"Vector3","x":0,"y":5,"z":0}
- Vector2: {"__type":"Vector2","x":0,"y":0}
- Color3:  {"__type":"Color3","r":1,"g":0,"b":0}  (components 0-1)  or  {"__type":"Color3","hex":"#ff8800"}
- UDim:    {"__type":"UDim","scale":0,"offset":10}
- UDim2:   {"__type":"UDim2","xScale":0,"xOffset":100,"yScale":0,"yOffset":50}
- CFrame:  {"__type":"CFrame","x":0,"y":5,"z":0}  (optionally add "orientation":{"x":0,"y":90,"z":0} in degrees)
- Enum:    {"__type":"Enum","value":"Material.Neon"}
- BrickColor: {"__type":"BrickColor","value":"Bright red"}
- Instance ref: {"__type":"Instance","path":"game.Workspace.Part"}
- NumberRange: {"__type":"NumberRange","min":0,"max":10}`;

export const TOOLS: ToolDef[] = [
  {
    name: "get_tree",
    description:
      "Explore the Roblox Explorer hierarchy. Returns a nested tree of {name, className, path, children}. Start here to understand a place's structure.",
    schema: {
      path: z
        .string()
        .optional()
        .describe(
          'Instance path, e.g. "game", "Workspace", "game.ServerScriptService". Default "game".',
        ),
      depth: z
        .number()
        .int()
        .min(1)
        .max(15)
        .optional()
        .describe("Levels to descend. Default 3."),
      max_nodes: z
        .number()
        .int()
        .optional()
        .describe("Cap on total nodes returned (safety). Default 400."),
    },
  },
  {
    name: "get_properties",
    description:
      "Read properties and attributes of an instance. If `properties` is omitted, returns a useful default set plus all attributes. Specify property names (standard Roblox API names) to read exactly those.",
    schema: {
      path: z.string().describe('Instance path, e.g. "game.Workspace.Part".'),
      properties: z
        .array(z.string())
        .optional()
        .describe('Property names to read, e.g. ["Anchored","Position","Size"].'),
    },
  },
  {
    name: "search_instances",
    description:
      "Search the DataModel for instances by name substring and/or class name. Returns matches as {name, className, path}.",
    schema: {
      query: z
        .string()
        .optional()
        .describe("Case-insensitive substring to match against instance Name."),
      class_name: z
        .string()
        .optional()
        .describe('Exact ClassName filter, e.g. "Part", "Script". Uses IsA.'),
      ancestor: z
        .string()
        .optional()
        .describe('Where to search under. Default "game".'),
      limit: z.number().int().optional().describe("Max results. Default 100."),
    },
  },
  {
    name: "get_script_source",
    description:
      "Read the source code of a Script, LocalScript, or ModuleScript. Pass start_line/end_line to read just a range (returned with line numbers).",
    schema: {
      path: z.string().describe('Path to the script instance.'),
      start_line: z.number().int().optional().describe("First line to return (1-based). Enables numbered output."),
      end_line: z.number().int().optional().describe("Last line to return (inclusive)."),
    },
  },
  {
    name: "set_script_source",
    description:
      "Replace the entire source code of a Script, LocalScript, or ModuleScript. Edits the live editor buffer via ScriptEditorService so it shows immediately. Undoable.",
    schema: {
      path: z.string().describe("Path to the script instance."),
      source: z.string().describe("The complete new Luau source."),
    },
  },
  {
    name: "create_instance",
    description:
      "Create a new instance of a class under a parent. Returns the new instance's path. Undoable.\n\n" +
      VALUE_FORMAT,
    schema: {
      class_name: z
        .string()
        .describe('Roblox class to create, e.g. "Part", "Folder", "Script".'),
      parent: z.string().describe("Path of the parent instance."),
      name: z.string().optional().describe("Name for the new instance."),
      properties: z
        .record(z.string(), z.any())
        .optional()
        .describe("Initial properties to set (see value format)."),
    },
  },
  {
    name: "delete_instance",
    description: "Destroy (delete) an instance and all its descendants. Undoable.",
    schema: {
      path: z.string().describe("Path of the instance to destroy."),
    },
  },
  {
    name: "set_properties",
    description:
      "Set one or more properties on an instance. Set Name to rename; set Parent (as an Instance ref) to move/reparent. Reports per-property success. Undoable.\n\n" +
      VALUE_FORMAT,
    schema: {
      path: z.string().describe("Path of the instance to modify."),
      properties: z
        .record(z.string(), z.any())
        .describe("Map of property name -> value (see value format)."),
    },
  },
  {
    name: "run_code",
    description:
      "Execute arbitrary Luau inside Studio (edit mode) and return captured print/warn/error output and any return values. The most powerful tool — use it for anything the dedicated tools don't cover (bulk edits, complex datatypes, queries). Runs at plugin security. Undoable as a single step.",
    schema: {
      command: z.string().describe("Luau source to execute."),
    },
  },
  {
    name: "get_console_output",
    description:
      "Return recent Studio output/console lines (prints, warnings, errors) with their message types. NOTE: in edit mode this is the edit session's output; to capture a running game's output use run_in_play_mode.",
    schema: {
      count: z
        .number()
        .int()
        .optional()
        .describe("How many of the most recent lines to return. Default 60."),
    },
  },
  {
    name: "run_in_play_mode",
    description:
      "Start a real playtest, run the given Luau inside the RUNNING game (server context), capture all output/warnings/errors and any return value, then automatically stop. This is the way to verify runtime behavior end-to-end without the user present. Returns JSON: {success, ranWithoutError, logs[], errors[], errorCount, durationSeconds, timedOut, returned}. Use print() to surface values; thrown errors are caught and reported.",
    schema: {
      code: z
        .string()
        .describe(
          "Luau to run in the running game (server side). e.g. require a module and assert behavior, then print results.",
        ),
      timeout: z
        .number()
        .optional()
        .describe("Max seconds to let it run before auto-stopping. Default 10, max 120."),
      mode: z
        .enum(["start_play", "run_server"])
        .optional()
        .describe(
          '"start_play" = Play Solo (a local Player exists); "run_server" = Run (server only, faster, no player). Default start_play.',
        ),
    },
  },
  {
    name: "play_control",
    description:
      "Manually start or stop a playtest session. Does NOT capture output — use run_in_play_mode when you need the logs. Handy to start a session, inspect via other means, then stop.",
    schema: {
      mode: z
        .enum(["start_play", "run_server", "stop"])
        .describe('"start_play" / "run_server" to begin, "stop" to end the current session.'),
    },
  },
  {
    name: "edit_script",
    description:
      "Surgical script edit: replace an exact snippet of a script's source with new text, instead of resending the whole file. `old_string` must match exactly (whitespace included) and be unique unless replace_all is true. Returns the edited line range. Undoable.",
    schema: {
      path: z.string().describe("Path to the script instance."),
      old_string: z.string().describe("Exact text to find (include enough surrounding lines to be unique)."),
      new_string: z.string().describe("Replacement text."),
      replace_all: z.boolean().optional().describe("Replace every occurrence. Default false."),
    },
  },
  {
    name: "search_scripts",
    description:
      "Grep the source of every script under an ancestor. Returns {path, line, text} matches. Use to find where something is defined/used across the whole place.",
    schema: {
      pattern: z.string().describe("Text to find (plain substring by default)."),
      lua_pattern: z.boolean().optional().describe("Treat `pattern` as a Luau string pattern instead of plain text."),
      case_sensitive: z.boolean().optional().describe("Default false."),
      ancestor: z.string().optional().describe('Where to search. Default "game".'),
      limit: z.number().int().optional().describe("Max matches. Default 200."),
    },
  },
  {
    name: "get_selection",
    description:
      "Return what the user currently has selected in Studio's Explorer ({name, className, path} each). Great for 'fix the thing I selected'.",
    schema: {},
  },
  {
    name: "set_selection",
    description: "Select instances in Studio's Explorer (so the user can see what you mean). Pass an empty list to clear.",
    schema: {
      paths: z.array(z.string()).describe("Instance paths to select."),
    },
  },
  {
    name: "undo",
    description: "Undo the last Studio change(s) (same as Ctrl/Cmd-Z). Every bridge write is one undo step.",
    schema: {
      steps: z.number().int().min(1).max(50).optional().describe("How many steps. Default 1."),
    },
  },
  {
    name: "redo",
    description: "Redo the last undone Studio change(s).",
    schema: {
      steps: z.number().int().min(1).max(50).optional().describe("How many steps. Default 1."),
    },
  },
  {
    name: "insert_asset",
    description:
      "Insert a Roblox asset (model, mesh, package, decal, sound, etc.) into the place by id, e.g. a model you just uploaded. Returns the paths of what was inserted. Undoable.",
    schema: {
      asset_id: z.number().int().describe("The asset id."),
      parent: z.string().optional().describe('Where to put it. Default "Workspace".'),
      unpack: z
        .boolean()
        .optional()
        .describe("Put the asset's contents directly under parent instead of the wrapper Model. Default true."),
    },
  },
  {
    name: "get_asset_info",
    description:
      "Look up any asset id's catalog info from Studio (name, type, creator, created/updated). Works for assets you don't own.",
    schema: {
      asset_id: z.number().int().describe("The asset id."),
    },
  },
  {
    name: "resolve_image_id",
    description:
      "Convert a Decal asset id into the Image id that ImageLabel.Image / Texture / SurfaceAppearance etc. actually need (rbxassetid://<imageId>). upload_asset does this automatically for images.",
    schema: {
      asset_id: z.number().int().describe("Decal asset id."),
    },
  },
  {
    name: "publish_model",
    description:
      "Publish an instance from the place (a Model, Part, Folder, UI, etc.) as a Roblox Model asset owned by the place owner (or the Studio user), returning the new asset id. Pass asset_id to publish a new version of an existing model instead. Uses the logged-in Studio account; no API key needed.",
    schema: {
      path: z.string().describe("Instance to publish."),
      name: z.string().optional().describe("Asset name. Default the instance name."),
      description: z.string().optional(),
      asset_id: z.number().int().optional().describe("Existing model asset to update instead of creating a new one."),
    },
  },
];

