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
	edit_script = require(Tools.EditScript),
	search_scripts = require(Tools.SearchScripts),
	get_selection = require(Tools.GetSelection),
	set_selection = require(Tools.SetSelection),
	undo = require(Tools.UndoRedo).undo,
	redo = require(Tools.UndoRedo).redo,
	insert_asset = require(Tools.InsertAsset),
	get_asset_info = require(Tools.GetAssetInfo),
	resolve_image_id = require(Tools.ResolveImageId),
	publish_model = require(Tools.PublishModel),
	create_image_asset = require(Tools.CreateImageAsset),
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
	search_scripts = true,
	get_selection = true,
	set_selection = true,
	-- undo/redo drive the history themselves; a recording around them would break it.
	undo = true,
	redo = true,
	get_asset_info = true,
	resolve_image_id = true,
	publish_model = true,
	create_image_asset = true,
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
