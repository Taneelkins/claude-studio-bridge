--!nonstrict
local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(24, 24, 26),
	Surface = Color3.fromRGB(33, 33, 36),
	Pressed = Color3.fromRGB(46, 46, 51),
	Rule = Color3.fromRGB(56, 56, 61),
	Text = Color3.fromRGB(214, 214, 219),
	Muted = Color3.fromRGB(128, 128, 138),
	Bright = Color3.fromRGB(242, 242, 245),
	Good = Color3.fromRGB(132, 190, 148),
	Bad = Color3.fromRGB(208, 102, 92),
	Warn = Color3.fromRGB(212, 168, 92),
}

Theme.Sans = Enum.Font.BuilderSans
Theme.Mono = Enum.Font.RobotoMono

function Theme.Row(parent, height, order)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, height)
	row.LayoutOrder = order
	row.Parent = parent
	return row
end

function Theme.Label(parent, text, props)
	props = props or {}
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.Font = props.Font or Theme.Sans
	label.TextSize = props.TextSize or 13
	label.TextColor3 = props.Color or Theme.Colors.Text
	label.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	label.TextYAlignment = props.VerticalAlign or Enum.TextYAlignment.Center
	label.TextWrapped = props.Wrap or false
	label.Size = props.Size or UDim2.new(1, 0, 0, 16)
	label.Position = props.Position or UDim2.new()
	label.LayoutOrder = props.Order or 0
	if props.AutoHeight then
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.new(1, 0, 0, 0)
	end
	label.Parent = parent
	return label
end

function Theme.Heading(parent, text, order)
	local row = Theme.Row(parent, 22, order)
	Theme.Label(row, string.upper(text), {
		Font = Theme.Mono,
		TextSize = 11,
		Color = Theme.Colors.Muted,
		Size = UDim2.new(1, 0, 1, 0),
		VerticalAlign = Enum.TextYAlignment.Bottom,
	})
	return row
end

function Theme.Rule(parent, order)
	local row = Theme.Row(parent, 9, order)
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Colors.Rule
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromScale(0, 0.5)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Parent = row
	return row
end

local function Stroke(instance, color)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Rule
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

function Theme.Button(parent, text, order, onClick, width)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Colors.Surface
	button.BorderSizePixel = 0
	button.Font = Theme.Sans
	button.TextSize = 13
	button.Text = text
	button.TextColor3 = Theme.Colors.Bright
	button.Size = width or UDim2.new(1, 0, 0, 28)
	button.LayoutOrder = order
	button.Parent = parent
	local stroke = Stroke(button)

	local enabled = true
	button.MouseEnter:Connect(function()
		if enabled then
			stroke.Color = Theme.Colors.Muted
		end
	end)
	button.MouseLeave:Connect(function()
		stroke.Color = Theme.Colors.Rule
		button.BackgroundColor3 = Theme.Colors.Surface
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			button.BackgroundColor3 = Theme.Colors.Pressed
		end
	end)
	button.MouseButton1Up:Connect(function()
		button.BackgroundColor3 = Theme.Colors.Surface
	end)
	button.MouseButton1Click:Connect(function()
		if enabled then
			onClick()
		end
	end)

	local handle = {}
	handle.Instance = button
	function handle.SetEnabled(on)
		enabled = on
		button.TextColor3 = if on then Theme.Colors.Bright else Theme.Colors.Muted
	end
	function handle.SetText(value)
		button.Text = value
	end
	return handle
end

function Theme.Chip(parent, text, order, onClick)
	local chip = Instance.new("TextButton")
	chip.AutoButtonColor = false
	chip.BackgroundColor3 = Theme.Colors.Surface
	chip.BorderSizePixel = 0
	chip.Font = Theme.Sans
	chip.TextSize = 12
	chip.Text = text
	chip.TextColor3 = Theme.Colors.Text
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, 24)
	chip.LayoutOrder = order
	chip.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = chip
	local stroke = Stroke(chip)
	chip.MouseEnter:Connect(function()
		stroke.Color = Theme.Colors.Muted
	end)
	chip.MouseLeave:Connect(function()
		stroke.Color = Theme.Colors.Rule
	end)
	chip.MouseButton1Click:Connect(onClick)
	return chip
end

function Theme.Input(parent, placeholder, order, width, position)
	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Theme.Colors.Surface
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Theme.Mono
	box.TextSize = 12
	box.Text = ""
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Theme.Colors.Muted
	box.TextColor3 = Theme.Colors.Bright
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = width or UDim2.new(1, 0, 0, 28)
	box.Position = position or UDim2.new()
	box.LayoutOrder = order
	box.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = box
	local stroke = Stroke(box)
	box.Focused:Connect(function()
		stroke.Color = Theme.Colors.Muted
	end)
	box.FocusLost:Connect(function()
		stroke.Color = Theme.Colors.Rule
	end)
	return box
end

function Theme.Drag(onMove, onEnd, source)
	local host = Theme.Host
	local overlay = Instance.new("TextButton")
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 1000
	overlay.Parent = host

	local finished = false
	local focusLost
	local function Finish()
		if finished then
			return
		end
		finished = true
		if focusLost then
			focusLost:Disconnect()
		end
		overlay:Destroy()
		if onEnd then
			onEnd()
		end
	end

	overlay.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			onMove(input)
		end
	end)
	overlay.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Finish()
		end
	end)
	overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Finish()
		end
	end)
	overlay.MouseButton1Up:Connect(Finish)
	overlay.MouseLeave:Connect(Finish)
	focusLost = host.WindowFocusReleased:Connect(Finish)
	if source then
		source.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				Finish()
			end
		end)
	end
end

function Theme.Slider(parent, order, config)
	local row = Theme.Row(parent, 38, order)
	Theme.Label(row, config.Label, { Size = UDim2.new(1, -74, 0, 16) })

	local value = Instance.new("TextBox")
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.ClearTextOnFocus = true
	value.Font = Theme.Mono
	value.TextSize = 12
	value.TextColor3 = Theme.Colors.Bright
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Size = UDim2.fromOffset(70, 16)
	value.Position = UDim2.new(1, -70, 0, 0)
	value.Parent = row

	local hit = Instance.new("Frame")
	hit.BackgroundTransparency = 1
	hit.BorderSizePixel = 0
	hit.Position = UDim2.fromOffset(0, 16)
	hit.Size = UDim2.new(1, 0, 0, 22)
	hit.Parent = row

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.Colors.Rule
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, 2)
	track.Parent = hit

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.Colors.Muted
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track

	local thumb = Instance.new("Frame")
	thumb.BackgroundColor3 = Theme.Colors.Bright
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Size = UDim2.fromOffset(6, 14)
	thumb.Parent = track

	local min, max = config.Min, config.Max
	local current = config.Value
	local function Render()
		local alpha = if max > min then (current - min) / (max - min) else 0
		fill.Size = UDim2.fromScale(alpha, 1)
		thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
		value.Text = string.format("%." .. (config.Decimals or 2) .. "f", current)
	end

	local function Commit(raw, silent)
		local step = config.Step or 0.01
		current = math.clamp(math.round(raw / step) * step, min, max)
		Render()
		if not silent then
			config.OnChange(current)
		end
	end

	local function Apply(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		Commit(min + alpha * (max - min), false)
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Apply(input.Position.X)
			if config.OnDragStart then
				config.OnDragStart()
			end
			Theme.Drag(function(moved)
				Apply(moved.Position.X)
			end, config.OnDragEnd, hit)
		end
	end)

	value.FocusLost:Connect(function()
		local typed = tonumber(value.Text)
		if typed then
			Commit(typed, false)
		else
			Render()
		end
	end)

	Render()

	local handle = {}
	function handle.Set(newValue)
		Commit(newValue, true)
	end
	function handle.SetRange(newMin, newMax)
		min, max = newMin, newMax
		Commit(current, true)
	end
	return handle
end

function Theme.Segmented(parent, order, config)
	local row = Theme.Row(parent, 30, order)
	Theme.Label(row, config.Label, { Size = UDim2.new(1, -140, 1, 0) })

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, 0, 0.5, 0)
	holder.Size = UDim2.fromOffset(#config.Options * 46, 24)
	holder.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	local buttons = {}
	local selected = config.Value
	local function Render()
		for option, button in buttons do
			local on = option == selected
			button.BackgroundColor3 = if on then Theme.Colors.Pressed else Theme.Colors.Surface
			button.TextColor3 = if on then Theme.Colors.Bright else Theme.Colors.Muted
		end
	end

	for index, option in config.Options do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Font = Theme.Mono
		button.TextSize = 12
		button.Text = tostring(option)
		button.Size = UDim2.fromOffset(46, 24)
		button.LayoutOrder = index
		button.Parent = holder
		Stroke(button)
		buttons[option] = button
		button.MouseButton1Click:Connect(function()
			selected = option
			Render()
			config.OnChange(option)
		end)
	end
	Render()

	return {
		Set = function(option)
			selected = option
			Render()
		end,
	}
end

function Theme.Toggle(parent, order, config)
	local row = Theme.Row(parent, 28, order)
	Theme.Label(row, config.Label, { Size = UDim2.new(1, -30, 1, 0) })

	local box = Instance.new("Frame")
	box.BackgroundColor3 = Theme.Colors.Surface
	box.BorderSizePixel = 0
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, 0, 0.5, 0)
	box.Size = UDim2.fromOffset(16, 16)
	box.Parent = row
	Stroke(box)

	local mark = Instance.new("Frame")
	mark.BackgroundColor3 = Theme.Colors.Bright
	mark.BorderSizePixel = 0
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromOffset(8, 8)
	mark.Parent = box

	local click = Instance.new("TextButton")
	click.Text = ""
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.Parent = row

	local on = config.Value
	local function Render()
		mark.Visible = on
	end
	click.MouseButton1Click:Connect(function()
		on = not on
		Render()
		config.OnChange(on)
	end)
	Render()

	return {
		Set = function(value)
			on = value
			Render()
		end,
	}
end

return Theme
