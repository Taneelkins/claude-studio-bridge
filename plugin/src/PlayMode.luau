--!strict
-- Playtest control via StudioTestService.
--
-- The trick that makes this work across DataModels: ExecutePlayModeAsync /
-- ExecuteRunModeAsync are called from EDIT mode and YIELD for the whole play
-- session, returning whatever in-game code passes to StudioTestService:EndTest.
-- So run_in_play_mode injects a server Script that runs the test, captures logs,
-- and calls EndTest({...}); that payload comes back here to return to Claude.
--
-- Stopping a manually-started session is also cross-DataModel: edit mode flips a
-- plugin setting; the play-mode plugin instance (running monitorForStop) sees it
-- and calls EndTest.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioTestService = game:GetService("StudioTestService")

local PluginRef = require(script.Parent.PluginRef)

local PlayMode = {}

local TEST_SCRIPT_NAME = "ClaudeBridgeTestRunner"
local STOP_FLAG = "ClaudeBridge_StopPlaySignal"

-- Builds the in-game runner. `code` is concatenated as raw text between literal
-- chunks (not embedded inside a string literal), so it can contain any chars.
local function buildRunnerSource(code: string, timeout: number): string
	return [==[
local StudioTestService = game:GetService("StudioTestService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
if not RunService:IsRunning() then return end

local MAX_LOGS = 500
local logs = {}
local truncated = false
local LEVEL = {
	[Enum.MessageType.MessageOutput] = "output",
	[Enum.MessageType.MessageInfo] = "info",
	[Enum.MessageType.MessageWarning] = "warning",
	[Enum.MessageType.MessageError] = "error",
}
local conn = LogService.MessageOut:Connect(function(message, messageType)
	if #logs < MAX_LOGS then
		table.insert(logs, { level = LEVEL[messageType] or "output", message = message })
	else
		truncated = true
	end
end)

local startClock = os.clock()
local finished = false
local userOk = nil
local userResult = nil
local timedOut = false

local function finish()
	if finished then return end
	finished = true
	task.wait(0.05) -- let trailing logs flush
	if conn then conn:Disconnect() end
	local errors = {}
	for _, l in ipairs(logs) do
		if l.level == "error" then table.insert(errors, l.message) end
	end
	StudioTestService:EndTest({
		success = (userOk == true) and (#errors == 0),
		ranWithoutError = userOk == true,
		returned = if userOk then tostring(userResult) else nil,
		errorMessage = if userOk == false then tostring(userResult) else nil,
		logs = logs,
		logsTruncated = truncated,
		errors = errors,
		errorCount = #errors,
		durationSeconds = os.clock() - startClock,
		timedOut = timedOut,
	})
end

task.spawn(function()
	task.wait(]==] .. tostring(timeout) .. [==[)
	timedOut = true
	finish()
end)

-- the play window closed or disconnected: end the test, or Studio keeps waiting on it and refuses new ones
task.spawn(function()
	local Players = game:GetService("Players")
	local hadPlayer = false
	while not finished do
		local n = #Players:GetPlayers()
		if n > 0 then hadPlayer = true elseif hadPlayer then
			task.wait(2)
			if #Players:GetPlayers() == 0 and not finished then
				timedOut = true
				finish()
			end
		end
		task.wait(0.5)
	end
end)

task.spawn(function()
	userOk, userResult = pcall(function()
]==] .. code .. [==[
	end)
	finish()
end)
]==]
end

local function removeTestScript()
	local existing = ServerScriptService:FindFirstChild(TEST_SCRIPT_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Runs `code` in a fresh play session, returning the captured result as JSON.
function PlayMode.runScript(code: string, timeout: number, mode: string): string
	local source = buildRunnerSource(code, timeout)

	-- Validate the fully-assembled script up front. If it can't compile, the
	-- in-game runner would never call EndTest and the play call would hang.
	if loadstring then
		local okCompile, compileErr = loadstring(source)
		if not okCompile then
			error("Test code produced an invalid script: " .. tostring(compileErr))
		end
	end

	removeTestScript()
	local runner = Instance.new("Script")
	runner.Name = TEST_SCRIPT_NAME
	local sourceOk, sourceErr = pcall(function()
		(runner :: any).Source = source
	end)
	if not sourceOk then
		runner:Destroy()
		error("Could not write the test runner (grant script-modification permission?): " .. tostring(sourceErr))
	end
	runner.Parent = ServerScriptService

	local ok, result = pcall(function()
		if mode == "run_server" then
			return StudioTestService:ExecuteRunModeAsync({})
		else
			return StudioTestService:ExecutePlayModeAsync({})
		end
	end)

	removeTestScript()

	if not ok then
		if string.find(tostring(result), "previous one is still in progress", 1, true) then
			error("Studio still has an old test session open. Press Stop (the red square) if one is showing; if none is, a session died without ending and Studio needs a restart.")
		end
		error("Failed to run in play mode: " .. tostring(result))
	end

	return HttpService:JSONEncode({ mode = mode, result = result })
end

-- Starts a session without blocking. ExecutePlayModeAsync yields for the whole
-- session, so we spawn it and, if it's still yielding shortly after, treat that
-- as "started". An immediate return means starting failed.
function PlayMode.start(mode: string): string
	local immediate: any = nil
	task.spawn(function()
		local ok, res = pcall(function()
			if mode == "run_server" then
				return StudioTestService:ExecuteRunModeAsync({})
			else
				return StudioTestService:ExecutePlayModeAsync({})
			end
		end)
		immediate = { ok = ok, res = res }
	end)

	task.wait(0.3)

	if immediate then
		if string.find(tostring(immediate.res), "previous one is still in progress", 1, true) then
			return string.format("Could not start %s: Studio still has an old test session open. Press Stop if one is showing; if none is, a session died without ending and Studio needs a restart.", mode)
		end
		return string.format("Could not start %s (already in a session, or: %s)", mode, tostring(immediate.res))
	end
	return string.format("Started %s. Use play_control mode=stop to end it.", mode)
end

function PlayMode.signalStop()
	local plugin = PluginRef.plugin
	if plugin then
		plugin:SetSetting(STOP_FLAG, true)
	end
end

function PlayMode.stopAndWait(): string
	PlayMode.signalStop()
	task.wait(1.2)
	return "Sent stop signal to the play session."
end

-- Runs in the play-mode SERVER DataModel: watches for the edit-mode stop signal.
function PlayMode.monitorForStop()
	local plugin = PluginRef.plugin
	if not plugin then
		return
	end
	plugin:SetSetting(STOP_FLAG, false)
	local Players = game:GetService("Players")
	local hadPlayer, emptySince = false, nil
	while RunService:IsRunning() do
		if plugin:GetSetting(STOP_FLAG) then
			plugin:SetSetting(STOP_FLAG, false)
			pcall(function()
				StudioTestService:EndTest({ stoppedByClaude = true })
			end)
		end
		-- the play window closed / disconnected but this server lived on: end it, or Studio refuses every new test
		if #Players:GetPlayers() > 0 then
			hadPlayer, emptySince = true, nil
		elseif hadPlayer then
			emptySince = emptySince or os.clock()
			if os.clock() - emptySince > 3 then
				pcall(function()
					StudioTestService:EndTest({ endedBecause = "client left" })
				end)
				emptySince = os.clock() + 30
			end
		end
		task.wait(1)
	end
end

return PlayMode
