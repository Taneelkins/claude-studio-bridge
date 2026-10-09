--!nonstrict
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Rig = require(script.Parent.Rig)
local Dummy = require(script.Parent.Dummy)
local AnimationConverter = require(script.Parent.AnimationConverter)

local Stage = {}
Stage.__index = Stage

local Target = Vector3.new(0, 2.8, 0)
local Views = {
	{ "Front", math.pi, 0.12 },
	{ "Back", 0, 0.12 },
	{ "Left", -math.pi / 2, 0.12 },
	{ "Right", math.pi / 2, 0.12 },
	{ "Top", math.pi, 1.4 },
}

local function Aim(camera, yaw, pitch, distance)
	local offset = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)) * distance
	camera.CFrame = CFrame.lookAt(Target + offset, Target)
end

function Stage.new(parent, Next, widget, saved, onChange)
	local self = setmetatable({}, Stage)
	saved = saved or {}
	self.Yaw = saved.Yaw or (math.pi - 0.55)
	self.Pitch = saved.Pitch or 0.12
	self.Distance = saved.Distance or 13
	self.Time = 0
	self.Length = 0
	self.Playing = true
	self.Speed = saved.Speed or 1
	self.Turntable = saved.Turntable or false
	self.OnChange = onChange
	self.GhostOn = false
	self.GhostTracks = nil
	self.GhostRig = nil
	self.Dirty = true
	self.PlayOnDummy = false
	self.Dummy = nil
	self.DummyRig = nil
	self.Widget = widget
	self.Panes = {}

	local holder = Theme.Row(parent, 190, Next())
	local function MakePane(key, caption, position)
		local pane = Instance.new("Frame")
		pane.BackgroundColor3 = Theme.Colors.Surface
		pane.BorderSizePixel = 0
		pane.Position = position
		pane.Size = UDim2.new(0.5, -3, 1, 0)
		pane.ClipsDescendants = true
		pane.Parent = holder
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Rule
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = pane

		local viewport = Instance.new("ViewportFrame")
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.Ambient = Color3.fromRGB(150, 150, 158)
		viewport.LightColor = Color3.fromRGB(255, 252, 245)
		viewport.LightDirection = Vector3.new(-0.5, -1, -0.7)
		viewport.Parent = pane

		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		local label = Theme.Label(pane, caption, {
			Font = Theme.Mono,
			TextSize = 10,
			Color = Theme.Colors.Muted,
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.new(1, -16, 0, 12),
		})
		label.ZIndex = 3
		local note = Theme.Label(pane, "Loading rig", {
			TextSize = 12,
			Color = Theme.Colors.Muted,
			Align = Enum.TextXAlignment.Center,
			Wrap = true,
			Size = UDim2.new(1, -24, 1, 0),
			Position = UDim2.fromOffset(12, 0),
		})
		note.ZIndex = 3

		viewport.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.Turntable = false
				if self.TurntableToggle then
					self.TurntableToggle.Set(false)
				end
				Theme.Drag(function(moved)
					self.Yaw -= moved.Delta.X * 0.012
					self.Pitch = math.clamp(self.Pitch + moved.Delta.Y * 0.01, -1.2, 1.45)
					self.Dirty = true
				end, function()
					self:Persist()
				end, viewport)
			end
		end)
		viewport.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				self.Distance = math.clamp(self.Distance * (1 - input.Position.Z * 0.1), 5, 40)
				self.Dirty = true
				self:Persist()
			end
		end)

		local entry = { Key = key, Pane = pane, Viewport = viewport, Camera = camera, Label = label, Note = note, Caption = caption, Tracks = nil, Rig = nil }
		self.Panes[key] = entry
		return entry
	end
	MakePane("Source", "R6 · source", UDim2.new())
	MakePane("Result", "R15 · result", UDim2.new(0.5, 3, 0, 0))

	local controls = Theme.Row(parent, 30, Next())
	self.PlayButton = Theme.Button(controls, "Pause", 1, function()
		self.Playing = not self.Playing
		self.PlayButton.SetText(if self.Playing then "Pause" else "Play")
	end, UDim2.fromOffset(60, 26))
	self.PlayButton.Instance.Position = UDim2.fromOffset(0, 2)
	local viewsWidth = 46
	for index, view in Views do
		local button = Theme.Button(controls, view[1], index + 1, function()
			self.Yaw, self.Pitch = view[2], view[3]
			self:Persist()
			self.Turntable = false
			if self.TurntableToggle then
				self.TurntableToggle.Set(false)
			end
			self.Dirty = true
		end, UDim2.fromOffset(viewsWidth, 26))
		button.Instance.TextSize = 12
		button.Instance.Position = UDim2.new(1, -(#Views - index + 1) * (viewsWidth + 4) + 4, 0, 2)
	end

	local readoutRow = Theme.Row(parent, 16, Next())
	self.Readout = Theme.Label(readoutRow, "", {
		Font = Theme.Mono,
		TextSize = 10,
		Color = Theme.Colors.Muted,
		Size = UDim2.new(1, 0, 1, 0),
	})

	self.Scrub = Theme.Slider(parent, Next(), {
		Label = "Time",
		Min = 0,
		Max = 1,
		Step = 0.01,
		Value = 0,
		OnChange = function(value)
			self.Time = value
			self.Playing = false
			self.PlayButton.SetText("Play")
			self.Dirty = true
		end,
	})
	self:LoadRig("Source", function()
		return Rig.Generate(Enum.HumanoidRigType.R6)
	end)
	self:LoadRig("Result", function()
		return Rig.Generate(Enum.HumanoidRigType.R15)
	end)

	local loop = 0
	local running = false
	local function Sync()
		if widget.Enabled and not running then
			running = true
			loop += 1
			local mine = loop
			task.spawn(function()
				local last = os.clock()
				while running and loop == mine do
					task.wait()
					local now = os.clock()
					local ok, problem = pcall(self.Step, self, now - last)
					last = now
					if not ok and problem ~= self.LastProblem then
						self.LastProblem = problem
						self.Readout.Text = "Preview error: " .. tostring(problem)
						self.Readout.TextColor3 = Theme.Colors.Bad
						warn("[Taru Tools] preview: " .. tostring(problem))
					end
				end
			end)
		elseif not widget.Enabled and running then
			running = false
			self:RestoreDummy()
		end
	end
	widget:GetPropertyChangedSignal("Enabled"):Connect(Sync)
	Sync()
	local keys = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Space and widget.Enabled and widget:HasFocus() then
			self.Playing = not self.Playing
			self.PlayButton.SetText(if self.Playing then "Pause" else "Play")
			self.Dirty = true
		end
	end)
	self.Disconnect = function()
		running = false
		keys:Disconnect()
	end

	return self
end

function Stage:BuildOptions(parent, Next)
	Theme.Heading(parent, "Preview", Next())
	Theme.Segmented(parent, Next(), {
		Label = "Speed",
		Options = { 0.25, 0.5, 1 },
		Value = self.Speed,
		OnChange = function(value)
			self.Speed = value
			self:Persist()
		end,
	})
	self.TurntableToggle = Theme.Toggle(parent, Next(), {
		Label = "Turntable",
		Value = self.Turntable,
		OnChange = function(on)
			self.Turntable = on
			self:Persist()
		end,
	})

end

function Stage:LoadRig(key, build)
	local entry = self.Panes[key]
	entry.Generation = (entry.Generation or 0) + 1
	local generation = entry.Generation
	if entry.Rig then
		entry.Rig.Model:Destroy()
		entry.Rig = nil
	end
	entry.Note.Text = "Loading rig"
	task.spawn(function()
		local ok, model = pcall(build)
		if generation ~= entry.Generation then
			if ok and model then
				model:Destroy()
			end
			return
		end
		if not ok or not model then
			entry.Note.Text = "Preview unavailable"
			warn("[Taru Tools] rig failed: " .. tostring(model))
			return
		end
		local rig = Rig.Stage(model)
		model.Parent = entry.Viewport
		entry.Rig = rig
		entry.Note.Text = if key == "Source" and not entry.Tracks then "Select an R6 animation" else ""
		self.Dirty = true
	end)
end

function Stage:Persist()
	if not self.OnChange or self.PersistPending then
		return
	end
	self.PersistPending = true
	task.delay(0.6, function()
		self.PersistPending = false
		self.OnChange({ Yaw = self.Yaw, Pitch = self.Pitch, Distance = self.Distance, Speed = self.Speed, Turntable = self.Turntable })
	end)
end

function Stage:MakeBody()
	local model = self.Dummy
	if model then
		local copy = model:Clone()
		if copy then
			copy:SetAttribute("TaruPreviewClone", true)
			CollectionService:RemoveTag(copy, Dummy.Tag)
			return copy
		end
	end
	return Rig.Generate(Enum.HumanoidRigType.R15)
end

function Stage:RebuildGhost()
	if self.GhostRig then
		self.GhostRig.Model:Destroy()
		self.GhostRig = nil
	end
	if not self.GhostOn then
		return
	end
	local ok, model = pcall(function()
		return self:MakeBody()
	end)
	if not ok or not model then
		return
	end
	local rig = Rig.Stage(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 0.62
			descendant.Color = Color3.fromRGB(120, 172, 255)
		end
	end
	model.Parent = self.Panes.Result.Viewport
	self.GhostRig = rig
	self.Dirty = true
end

function Stage:SetGhost(on)
	self.GhostOn = on
	self:RebuildGhost()
end

function Stage:RestoreDummy()
	if self.DummyRig and self.DummyPosed then
		self.DummyPosed = false
		Rig.Reset(self.DummyRig)
	end
end

function Stage:SetDummy(model)
	self:RestoreDummy()
	self.DummyRig = nil
	self.Dummy = model
	local result = self.Panes.Result
	if model then
		result.Label.Text = "R15 · " .. model.Name
		local ok, built = pcall(Rig.Build, model)
		if ok then
			self.DummyRig = built
		end
		self:LoadRig("Result", function()
			return self:MakeBody()
		end)
	else
		result.Label.Text = result.Caption
		self:LoadRig("Result", function()
			return self:MakeBody()
		end)
	end
	self:RebuildGhost()
end

function Stage:SetPlayOnDummy(on)
	self.PlayOnDummy = on
	if not on then
		self:RestoreDummy()
	end
	self.Dirty = true
end

function Stage:SetSource(source, result, ghost)
	local length = 0
	if source then
		local tracks, keyframes = AnimationConverter.Collect(source)
		self.Panes.Source.Tracks = tracks
		length = keyframes[#keyframes] and keyframes[#keyframes].Time or 0
	else
		self.Panes.Source.Tracks = nil
	end
	if result then
		self.Panes.Result.Tracks = (AnimationConverter.Collect(result))
	else
		self.Panes.Result.Tracks = nil
	end
	self.GhostTracks = if ghost then (AnimationConverter.Collect(ghost)) else nil
	self.Length = length
	if length > 0 then
		self.Time = self.Time % length
	else
		self.Time = 0
	end
	self.Scrub.SetRange(0, math.max(length, 0.01))
	self.Panes.Source.Note.Text = if source then "" else "Select an R6 animation"
	if self.Panes.Source.Rig == nil and source then
		self.Panes.Source.Note.Text = "Loading rig"
	end
	self.Dirty = true
end

function Stage:Step(dt)
	if self.Turntable then
		self.Yaw += dt * 0.6
		self.Dirty = true
	end
	if self.Playing and self.Length > 0 then
		self.Time = (self.Time + dt * self.Speed) % self.Length
		self.Dirty = true
	end
	if not self.Dirty then
		return
	end
	self.Dirty = false

	for _, entry in self.Panes do
		if entry.Rig then
			Rig.Apply(entry.Rig, entry.Tracks, self.Time)
			Rig.Solve(entry.Rig)
		end
		Aim(entry.Camera, self.Yaw, self.Pitch, self.Distance)
	end
	if self.GhostRig then
		Rig.Apply(self.GhostRig, self.GhostTracks, self.Time)
		Rig.Solve(self.GhostRig)
	end
	if self.PlayOnDummy and self.DummyRig then
		Rig.Apply(self.DummyRig, self.Panes.Result.Tracks, self.Time)
		Rig.Solve(self.DummyRig)
		self.DummyPosed = true
	end
	self.Scrub.Set(self.Time)
	local text = string.format("%.2f / %.2fs  %s", self.Time, self.Length, if self.Length <= 0 then "single pose" elseif self.Playing then "playing" else "paused")
	if text ~= self.ReadoutText then
		self.ReadoutText = text
		self.Readout.Text = text
		self.Readout.TextColor3 = Theme.Colors.Muted
	end
end

function Stage:Destroy()
	self.Disconnect()
	self:RestoreDummy()
end

return Stage
