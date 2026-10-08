--!strict
local TweenService = game:GetService("TweenService")

export type Options = {
	Secondary: number,
	SpineSplit: number,
	Fps: number,
	RootScale: number,
}

export type Report = {
	Keyframes: number,
	Length: number,
	Poses: number,
}

type Key = {
	Time: number,
	Value: CFrame,
	Weight: number,
	Style: Enum.PoseEasingStyle,
	Direction: Enum.PoseEasingDirection,
}

type Segment = {
	Rest: number,
	Speed: number,
	Gain: number,
	Min: number,
	Max: number,
}

type Limb = {
	Pose: string,
	Joint: CFrame,
	Upper: string,
	Lower: string,
	Tip: string,
	Leg: boolean,
	Mid: Segment,
	End: Segment,
}

type Spring = { Angle: number, Velocity: number }

type Tracker = { Previous: CFrame?, Omega: number, Speed: number }

type Dynamics = { Mid: Spring, End: Spring, Upper: Tracker, Lower: Tracker }

type Frame = {
	Root: CFrame?,
	RootWeight: number,
	TorsoRot: CFrame,
	TorsoPos: Vector3,
	TorsoWeight: number,
	Head: CFrame?,
	HeadWeight: number,
	Limbs: { [number]: { Local: CFrame, Weight: number } },
}

local AnimationConverter = {}

AnimationConverter.Defaults = {
	Secondary = 1,
	SpineSplit = 0.5,
	Fps = 30,
	RootScale = 1,
}

local EasingFromPrevious = true
local SimRate = 120
local WarmupPasses = 3
local Frequency = 20
local Damping = 0.55

local Flip = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local RightSide = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LeftSide = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)

local ArmMid: Segment = { Rest = 0.12, Speed = 0.09, Gain = 1.4, Min = 0, Max = 2.4 }
local ArmEnd: Segment = { Rest = 0, Speed = 0, Gain = 0.5, Min = -0.6, Max = 0.6 }
local LegMid: Segment = { Rest = -0.05, Speed = -0.03, Gain = 1.4, Min = -2.5, Max = 0 }
local LegEnd: Segment = { Rest = 0, Speed = 0, Gain = 0.4, Min = -0.5, Max = 0.5 }

local Limbs: { Limb } = {
	{ Pose = "Right Arm", Joint = RightSide, Upper = "RightUpperArm", Lower = "RightLowerArm", Tip = "RightHand", Leg = false, Mid = ArmMid, End = ArmEnd },
	{ Pose = "Left Arm", Joint = LeftSide, Upper = "LeftUpperArm", Lower = "LeftLowerArm", Tip = "LeftHand", Leg = false, Mid = ArmMid, End = ArmEnd },
	{ Pose = "Right Leg", Joint = RightSide, Upper = "RightUpperLeg", Lower = "RightLowerLeg", Tip = "RightFoot", Leg = true, Mid = LegMid, End = LegEnd },
	{ Pose = "Left Leg", Joint = LeftSide, Upper = "LeftUpperLeg", Lower = "LeftLowerLeg", Tip = "LeftFoot", Leg = true, Mid = LegMid, End = LegEnd },
}

local StyleMap: { [string]: Enum.EasingStyle } = {
	Linear = Enum.EasingStyle.Linear,
	Cubic = Enum.EasingStyle.Cubic,
	CubicV2 = Enum.EasingStyle.Cubic,
	Elastic = Enum.EasingStyle.Elastic,
	Bounce = Enum.EasingStyle.Bounce,
}

local function RotationOnly(cframe: CFrame): CFrame
	return cframe - cframe.Position
end

local function Fraction(rotation: CFrame, amount: number): CFrame
	local axis, angle = rotation:ToAxisAngle()
	if math.abs(angle) < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis, angle * amount)
end

local function Ease(alpha: number, style: Enum.PoseEasingStyle, direction: Enum.PoseEasingDirection): number
	if style == Enum.PoseEasingStyle.Constant then
		return 0
	end
	local mapped = StyleMap[style.Name] or Enum.EasingStyle.Linear
	return TweenService:GetValue(alpha, mapped, (Enum.EasingDirection :: any)[direction.Name])
end

local function Sample(track: { Key }?, time: number): (CFrame?, number)
	if not track or #track == 0 then
		return nil, 0
	end
	local count = #track
	local first = track[1]
	local last = track[count]
	if time <= first.Time then
		return first.Value, first.Weight
	end
	if time >= last.Time then
		return last.Value, last.Weight
	end
	for index = 2, count do
		local after = track[index]
		if time <= after.Time then
			local before = track[index - 1]
			local span = after.Time - before.Time
			local alpha = if span > 0 then (time - before.Time) / span else 1
			local owner = if EasingFromPrevious then after else before
			local eased = Ease(alpha, owner.Style, owner.Direction)
			return before.Value:Lerp(after.Value, eased), before.Weight + (after.Weight - before.Weight) * alpha
		end
	end
	return last.Value, last.Weight
end

local function Collect(sequence: KeyframeSequence): ({ [string]: { Key } }, { Keyframe })
	local tracks: { [string]: { Key } } = {}
	local keyframes: { Keyframe } = {}
	for _, child in sequence:GetChildren() do
		if child:IsA("Keyframe") then
			table.insert(keyframes, child)
		end
	end
	table.sort(keyframes, function(a, b)
		return a.Time < b.Time
	end)
	for _, keyframe in keyframes do
		for _, descendant in keyframe:GetDescendants() do
			if descendant:IsA("Pose") then
				local list = tracks[descendant.Name]
				if not list then
					list = {}
					tracks[descendant.Name] = list
				end
				table.insert(list :: { Key }, {
					Time = keyframe.Time,
					Value = descendant.CFrame,
					Weight = descendant.Weight,
					Style = descendant.EasingStyle,
					Direction = descendant.EasingDirection,
				})
			end
		end
	end
	return tracks, keyframes
end

local function ReadFrame(tracks: { [string]: { Key } }, time: number, scale: number): Frame
	local torsoValue, torsoWeight = Sample(tracks.Torso, time)
	local torso = Flip * (torsoValue or CFrame.identity) * Flip:Inverse()
	local headValue, headWeight = Sample(tracks.Head, time)
	local rootValue, rootWeight = Sample(tracks.HumanoidRootPart, time)

	local frame: Frame = {
		Root = if rootValue then CFrame.new(rootValue.Position * scale) * RotationOnly(rootValue) else nil,
		RootWeight = rootWeight,
		TorsoRot = RotationOnly(torso),
		TorsoPos = torso.Position * scale,
		TorsoWeight = torsoWeight,
		Head = if headValue then RotationOnly(Flip * headValue * Flip:Inverse()) else nil,
		HeadWeight = headWeight,
		Limbs = {},
	}

	for index, limb in Limbs do
		local value, weight = Sample(tracks[limb.Pose], time)
		if value then
			frame.Limbs[index] = {
				Local = RotationOnly(limb.Joint * value * limb.Joint:Inverse()),
				Weight = weight,
			}
		end
	end
	return frame
end

local function NewTracker(): Tracker
	return { Previous = nil, Omega = 0, Speed = 0 }
end

local function Track(tracker: Tracker, world: CFrame, dt: number): (number, number)
	local previous = tracker.Previous
	tracker.Previous = world
	if not previous then
		return 0, 0
	end
	local axis, angle = (world * previous:Inverse()):ToAxisAngle()
	local omega = if math.abs(angle) > 1e-7 then axis * (angle / dt) else Vector3.zero
	local about = world:VectorToObjectSpace(omega).X
	local smoothed = tracker.Omega + (about - tracker.Omega) * (1 - math.exp(-dt / 0.03))
	local drive = (smoothed - tracker.Omega) / dt
	tracker.Omega = smoothed
	tracker.Speed += (omega.Magnitude - tracker.Speed) * (1 - math.exp(-dt / 0.12))
	return drive, tracker.Speed
end

local function Advance(state: Spring, segment: Segment, drive: number, speed: number, amount: number, dt: number)
	local target = math.clamp((segment.Rest + segment.Speed * speed) * amount, segment.Min, segment.Max)
	local acceleration = -Frequency * Frequency * (state.Angle - target)
		- 2 * Damping * Frequency * state.Velocity
		- segment.Gain * amount * drive
	state.Velocity += acceleration * dt
	state.Angle += state.Velocity * dt
	if state.Angle < segment.Min then
		state.Angle = segment.Min
		state.Velocity = math.max(state.Velocity, 0)
	elseif state.Angle > segment.Max then
		state.Angle = segment.Max
		state.Velocity = math.min(state.Velocity, 0)
	end
end

local function Simulate(tracks: { [string]: { Key } }, length: number, loop: boolean, options: Options)
	local dt = 1 / SimRate
	local steps = math.ceil(length * SimRate) + 1
	local passes = if loop then WarmupPasses else 1
	local prefill = if loop then 0 else math.floor(SimRate * 0.6)

	local dynamics: { Dynamics } = {}
	local recorded = {}
	for index in Limbs do
		dynamics[index] = {
			Mid = { Angle = 0, Velocity = 0 },
			End = { Angle = 0, Velocity = 0 },
			Upper = NewTracker(),
			Lower = NewTracker(),
		}
		recorded[index] = { Mid = table.create(steps, 0), End = table.create(steps, 0) }
	end

	local function Step(time: number, record: number?)
		local frame = ReadFrame(tracks, time, options.RootScale)
		for index, limb in Limbs do
			local data = frame.Limbs[index]
			if data then
				local state = dynamics[index]
				local upperWorld = frame.TorsoRot * data.Local
				local drive, speed = Track(state.Upper, upperWorld, dt)
				Advance(state.Mid, limb.Mid, drive, speed, options.Secondary, dt)
				local lowerWorld = upperWorld * CFrame.Angles(state.Mid.Angle, 0, 0)
				local tipDrive = Track(state.Lower, lowerWorld, dt)
				Advance(state.End, limb.End, tipDrive, 0, options.Secondary, dt)
				if record then
					recorded[index].Mid[record] = state.Mid.Angle
					recorded[index].End[record] = state.End.Angle
				end
			end
		end
	end

	for _ = 1, prefill do
		Step(0, nil)
	end
	for pass = 1, passes do
		for step = 1, steps do
			Step(math.min((step - 1) * dt, length), if pass == passes then step else nil)
		end
	end
	return recorded, steps
end

local function AddPose(parent: Instance, name: string, cframe: CFrame, weight: number): Pose
	local pose = Instance.new("Pose")
	pose.Name = name
	pose.CFrame = cframe
	pose.Weight = weight
	pose.EasingStyle = Enum.PoseEasingStyle.Linear
	pose.EasingDirection = Enum.PoseEasingDirection.In
	pose.Parent = parent
	return pose
end

local function Timeline(keyframes: { Keyframe }, length: number, fps: number): { { Time: number, Source: Keyframe? } }
	local entries: { { Time: number, Source: Keyframe? } } = {}
	for _, keyframe in keyframes do
		table.insert(entries, { Time = keyframe.Time, Source = keyframe })
	end
	local gap = 0.35 / fps
	for index = 0, math.floor(length * fps) do
		local time = index / fps
		local near = false
		for _, keyframe in keyframes do
			if math.abs(keyframe.Time - time) < gap then
				near = true
				break
			end
		end
		if not near then
			table.insert(entries, { Time = time, Source = nil })
		end
	end
	table.sort(entries, function(a, b)
		return a.Time < b.Time
	end)
	return entries
end

function AnimationConverter.Convert(source: KeyframeSequence, given: Options?): (KeyframeSequence, Report)
	local options: Options = table.clone(AnimationConverter.Defaults)
	if given then
		for key, value in given do
			(options :: any)[key] = value
		end
	end

	local tracks, keyframes = Collect(source)
	if tracks.UpperTorso or tracks.LowerTorso then
		error("already an R15 animation")
	end
	if not (tracks.Torso or tracks.Head or tracks["Left Arm"] or tracks["Right Arm"] or tracks["Left Leg"] or tracks["Right Leg"]) then
		error("no R6 poses found (expected Torso, Head, Left Arm, Right Arm, Left Leg, Right Leg)")
	end
	if #keyframes == 0 then
		error("no keyframes")
	end

	local length = keyframes[#keyframes].Time
	local split = math.clamp(options.SpineSplit, 0, 1)
	local entries = Timeline(keyframes, length, math.max(options.Fps, 1))
	local recorded, steps = Simulate(tracks, length, source.Loop, options)

	local result = Instance.new("KeyframeSequence")
	result.Name = source.Name .. "_R15"
	result.Loop = source.Loop
	result.Priority = source.Priority

	local poseCount = 0
	for _, entry in entries do
		local time = entry.Time
		local frame = ReadFrame(tracks, time, options.RootScale)
		local position = math.min(time * SimRate, steps - 1)
		local low = math.floor(position)
		local high = math.min(low + 1, steps - 1)
		local blend = position - low

		local keyframe = Instance.new("Keyframe")
		keyframe.Time = time
		if entry.Source then
			keyframe.Name = entry.Source.Name
			for _, child in entry.Source:GetChildren() do
				if child:IsA("KeyframeMarker") then
					local marker = Instance.new("KeyframeMarker")
					marker.Name = child.Name
					marker.Value = child.Value
					marker.Parent = keyframe
				end
			end
		end

		local spineTop = Fraction(frame.TorsoRot, split)
		local root = AddPose(keyframe, "HumanoidRootPart", frame.Root or CFrame.identity, frame.RootWeight)
		local lower = AddPose(root, "LowerTorso", CFrame.new(frame.TorsoPos) * Fraction(frame.TorsoRot, 1 - split), frame.TorsoWeight)
		local upper = AddPose(lower, "UpperTorso", spineTop, frame.TorsoWeight)
		poseCount += 3
		if frame.Head then
			AddPose(upper, "Head", frame.Head, frame.HeadWeight)
			poseCount += 1
		end

		for index, limb in Limbs do
			local data = frame.Limbs[index]
			if data then
				local read = recorded[index]
				local mid = read.Mid[low + 1] + (read.Mid[high + 1] - read.Mid[low + 1]) * blend
				local tip = read.End[low + 1] + (read.End[high + 1] - read.End[low + 1]) * blend
				local parent = if limb.Leg then lower else upper
				local rotation = if limb.Leg then spineTop * data.Local else data.Local
				local upperPose = AddPose(parent, limb.Upper, rotation, data.Weight)
				local lowerPose = AddPose(upperPose, limb.Lower, CFrame.Angles(mid, 0, 0), data.Weight)
				AddPose(lowerPose, limb.Tip, CFrame.Angles(tip, 0, 0), data.Weight)
				poseCount += 3
			end
		end

		keyframe.Parent = result
	end

	return result, { Keyframes = #entries, Length = length, Poses = poseCount }
end

return AnimationConverter
