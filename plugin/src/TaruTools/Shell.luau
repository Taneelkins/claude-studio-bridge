--!nonstrict
local Theme = require(script.Parent.Theme)
local Registry = require(script.Parent.Registry)

local Shell = {}

function Shell.Mount(plugin, widget)
	local root = Instance.new("ScrollingFrame")
	root.BackgroundColor3 = Theme.Colors.Background
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ScrollBarThickness = 4
	root.ScrollBarImageColor3 = Theme.Colors.Rule
	root.Parent = widget

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local header = Theme.Row(root, 22, 1)
	Theme.Label(header, "TARU TOOLS", {
		Font = Theme.Mono,
		TextSize = 12,
		Color = Theme.Colors.Bright,
		Size = UDim2.new(1, 0, 1, 0),
	})
	Theme.Rule(root, 2)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.new(1, 0, 0, 0)
	body.LayoutOrder = 4
	body.Parent = root

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	local frames = {}
	local tabButtons = {}
	local function Show(index)
		for position, frame in frames do
			frame.Visible = position == index
		end
		for position, button in tabButtons do
			button.TextColor3 = if position == index then Theme.Colors.Bright else Theme.Colors.Muted
		end
	end

	if #Registry > 1 then
		local tabs = Theme.Row(root, 26, 3)
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
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.LayoutOrder = index
		frame.Parent = body

		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = frame

		frames[index] = frame
		tool.Build(frame, plugin, widget)
	end
	Show(1)
end

return Shell
