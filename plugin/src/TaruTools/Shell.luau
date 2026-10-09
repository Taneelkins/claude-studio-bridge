--!nonstrict
local Theme = require(script.Parent.Theme)
local Registry = require(script.Parent.Registry)

local Shell = {}

local function List(frame)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return layout
end

function Shell.Mount(plugin, widget)
	Theme.Host = widget

	local background = Instance.new("Frame")
	background.BackgroundColor3 = Theme.Colors.Background
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = widget

	local pinned = Instance.new("Frame")
	pinned.BackgroundTransparency = 1
	pinned.BorderSizePixel = 0
	pinned.AutomaticSize = Enum.AutomaticSize.Y
	pinned.Size = UDim2.new(1, 0, 0, 0)
	pinned.ZIndex = 2
	pinned.Parent = background
	local pinnedPadding = Instance.new("UIPadding")
	pinnedPadding.PaddingLeft = UDim.new(0, 16)
	pinnedPadding.PaddingRight = UDim.new(0, 16)
	pinnedPadding.PaddingTop = UDim.new(0, 14)
	List(pinned)

	local root = Instance.new("ScrollingFrame")
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ScrollBarThickness = 4
	root.ScrollBarImageColor3 = Theme.Colors.Rule
	root.Parent = background
	pinnedPadding.Parent = pinned

	local function Layout()
		local height = pinned.AbsoluteSize.Y
		root.Position = UDim2.fromOffset(0, height)
		root.Size = UDim2.new(1, 0, 1, -height)
	end
	pinned:GetPropertyChangedSignal("AbsoluteSize"):Connect(Layout)
	Layout()

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.Parent = root
	List(root)

	local header = Theme.Row(pinned, 22, 1)
	Theme.Label(header, "TARU TOOLS", {
		Font = Theme.Mono,
		TextSize = 12,
		Color = Theme.Colors.Bright,
		Size = UDim2.new(1, 0, 1, 0),
	})
	Theme.Rule(pinned, 2)

	local pinnedFrames = {}
	local bodyFrames = {}
	local tabButtons = {}
	local function Show(index)
		for position in bodyFrames do
			bodyFrames[position].Visible = position == index
			pinnedFrames[position].Visible = position == index
		end
		for position, button in tabButtons do
			button.TextColor3 = if position == index then Theme.Colors.Bright else Theme.Colors.Muted
		end
	end

	if #Registry > 1 then
		local tabs = Theme.Row(pinned, 26, 3)
		local tabLayout = Instance.new("UIListLayout")
		tabLayout.FillDirection = Enum.FillDirection.Horizontal
		tabLayout.Padding = UDim.new(0, 14)
		tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabLayout.Parent = tabs
		for index, tool in Registry do
			local button = Instance.new("TextButton")
			button.BackgroundTransparency = 1
			button.AutoButtonColor = false
			button.Font = Theme.Sans
			button.TextSize = 13
			button.Text = tool.Name
			button.Size = UDim2.new(0, 0, 1, 0)
			button.AutomaticSize = Enum.AutomaticSize.X
			button.LayoutOrder = index
			button.Parent = tabs
			tabButtons[index] = button
			button.MouseButton1Click:Connect(function()
				Show(index)
			end)
		end
	end

	for index, tool in Registry do
		local pin = Instance.new("Frame")
		pin.BackgroundTransparency = 1
		pin.BorderSizePixel = 0
		pin.AutomaticSize = Enum.AutomaticSize.Y
		pin.Size = UDim2.new(1, 0, 0, 0)
		pin.LayoutOrder = 10 + index
		pin.Parent = pinned
		List(pin)
		pinnedFrames[index] = pin

		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.LayoutOrder = index
		frame.Parent = root
		List(frame)
		bodyFrames[index] = frame

		tool.Build(frame, plugin, widget, pin)
	end
	Show(1)
end

return Shell
