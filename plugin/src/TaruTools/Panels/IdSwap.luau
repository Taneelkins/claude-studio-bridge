--!nonstrict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerStorage = game:GetService("ServerStorage")

local Theme = require(script.Parent.Parent.Theme)

local SettingKey = "TaruToolsIdSwap"
local MaxLogLines = 80

local IdSwap = {
	Name = "ID swap",
}

local function Digits(text)
	return text:match("%d+")
end

function IdSwap.Build(parent, plugin, widget, pinned)
	local pairsList = {}
	local saved = plugin:GetSetting(SettingKey)
	if type(saved) == "table" then
		for _, entry in saved do
			if type(entry) == "table" then
				table.insert(pairsList, { Old = tostring(entry.Old or ""), New = tostring(entry.New or ""), Label = tostring(entry.Label or "") })
			end
		end
	end
	local function Save()
		plugin:SetSetting(SettingKey, pairsList)
	end

	local order = 0
	local function Next()
		order += 1
		return order
	end

	local title = Theme.Row(pinned, 30, 1)
	Theme.Label(title, "Animation ID swap", {
		TextSize = 16,
		Color = Theme.Colors.Bright,
		Size = UDim2.new(1, 0, 1, 0),
	})
	Theme.Rule(pinned, 2)

	local about = Theme.Row(parent, 0, Next())
	about.AutomaticSize = Enum.AutomaticSize.Y
	Theme.Label(about, "After you publish the R15 versions, pair each old animation ID with its new one. Find matches lists every Animation, StringValue and script that uses an old ID, and Apply swaps them in one undoable step.", {
		Color = Theme.Colors.Muted,
		TextSize = 12,
		Wrap = true,
		AutoHeight = true,
		VerticalAlign = Enum.TextYAlignment.Top,
	})
	Theme.Row(parent, 8, Next())

	Theme.Heading(parent, "Pairs", Next())
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.Size = UDim2.new(1, 0, 0, 0)
	list.LayoutOrder = Next()
	list.Parent = parent
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	local armed = false
	local applyButton
	local function Disarm()
		armed = false
		if applyButton then
			applyButton.SetEnabled(false)
		end
	end

	local Render
	Render = function()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for index, entry in pairsList do
			local row = Theme.Row(list, 52, index)
			Theme.Label(row, if entry.Label ~= "" then entry.Label else "Pair " .. index, {
				Font = Theme.Mono,
				TextSize = 10,
				Color = Theme.Colors.Muted,
				Size = UDim2.new(1, -30, 0, 14),
			})
			local old = Theme.Input(row, "Old ID", 1, UDim2.new(0.5, -22, 0, 28), UDim2.fromOffset(0, 20))
			old.Text = entry.Old
			local new = Theme.Input(row, "New ID", 2, UDim2.new(0.5, -22, 0, 28), UDim2.new(0.5, -10, 0, 20))
			new.Text = entry.New
			local remove = Theme.Button(row, "×", 3, function()
				table.remove(pairsList, index)
				Save()
				Disarm()
				Render()
			end, UDim2.fromOffset(28, 28))
			remove.Instance.Position = UDim2.new(1, -28, 0, 20)
			old.FocusLost:Connect(function()
				entry.Old = Digits(old.Text) or ""
				old.Text = entry.Old
				Save()
				Disarm()
			end)
			new.FocusLost:Connect(function()
				entry.New = Digits(new.Text) or ""
				new.Text = entry.New
				Save()
				Disarm()
			end)
		end
	end

	local buttons = Theme.Row(parent, 28, Next())
	local scan = Theme.Button(buttons, "Scan converted", 1, function() end, UDim2.new(0.5, -3, 1, 0))
	local add = Theme.Button(buttons, "Add pair", 2, function() end, UDim2.new(0.5, -3, 1, 0))
	add.Instance.Position = UDim2.new(0.5, 3, 0, 0)
	Theme.Rule(parent, Next())

	local actions = Theme.Row(parent, 28, Next())
	local find = Theme.Button(actions, "Find matches", 1, function() end, UDim2.new(0.5, -3, 1, 0))
	applyButton = Theme.Button(actions, "Apply swap", 2, function() end, UDim2.new(0.5, -3, 1, 0))
	applyButton.Instance.Position = UDim2.new(0.5, 3, 0, 0)
	applyButton.SetEnabled(false)
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

	local function Map()
		local map = {}
		for _, entry in pairsList do
			if entry.Old ~= "" and entry.New ~= "" and entry.Old ~= entry.New then
				map[entry.Old] = entry.New
			end
		end
		return map
	end

	local function Swap(text, map)
		local count = 0
		local result = text:gsub("%f[%d](%d+)%f[%D]", function(number)
			local replacement = map[number]
			if replacement then
				count += 1
				return replacement
			end
			return nil
		end)
		return result, count
	end

	local function Walk(map, apply)
		local vault = ServerStorage:FindFirstChild("TaruTools")
		local total, touched = 0, 0
		local checked = 0
		for _, instance in game:GetDescendants() do
			checked += 1
			if checked % 800 == 0 then
				task.wait()
			end
			if not (vault and instance:IsDescendantOf(vault)) then
				local property = if instance:IsA("Animation") then "AnimationId"
					elseif instance:IsA("StringValue") then "Value"
					elseif instance:IsA("LuaSourceContainer") then "Source"
					else nil
				if property then
					local ok, text = pcall(function()
						return instance[property]
					end)
					if ok and type(text) == "string" and text ~= "" then
						local replaced, count = Swap(text, map)
						if count > 0 then
							total += count
							touched += 1
							if apply then
								local wrote, problem = pcall(function()
									instance[property] = replaced
								end)
								if not wrote then
									Log(instance:GetFullName() .. ": " .. tostring(problem), Theme.Colors.Bad)
								end
							end
							Log(string.format("%s  %s  x%d", instance.ClassName, instance:GetFullName(), count))
						end
					end
				end
			end
		end
		return total, touched
	end

	local busy = false
	local function Run(apply)
		if busy then
			return
		end
		local map = Map()
		ClearLog()
		if next(map) == nil then
			Log("Add at least one pair with an old and a new ID.", Theme.Colors.Bad)
			return
		end
		busy = true
		task.spawn(function()
			local recording = if apply then ChangeHistoryService:TryBeginRecording("Taru Tools: ID swap") else nil
			local total, touched = Walk(map, apply)
			if recording then
				ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
			end
			if total == 0 then
				Log("No matches.", Theme.Colors.Warn)
			else
				Log(string.format("%s %d references in %d objects.", if apply then "Swapped" else "Found", total, touched), Theme.Colors.Good)
			end
			armed = not apply and total > 0
			applyButton.SetEnabled(armed)
			busy = false
		end)
	end
	find.Instance.MouseButton1Click:Connect(function()
		Run(false)
	end)
	applyButton.Instance.MouseButton1Click:Connect(function()
		if armed then
			Run(true)
		end
	end)

	add.Instance.MouseButton1Click:Connect(function()
		table.insert(pairsList, { Old = "", New = "", Label = "" })
		Save()
		Disarm()
		Render()
	end)
	scan.Instance.MouseButton1Click:Connect(function()
		ClearLog()
		local known = {}
		for _, entry in pairsList do
			known[entry.Label .. "|" .. entry.Old] = true
		end
		local added = 0
		for _, instance in game:GetDescendants() do
			if instance:IsA("KeyframeSequence") and instance:GetAttribute("TaruSource") then
				local name = tostring(instance:GetAttribute("TaruName") or instance.Name)
				local old = Digits(tostring(instance:GetAttribute("TaruAssetId") or "")) or ""
				if not known[name .. "|" .. old] then
					known[name .. "|" .. old] = true
					table.insert(pairsList, { Old = old, New = "", Label = name })
					added += 1
				end
			end
		end
		Save()
		Disarm()
		Render()
		Log(if added > 0 then added .. " converted animations added. Fill in the new IDs." else "No new converted animations found.", if added > 0 then Theme.Colors.Good else Theme.Colors.Muted)
	end)

	Render()
end

return IdSwap
