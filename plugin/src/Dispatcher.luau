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
}

-- Tools that never modify the DataModel; we skip undo recording for these.
local READ_ONLY: { [string]: boolean } = {
	get_tree = true,
	get_properties = true,
	search_instances = true,
	get_script_source = true,
	get_console_output = true,
}

local Dispatcher = {}

function Dispatcher.isReadOnly(toolName: string): boolean
	return READ_ONLY[toolName] == true
end

function Dispatcher.dispatch(toolName: string, args: any): string
	local handler = handlers[toolName]
	if not handler then
		error("Unknown tool: " .. tostring(toolName))
	end
	return handler(args or {})
end

return Dispatcher
