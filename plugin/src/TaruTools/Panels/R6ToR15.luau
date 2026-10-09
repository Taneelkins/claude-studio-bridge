--!nonstrict
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Theme = require(script.Parent.Parent.Theme)
local AnimationConverter = require(script.Parent.Parent.AnimationConverter)
local Pipeline = require(script.Parent.Parent.Pipeline)
local Dummy = require(script.Parent.Parent.Dummy)
local Stage = require(script.Parent.Parent.Stage)

local SettingKey = "TaruToolsR6ToR15"
local MaxLogLines = 60
local MaxFolderItems = 300

local BuiltIn = {
	{ "Locomotion", { Secondary = 1, RestBend = 1, TipFollow = 1, SpineSplit = 0.5, ArmsOn = 1, LegsOn = 1 } },
	{ "Combat", { Secondary = 0.6, RestBend = 0.5, TipFollow = 1.3, SpineSplit = 0.65, ArmsOn = 1, LegsOn = 1 } },
	{ "Idle", { Secondary = 0.6, RestBend = 1.6, TipFollow = 0.8, SpineSplit = 0.4, ArmsOn = 1, LegsOn = 1 } },
	{ "Rigid", { Secondary = 0, RestBend = 0, TipFollow = 0 } },
}

local R6ToR15 = {
	Name = "R6 → R15",
}

local function HasR15Poses(sequence)
	return sequence:FindFirstChild("UpperTorso", true) ~= nil or sequence:FindFirstChild("LowerTorso", true) ~= nil
end

function R6ToR15.Build(parent, plugin, widget, pinned)
	local settings = table.clone(AnimationConverter.Defaults)
	local flags = { PlayOnDummy = true, SendToDummy = true, Ghost = false }
	local presets = {}
	local camera = {}
	local saved = plugin:GetSetting(SettingKey)
	if type(saved) == "table" then
		for key in settings do
			if type(saved[key]) == "number" then
				settings[key] = saved[key]
			end
		end
		for key in flags do
			if type(saved[key]) == "boolean" then
				flags[key] = saved[key]
			end
		end
		if type(saved.Presets) == "table" then
			presets = saved.Presets
		end
		if type(saved.Camera) == "table" then
			camera = saved.Camera
		end
	end
	local function Save()
		local data = table.clone(settings)
		for key, value in flags do
			data[key] = value
		end
		data.Presets = presets
		data.Camera = camera
		plugin:SetSetting(SettingKey, data)
	end

	local order = 0
	local function Next()
		order += 1
		return order
	end
	local pinOrder = 0
	local function PinNext()
		pinOrder += 1
		return pinOrder
	end

	local title = Theme.Row(pinned, 30, PinNext())
	Theme.Label(title, "R6 → R15 Animation", {
		TextSize = 16,
		Color = Theme.Colors.Bright,
		Size = UDim2.new(1, 0, 1, 0),
	})
	local stage = Stage.new(pinned, PinNext, widget, camera, function(values)
		camera = values
		Save()
	end)
	Theme.Rule(pinned, PinNext())
	stage:BuildOptions(parent, Next)
	local ghostToggle = Theme.Toggle(parent, Next(), {
		Label = "Ghost: rigid conversion",
		Value = flags.Ghost,
		OnChange = function(on)
			flags.Ghost = on
			stage:SetGhost(on)
			Save()
		end,
	})
	Theme.Rule(parent, Next())

	Theme.Heading(parent, "Source", Next())
	local status = Theme.Row(parent, 0, Next())
	status.AutomaticSize = Enum.AutomaticSize.Y
	local statusLabel = Theme.Label(status, "", {
		Color = Theme.Colors.Muted,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
	})
	local warnRow = Theme.Row(parent, 0, Next())
	warnRow.AutomaticSize = Enum.AutomaticSize.Y
	local warnLabel = Theme.Label(warnRow, "", {
		Color = Theme.Colors.Warn,
		TextSize = 12,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
	})
	Theme.Row(parent, 6, Next())
	local convertButton = Theme.Button(parent, "Convert", Next(), function() end)

	local idRow = Theme.Row(parent, 36, Next())
	local idBox = Theme.Input(idRow, "Animation ID", 1, UDim2.new(1, -108, 0, 28), UDim2.fromOffset(0, 6))
	local loadButton = Theme.Button(idRow, "Load ID", 2, function() end, UDim2.fromOffset(100, 28))
	loadButton.Instance.Position = UDim2.new(1, -100, 0, 6)
	Theme.Rule(parent, Next())

	Theme.Heading(parent, "Test dummy", Next())
	local dummyStatus = Theme.Row(parent, 0, Next())
	dummyStatus.AutomaticSize = Enum.AutomaticSize.Y
	local dummyLabel = Theme.Label(dummyStatus, "", {
		Color = Theme.Colors.Muted,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
	})
	Theme.Row(parent, 6, Next())
	local dummyRow = Theme.Row(parent, 28, Next())
	local setDummy = Theme.Button(dummyRow, "Set from selection", 1, function() end, UDim2.new(0.5, -3, 1, 0))
	local clearDummy = Theme.Button(dummyRow, "Clear", 2, function() end, UDim2.new(0.5, -3, 1, 0))
	clearDummy.Instance.Position = UDim2.new(0.5, 3, 0, 0)
	Theme.Toggle(parent, Next(), {
		Label = "Play preview on dummy",
		Value = flags.PlayOnDummy,
		OnChange = function(on)
			flags.PlayOnDummy = on
			stage:SetPlayOnDummy(on)
			Save()
		end,
	})
	Theme.Toggle(parent, Next(), {
		Label = "Send converted files to dummy",
		Value = flags.SendToDummy,
		OnChange = function(on)
			flags.SendToDummy = on
			Save()
		end,
	})
	Theme.Rule(parent, Next())

	Theme.Heading(parent, "Presets", Next())
	local chipFrame = Instance.new("Frame")
	chipFrame.BackgroundTransparency = 1
	chipFrame.BorderSizePixel = 0
	chipFrame.AutomaticSize = Enum.AutomaticSize.Y
	chipFrame.Size = UDim2.new(1, 0, 0, 0)
	chipFrame.LayoutOrder = Next()
	chipFrame.Parent = parent
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Wraps = true
	chipLayout.Padding = UDim.new(0, 5)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipFrame
	local presetRow = Theme.Row(parent, 38, Next())
	local presetName = Theme.Input(presetRow, "Preset name", 1, UDim2.new(1, -168, 0, 28), UDim2.fromOffset(0, 8))
	local savePreset = Theme.Button(presetRow, "Save", 2, function() end, UDim2.fromOffset(78, 28))
	savePreset.Instance.Position = UDim2.new(1, -164, 0, 8)
	local deletePreset = Theme.Button(presetRow, "Delete", 3, function() end, UDim2.fromOffset(78, 28))
	deletePreset.Instance.Position = UDim2.new(1, -78, 0, 8)
	Theme.Rule(parent, Next())

	Theme.Heading(parent, "Settings", Next())
	local sliders = {}
	local toggles = {}
	local function Recompute() end
	local function AddSlider(key, label, min, max, step)
		sliders[key] = Theme.Slider(parent, Next(), {
			Label = label,
			Min = min,
			Max = max,
			Step = step,
			Value = settings[key],
			OnChange = function(value)
				settings[key] = value
				Save()
				Recompute()
			end,
		})
	end
	local function AddToggle(key, label)
		toggles[key] = Theme.Toggle(parent, Next(), {
			Label = label,
			Value = settings[key] > 0.5,
			OnChange = function(on)
				settings[key] = if on then 1 else 0
				Save()
				Recompute()
			end,
		})
	end
	AddSlider("Secondary", "Secondary motion", 0, 2, 0.05)
	AddSlider("RestBend", "Rest bend", 0, 3, 0.05)
	AddSlider("TipFollow", "Hands and feet follow", 0, 2, 0.05)
	AddSlider("SpineSplit", "Spine split", 0, 1, 0.05)
	AddSlider("RootScale", "Root scale", 0.5, 2, 0.05)
	AddSlider("Simplify", "Simplify keys", 0, 1, 0.05)
	AddToggle("ArmsOn", "Secondary motion on arms")
	AddToggle("LegsOn", "Secondary motion on legs")
	AddToggle("Mirror", "Mirror left and right")
	local fpsControl = Theme.Segmented(parent, Next(), {
		Label = "Frame rate",
		Options = { 30, 60 },
		Value = settings.Fps,
		OnChange = function(value)
			settings.Fps = value
			Save()
			Recompute()
		end,
	})
	Theme.Row(parent, 6, Next())
	local function ApplySettings(values)
		for key, control in sliders do
			if type(values[key]) == "number" then
				settings[key] = values[key]
				control.Set(values[key])
			end
		end
		for key, control in toggles do
			if type(values[key]) == "number" then
				settings[key] = values[key]
				control.Set(values[key] > 0.5)
			end
		end
		if type(values.Fps) == "number" then
			settings.Fps = values.Fps
			fpsControl.Set(values.Fps)
		end
		Save()
	end
	Theme.Button(parent, "Reset settings", Next(), function()
		ApplySettings(AnimationConverter.Defaults)
		Recompute()
	end)
	Theme.Rule(parent, Next())

	local function Snapshot()
		local values = {}
		for key in AnimationConverter.Defaults do
			values[key] = settings[key]
		end
		return values
	end
	local RebuildChips
	RebuildChips = function()
		for _, child in chipFrame:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local position = 0
		for _, entry in BuiltIn do
			position += 1
			Theme.Chip(chipFrame, entry[1], position, function()
				ApplySettings(entry[2])
				Recompute()
			end)
		end
		local names = {}
		for name in presets do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			position += 1
			Theme.Chip(chipFrame, name, position, function()
				presetName.Text = name
				ApplySettings(presets[name])
				Recompute()
			end).TextColor3 = Theme.Colors.Bright
		end
	end
	savePreset.Instance.MouseButton1Click:Connect(function()
		local name = presetName.Text:match("^%s*(.-)%s*$")
		if name ~= "" then
			presets[name] = Snapshot()
			Save()
			RebuildChips()
		end
	end)
	deletePreset.Instance.MouseButton1Click:Connect(function()
		local name = presetName.Text:match("^%s*(.-)%s*$")
		if presets[name] then
			presets[name] = nil
			presetName.Text = ""
			Save()
			RebuildChips()
		end
	end)
	RebuildChips()

	Theme.Heading(parent, "Log", Next())
	local logFrame = Instance.new("Frame")
	logFrame.BackgroundTransparency = 1
	logFrame.BorderSizePixel = 0
	logFrame.AutomaticSize = Enum.AutomaticSize.Y
	logFrame.Size = UDim2.new(1, 0, 0, 0)
	logFrame.LayoutOrder = Next()
	logFrame.Parent = parent
	local logLayout = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Padding = UDim.new(0, 2)
	logLayout.Parent = logFrame

	local lines = 0
	local function Log(text, color)
		lines += 1
		Theme.Label(logFrame, text, {
			Font = Theme.Mono,
			TextSize = 11,
			Color = color or Theme.Colors.Text,
			Wrap = true,
			AutoHeight = true,
			VerticalAlign = Enum.TextYAlignment.Top,
			Order = lines,
		})
		local labels = {}
		for _, child in logFrame:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(labels, child)
			end
		end
		if #labels > MaxLogLines then
			table.sort(labels, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			labels[1]:Destroy()
		end
	end
	local function ClearLog()
		lines = 0
		for _, child in logFrame:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	local hint = Theme.Row(parent, 0, Next())
	hint.AutomaticSize = Enum.AutomaticSize.Y
	Theme.Label(hint, "Pick an animation or a folder of them, tune the settings against the preview, then Convert. Selecting a converted file reloads its settings so you can keep tuning it and apply the change in place. Space plays and pauses.", {
		Color = Theme.Colors.Muted,
		TextSize = 12,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
	})
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingTop = UDim.new(0, 10)
	hintPad.Parent = hint

	local fetched = {}
	local function Fetch(assetId)
		if not fetched[assetId] then
			fetched[assetId] = KeyframeSequenceProvider:GetKeyframeSequenceAsync(assetId)
		end
		return fetched[assetId]
	end

	local function SourceOf(item)
		if item.Kind == "edit" then
			local source = Pipeline.FindSource(item.Target)
			if not source then
				error("stored source copy is missing")
			end
			return source
		end
		return item.Sequence or Fetch(item.AssetId)
	end

	local loaded = nil
	local skipped = 0
	local function Gather()
		local items = {}
		skipped = 0
		local vault = ServerStorage:FindFirstChild("TaruTools")
		local function Add(instance, fromFolder)
			if instance:IsA("KeyframeSequence") then
				if vault and instance:IsDescendantOf(vault) then
					return
				end
				if Pipeline.IsConverted(instance) then
					table.insert(items, { Kind = "edit", Target = instance, Name = instance.Name })
				elseif fromFolder and (HasR15Poses(instance) or instance.Name:match("_R15$")) then
					skipped += 1
				else
					table.insert(items, { Kind = "new", Sequence = instance, Name = instance.Name, Parent = instance.Parent })
				end
			elseif instance:IsA("Animation") and instance.AnimationId ~= "" and not fromFolder then
				table.insert(items, { Kind = "new", AssetId = instance.AnimationId, Name = instance.Name, Parent = instance.Parent })
			end
		end
		for _, instance in Selection:Get() do
			if instance:IsA("KeyframeSequence") or instance:IsA("Animation") then
				Add(instance, false)
			else
				for _, descendant in instance:GetDescendants() do
					if descendant:IsA("KeyframeSequence") then
						Add(descendant, true)
						if #items >= MaxFolderItems then
							break
						end
					end
				end
			end
		end
		if #items == 0 and loaded then
			items[1] = loaded
		end
		return items
	end

	local currentSource = nil
	local function SetStatus(text, color)
		statusLabel.Text = text
		statusLabel.TextColor3 = color or Theme.Colors.Text
	end

	local scheduled = false
	Recompute = function()
		if scheduled then
			return
		end
		scheduled = true
		task.delay(0.06, function()
			scheduled = false
			if not currentSource then
				stage:SetSource(nil, nil, nil)
				warnLabel.Text = ""
				return
			end
			local ok, result, report = pcall(AnimationConverter.Convert, currentSource, settings)
			if ok then
				local ghost = nil
				if flags.Ghost then
					local rigid = table.clone(settings)
					rigid.Secondary = 0
					local good, converted = pcall(AnimationConverter.Convert, currentSource, rigid)
					ghost = if good then converted else nil
				end
				stage:SetSource(currentSource, result, ghost)
				warnLabel.Text = table.concat(report.Warnings, "\n")
				result:Destroy()
				if ghost then
					ghost:Destroy()
				end
			else
				stage:SetSource(currentSource, nil, nil)
				warnLabel.Text = ""
				SetStatus(tostring(result):gsub("^.-:%d+: ", ""), Theme.Colors.Bad)
			end
		end)
	end

	local token = 0
	local function Describe()
		token += 1
		local mine = token
		local items = Gather()
		local edits, news = 0, 0
		for _, item in items do
			if item.Kind == "edit" then
				edits += 1
			else
				news += 1
			end
		end
		local suffix = if #items > 1 then string.format(" (%d)", #items) else ""
		convertButton.SetText((if edits > 0 and news == 0 then "Apply to file" elseif edits > 0 then "Convert and apply" else "Convert") .. suffix)
		convertButton.SetEnabled(#items > 0)

		local item = items[1]
		if not item then
			currentSource = nil
			SetStatus("Select a KeyframeSequence, Animation or folder in the Explorer, or load an ID.", Theme.Colors.Muted)
			Recompute()
			return
		end
		SetStatus("Loading " .. item.Name, Theme.Colors.Muted)
		task.spawn(function()
			local ok, source = pcall(SourceOf, item)
			if mine ~= token then
				return
			end
			if not ok then
				currentSource = nil
				SetStatus(item.Name .. ": " .. tostring(source), Theme.Colors.Bad)
				Recompute()
				return
			end
			currentSource = source
			if item.Kind == "edit" then
				local stored = Pipeline.ReadSettings(item.Target)
				if stored then
					ApplySettings(stored)
				end
			end
			local _, keyframes = AnimationConverter.Collect(source)
			local length = keyframes[#keyframes] and keyframes[#keyframes].Time or 0
			local prefix = if item.Kind == "edit" then "Editing " else "Previewing "
			local extra = if #items > 1 then string.format("  +%d more", #items - 1) else ""
			if skipped > 0 then
				extra ..= string.format("  (%d R15 skipped)", skipped)
			end
			SetStatus(string.format("%s%s  %.2fs  %d keys%s", prefix, item.Name, length, #keyframes, extra))
			Recompute()
		end)
	end

	local running = false
	local function Convert()
		if running then
			return
		end
		local items = Gather()
		if #items == 0 then
			return
		end
		running = true
		convertButton.SetEnabled(false)
		ClearLog()

		task.spawn(function()
			local dummy = Dummy.Find()
			local recording = ChangeHistoryService:TryBeginRecording("Taru Tools: R6 to R15")
			local outputs = {}
			local failed = 0
			for position, item in items do
				convertButton.SetText(string.format("Converting %d/%d", position, #items))
				local ok, target, report = pcall(function()
					if item.Kind == "edit" then
						return Pipeline.Reapply(item.Target, settings)
					end
					local home = if dummy and flags.SendToDummy then Dummy.Folder(dummy) else (item.Parent or ServerStorage)
					return Pipeline.Create(SourceOf(item), item.Name, home, settings, item.AssetId)
				end)
				if ok then
					table.insert(outputs, target)
					Log(string.format("%s  %.2fs  %d of %d keys", target.Name, report.Length, report.Keyframes, report.Dense), Theme.Colors.Good)
					for _, warning in report.Warnings do
						Log("  " .. warning, Theme.Colors.Warn)
					end
				else
					failed += 1
					Log(item.Name .. ": " .. tostring(target), Theme.Colors.Bad)
				end
				if position % 4 == 0 then
					task.wait()
				end
			end
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
			end
			if #items > 1 then
				Log(string.format("Done: %d converted, %d failed", #outputs, failed), if failed > 0 then Theme.Colors.Warn else Theme.Colors.Good)
			end
			running = false
			if #outputs > 0 then
				Selection:Set(outputs)
			end
			Describe()
		end)
	end
	convertButton.Instance.MouseButton1Click:Connect(Convert)

	loadButton.Instance.MouseButton1Click:Connect(function()
		local id = idBox.Text:match("%d+")
		if not id then
			ClearLog()
			Log("Enter a numeric animation ID.", Theme.Colors.Bad)
			return
		end
		SetStatus("Loading " .. id, Theme.Colors.Muted)
		task.spawn(function()
			local ok, sequence = pcall(Fetch, "rbxassetid://" .. id)
			if not ok then
				ClearLog()
				Log(id .. ": " .. tostring(sequence), Theme.Colors.Bad)
				Describe()
				return
			end
			loaded = { Kind = "new", Sequence = sequence, AssetId = "rbxassetid://" .. id, Name = "Animation_" .. id }
			Selection:Set({})
			Describe()
		end)
	end)

	local function DescribeDummy()
		local dummy = Dummy.Find()
		if dummy then
			dummyLabel.Text = "Dummy: " .. dummy:GetFullName():gsub("^Workspace%.", "")
			dummyLabel.TextColor3 = Theme.Colors.Text
		else
			dummyLabel.Text = "No dummy set. Select an R15 rig and set it to preview on it and collect converted files there."
			dummyLabel.TextColor3 = Theme.Colors.Muted
		end
		return dummy
	end

	local function ApplyDummy()
		local dummy = DescribeDummy()
		stage:SetDummy(dummy)
		stage:SetPlayOnDummy(flags.PlayOnDummy and dummy ~= nil)
	end

	setDummy.Instance.MouseButton1Click:Connect(function()
		for _, instance in Selection:Get() do
			local model, problem = Dummy.Set(instance)
			if model then
				ApplyDummy()
				return
			elseif problem then
				ClearLog()
				Log(problem, Theme.Colors.Bad)
			end
		end
		if #Selection:Get() == 0 then
			ClearLog()
			Log("Select an R15 rig first.", Theme.Colors.Bad)
		end
	end)
	clearDummy.Instance.MouseButton1Click:Connect(function()
		Dummy.Clear()
		ApplyDummy()
	end)

	local connections = {
		Selection.SelectionChanged:Connect(Describe),
		CollectionService:GetInstanceRemovedSignal(Dummy.Tag):Connect(function(instance)
			if not instance:GetAttribute("TaruPreviewClone") then
				ApplyDummy()
			end
		end),
	}
	plugin.Unloading:Connect(function()
		stage:Destroy()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	parent.Destroying:Connect(function()
		stage:Destroy()
	end)

	ghostToggle.Set(flags.Ghost)
	stage:SetGhost(flags.Ghost)
	ApplyDummy()
	Describe()
end

return R6ToR15
