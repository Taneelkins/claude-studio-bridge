--!strict
-- Maps tool names to their handlers and routes a call. Tool names match the MCP
-- tool names defined in bridge/src/tools.ts.

local Tools = script.Parent.Tools

local handlers: { [string]: (any) -> string } = {
	get_tree = require(Tools.GetTree),
	get_properties = require(Tools.GetProperties),
	search_instances = require(Tools.SearchInstances),
	get_script_source = require(Tools.GetScriptSource),
	set_script_source = require(Tools.SetScriptSource),
	create_instance = require(Tools.CreateInstance),
	delete_instance = require(Tools.DeleteInstance),
	set_properties = require(Tools.SetProperties),
	run_code = require(Tools.RunCode),
	get_console_output = require(Tools.GetConsoleOutput),
	run_in_play_mode = require(Tools.RunInPlayMode),
	play_control = require(Tools.PlayControl),
}

-- Tools not wrapped in an undo recording: read-only queries, plus play-mode
-- tools (which manage their own session, not the edit DataModel).
local SKIP_RECORDING: { [string]: boolean } = {
	get_tree = true,
	get_properties = true,
	search_instances = true,
	get_script_source = true,
	get_console_output = true,
	run_in_play_mode = true,
	play_control = true,
}

local Dispatcher = {}

function Dispatcher.skipRecording(toolName: string): boolean
	return SKIP_RECORDING[toolName] == true
end

function Dispatcher.dispatch(toolName: string, args: any): string
	local handler = handlers[toolName]
	if not handler then
		error("Unknown tool: " .. tostring(toolName))
	end
	return handler(args or {})
end

return Dispatcher
