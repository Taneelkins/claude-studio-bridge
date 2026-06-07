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
      "Read the full source code of a Script, LocalScript, or ModuleScript.",
    schema: {
      path: z.string().describe('Path to the script instance.'),
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
      "Return recent Studio output/console lines (prints, warnings, errors) with their message types.",
    schema: {
      count: z
        .number()
        .int()
        .optional()
        .describe("How many of the most recent lines to return. Default 60."),
    },
  },
];
