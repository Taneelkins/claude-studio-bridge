local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

local Shell = require(script.Shell)

local toolbar = plugin:CreateToolbar("Taru Tools")
local button = toolbar:CreateButton("Taru Tools", "Open Taru Tools", "rbxasset://textures/ui/GuiImagePlaceholder.png")
button.ClickableWhenViewportHidden = true

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 340, 580, 300, 360)
local widget = plugin:CreateDockWidgetPluginGui("TaruTools", info)
widget.Title = "Taru Tools"
widget.Name = "TaruTools"

Shell.Mount(plugin, widget)

button:SetActive(widget.Enabled)
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)
