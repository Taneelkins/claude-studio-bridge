--!nonstrict
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ServerStorage = game:GetService("ServerStorage")

local Theme = require(script.Parent.Parent.Theme)
local AnimationConverter = require(script.Parent.Parent.AnimationConverter)

local SettingKey = "TaruToolsR6ToR15"
local MaxLogLines = 40

local R6ToR15 = {
	Name = "R6 → R15",
}

function R6ToR15.Build(parent, plugin)
	local settings = table.clone(AnimationConverter.Defaults)
	local saved = plugin:GetSetting(SettingKey)
	if type(saved) == "table" then
		for key in settings do
			if type(saved[key]) == "number" then
				settings[key] = saved[key]
			end
		end
	end
	local function Save()
		plugin:SetSetting(SettingKey, settings)
	end

	local order = 0
	local function Next()
		order += 1
		return order
	end

	local title = Theme.Row(parent, 30, Next())
	Theme.Label(title, "R6 → R15 Animation", {
		TextSize = 16,
		Color = Theme.Colors.Bright,
		Size = UDim2.new(1, 0, 1, 0),
	})
	local summary = Theme.Row(parent, 0, Next())
	summary.AutomaticSize = Enum.AutomaticSize.Y
	Theme.Label(summary, "Reads the keyframes of an R6 animation and writes a smooth R15 version, filling the extra joints with natural motion.", {
		Color = Theme.Colors.Muted,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
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
	local spacer = Theme.Row(parent, 6, Next())
	local convertSelected = Theme.Button(parent, "Convert selected", Next(), function() end)

	local idRow = Theme.Row(parent, 36, Next())
	local idBox = Theme.Input(idRow, "Animation ID", 1, UDim2.new(1, -108, 0, 28), UDim2.fromOffset(0, 6))
	local convertId = Theme.Button(idRow, "Convert ID", 2, function() end, UDim2.fromOffset(100, 28))
	convertId.Instance.Position = UDim2.new(1, -100, 0, 6)
	Theme.Rule(parent, Next())

	Theme.Heading(parent, "Settings", Next())
	Theme.Slider(parent, Next(), {
		Label = "Secondary motion",
		Min = 0,
		Max = 2,
		Step = 0.05,
		Value = settings.Secondary,
		OnChange = function(value)
			settings.Secondary = value
			Save()
		end,
	})
	Theme.Slider(parent, Next(), {
		Label = "Spine split",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Value = settings.SpineSplit,
		OnChange = function(value)
			settings.SpineSplit = value
			Save()
		end,
	})
	Theme.Slider(parent, Next(), {
		Label = "Root scale",
		Min = 0.5,
		Max = 2,
		Step = 0.05,
		Value = settings.RootScale,
		OnChange = function(value)
			settings.RootScale = value
			Save()
		end,
	})
	Theme.Segmented(parent, Next(), {
		Label = "Frame rate",
		Options = { 30, 60 },
		Value = settings.Fps,
		OnChange = function(value)
			settings.Fps = value
			Save()
		end,
	})
	Theme.Rule(parent, Next())

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
		local children = logFrame:GetChildren()
		if #children > MaxLogLines + 1 then
			for _, child in children do
				if child:IsA("TextLabel") then
					child:Destroy()
					break
				end
			end
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
	Theme.Label(hint, "Results land next to the source. Open one in the Animation Editor to preview it on an R15 rig, then publish.", {
		Color = Theme.Colors.Muted,
		TextSize = 12,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
	})
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingTop = UDim.new(0, 10)
	hintPad.Parent = hint

	local function SelectedItems()
		local items = {}
		for _, instance in Selection:Get() do
			if instance:IsA("KeyframeSequence") then
				table.insert(items, { Name = instance.Name, Sequence = instance, Parent = instance.Parent })
			elseif instance:IsA("Animation") and instance.AnimationId ~= "" then
				table.insert(items, { Name = instance.Name, AssetId = instance.AnimationId, Parent = instance.Parent })
			end
		end
		return items
	end

	local function Describe()
		local count = #SelectedItems()
		if count == 0 then
			statusLabel.Text = "Select KeyframeSequence or Animation instances in the Explorer."
			statusLabel.TextColor3 = Theme.Colors.Muted
		else
			statusLabel.Text = count .. (if count == 1 then " animation selected." else " animations selected.")
			statusLabel.TextColor3 = Theme.Colors.Text
		end
	end

	local running = false
	local function Convert(items)
		if running then
			return
		end
		if #items == 0 then
			ClearLog()
			Log("Nothing to convert.", Theme.Colors.Bad)
			return
		end
		running = true
		convertSelected.SetEnabled(false)
		convertId.SetEnabled(false)
		ClearLog()

		task.spawn(function()
			local recording = ChangeHistoryService:TryBeginRecording("Taru Tools: R6 to R15")
			local outputs = {}
			for _, item in items do
				local ok, converted, report = pcall(function()
					local sequence = item.Sequence
					if not sequence then
						sequence = KeyframeSequenceProvider:GetKeyframeSequenceAsync(item.AssetId)
						sequence.Name = item.Name
					end
					local result, info = AnimationConverter.Convert(sequence, settings)
					result.Parent = item.Parent or ServerStorage
					return result, info
				end)
				if ok then
					table.insert(outputs, converted)
					Log(string.format("%s → %s  %.2fs  %d keys", item.Name, converted.Name, report.Length, report.Keyframes), Theme.Colors.Good)
				else
					Log(item.Name .. ": " .. tostring(converted), Theme.Colors.Bad)
				end
			end
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
			end
			if #outputs > 0 then
				Selection:Set(outputs)
			end
			running = false
			convertSelected.SetEnabled(true)
			convertId.SetEnabled(true)
		end)
	end

	convertSelected.Instance.MouseButton1Click:Connect(function()
		if not running then
			Convert(SelectedItems())
		end
	end)
	convertId.Instance.MouseButton1Click:Connect(function()
		if running then
			return
		end
		local id = idBox.Text:match("%d+")
		if not id then
			ClearLog()
			Log("Enter a numeric animation ID.", Theme.Colors.Bad)
			return
		end
		Convert({ { Name = "Animation_" .. id, AssetId = "rbxassetid://" .. id } })
	end)

	local connection = Selection.SelectionChanged:Connect(Describe)
	parent.Destroying:Connect(function()
		connection:Disconnect()
	end)
	Describe()
end

return R6ToR15
