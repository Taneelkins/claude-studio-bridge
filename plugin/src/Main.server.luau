-- Claude Bridge — Studio plugin entry point.
-- Thin: wires the toolbar toggle and the transport loop to the dispatcher,
-- wrapping every mutating tool call in a single undoable recording.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")

local PluginRef = require(script.Parent.PluginRef)
local Transport = require(script.Parent.Transport)
local Dispatcher = require(script.Parent.Dispatcher)
local PlayMode = require(script.Parent.PlayMode)

-- Expose the plugin object for cross-DataModel settings (used by play mode).
PluginRef.plugin = plugin

-- Only the edit-mode instance owns the bridge connection. In a play/run
-- DataModel this instance just watches (on the server) for a stop signal sent
-- from edit mode, so play_control mode=stop can end the session.
if RunService:IsRunning() then
	if RunService:IsServer() then
		task.spawn(PlayMode.monitorForStop)
	end
	return
end

pcall(PlayMode.cleanup)

local DISABLED_SETTING = "ClaudeBridgeDisabled"

local function handleMessage(message: Transport.Message): (boolean, string)
	local args = message.args
	if type(args) ~= "table" then
		return false, "Invalid message: 'args' must be a table"
	end

	local toolName = next(args)
	if type(toolName) ~= "string" then
		return false, "Invalid message: no tool name"
	end
	local toolArgs = args[toolName]

	if Dispatcher.skipRecording(toolName) then
		local ok, result = pcall(Dispatcher.dispatch, toolName, toolArgs)
		return ok, ok and tostring(result or "") or tostring(result)
	end

	-- Mutating call: wrap so the user can undo it in one step.
	local recording = ChangeHistoryService:TryBeginRecording("ClaudeBridge: " .. toolName)
	local ok, result = pcall(Dispatcher.dispatch, toolName, toolArgs)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end

	return ok, ok and tostring(result or "") or tostring(result)
end

local toolbar = plugin:CreateToolbar("Taru Tools")
local button = toolbar:CreateButton(
	"Claude Bridge",
	"Toggle the connection to Claude Code",
	"rbxasset://textures/ui/GuiImagePlaceholder.png"
)
button.ClickableWhenViewportHidden = true

local connection: Transport.Connection? = nil

local function setConnected(on: boolean)
	if on and not connection then
		connection = Transport.start(handleMessage)
		print("[Claude Bridge] Connected. Claude Code can now read and edit this place.")
	elseif not on and connection then
		connection.stop()
		connection = nil
		print("[Claude Bridge] Disconnected.")
	end
	button:SetActive(connection ~= nil)
	plugin:SetSetting(DISABLED_SETTING, connection == nil)
end

button.Click:Connect(function()
	setConnected(connection == nil)
end)

-- Auto-connect on load unless the user previously turned it off.
if not plugin:GetSetting(DISABLED_SETTING) then
	setConnected(true)
end

plugin.Unloading:Connect(function()
	if connection then
		connection.stop()
		connection = nil
	end
end)
