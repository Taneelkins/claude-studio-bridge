--!strict
local TweenService = game:GetService("TweenService")

export type Options = {
	Secondary: number,
	SpineSplit: number,
	Fps: number,
	RootScale: number,
	RestBend: number,
	TipFollow: number,
	Simplify: number,
	ArmsOn: number,
	LegsOn: number,
	Mirror: number,
}

export type Report = {
	Keyframes: number,
	Dense: number,
	Length: number,
	Poses: number,
	Warnings: { string },
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
	RestBend = 1,
	TipFollow = 1,
	Simplify = 0.3,
	ArmsOn = 1,
	LegsOn = 1,
	Mirror = 0,
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

local function Reflect(cframe: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

local function ReadFrame(tracks: { [string]: { Key } }, time: number, scale: number, mirror: boolean): Frame
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

	if mirror then
		frame.TorsoRot = Reflect(frame.TorsoRot)
		frame.TorsoPos = Vector3.new(-frame.TorsoPos.X, frame.TorsoPos.Y, frame.TorsoPos.Z)
		if frame.Head then
			frame.Head = Reflect(frame.Head)
		end
		local swapped = {}
		for index, data in frame.Limbs do
			local partner = if index % 2 == 1 then index + 1 else index - 1
			swapped[partner] = { Local = Reflect(data.Local), Weight = data.Weight }
		end
		frame.Limbs = swapped
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

local function Advance(state: Spring, segment: Segment, drive: number, speed: number, amount: number, dt: number, restScale: number, gainScale: number)
	local target = math.clamp((segment.Rest * restScale + segment.Speed * speed) * amount, segment.Min, segment.Max)
	local acceleration = -Frequency * Frequency * (state.Angle - target)
		- 2 * Damping * Frequency * state.Velocity
		- segment.Gain * gainScale * amount * drive
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
		local frame = ReadFrame(tracks, time, options.RootScale, options.Mirror > 0.5)
		for index, limb in Limbs do
			local data = frame.Limbs[index]
			if data then
				local state = dynamics[index]
				local amount = options.Secondary * (if limb.Leg then options.LegsOn else options.ArmsOn)
				local upperWorld = frame.TorsoRot * data.Local
				local drive, speed = Track(state.Upper, upperWorld, dt)
				Advance(state.Mid, limb.Mid, drive, speed, amount, dt, options.RestBend, 1)
				local lowerWorld = upperWorld * CFrame.Angles(state.Mid.Angle, 0, 0)
				local tipDrive = Track(state.Lower, lowerWorld, dt)
				Advance(state.End, limb.End, tipDrive, 0, amount, dt, 1, options.TipFollow)
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

type PoseData = { CFrame: CFrame, Weight: number }

type Entry = {
	Time: number,
	Source: Keyframe?,
	Forced: boolean,
	Poses: { [string]: PoseData },
}

local function Timeline(keyframes: { Keyframe }, length: number, fps: number): { Entry }
	local entries: { Entry } = {}
	for _, keyframe in keyframes do
		local forced = keyframe.Name ~= "Keyframe"
		for _, child in keyframe:GetChildren() do
			if child:IsA("KeyframeMarker") then
				forced = true
			end
		end
		table.insert(entries, { Time = keyframe.Time, Source = keyframe, Forced = forced, Poses = {} })
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
			table.insert(entries, { Time = time, Source = nil, Forced = false, Poses = {} })
		end
	end
	table.sort(entries, function(a, b)
		return a.Time < b.Time
	end)
	entries[1].Forced = true
	entries[#entries].Forced = true
	return entries
end

local function Angle(a: CFrame, b: CFrame): number
	local _, angle = (a:Inverse() * b):ToAxisAngle()
	return math.abs(angle)
end

local function PoseError(entries: { Entry }, low: number, high: number, middle: number): number
	local first, last, mid = entries[low], entries[high], entries[middle]
	local alpha = (mid.Time - first.Time) / math.max(last.Time - first.Time, 1e-6)
	local worst = 0
	for name, data in mid.Poses do
		local a, b = first.Poses[name], last.Poses[name]
		if a and b then
			local guess = a.CFrame:Lerp(b.CFrame, alpha)
			local deviation = Angle(guess, data.CFrame) + 0.25 * (guess.Position - data.CFrame.Position).Magnitude
			worst = math.max(worst, deviation)
		end
	end
	return worst
end

local function Reduce(entries: { Entry }, tolerance: number): { Entry }
	if tolerance <= 0 then
		return entries
	end
	local keep: { [number]: boolean } = {}
	local forced: { number } = {}
	for index, entry in entries do
		if entry.Forced then
			keep[index] = true
			table.insert(forced, index)
		end
	end
	local stack: { { number } } = {}
	for position = 1, #forced - 1 do
		table.insert(stack, { forced[position], forced[position + 1] })
	end
	while #stack > 0 do
		local range = table.remove(stack) :: { number }
		local low, high = range[1], range[2]
		local worst, worstIndex = 0, 0
		for middle = low + 1, high - 1 do
			local deviation = PoseError(entries, low, high, middle)
			if deviation > worst then
				worst, worstIndex = deviation, middle
			end
		end
		if worst > tolerance and worstIndex > 0 then
			keep[worstIndex] = true
			table.insert(stack, { low, worstIndex })
			table.insert(stack, { worstIndex, high })
		end
	end
	local kept: { Entry } = {}
	for index, entry in entries do
		if keep[index] then
			table.insert(kept, entry)
		end
	end
	return kept
end

local function Inspect(entries: { Entry }, loop: boolean): { string }
	local warnings: { string } = {}
	local snaps = 0
	for index = 2, #entries do
		local previous, current = entries[index - 1], entries[index]
		local dt = math.max(current.Time - previous.Time, 1e-3)
		for name, data in current.Poses do
			local before = previous.Poses[name]
			if before and data.Weight > 0.5 and Angle(before.CFrame, data.CFrame) / dt > 35 then
				snaps += 1
				if snaps <= 3 then
					table.insert(warnings, string.format("Fast snap in %s at %.2fs", name, current.Time))
				end
			end
		end
	end
	if snaps > 3 then
		table.insert(warnings, string.format("%d more fast snaps", snaps - 3))
	end

	if loop and #entries > 1 then
		local first, last = entries[1], entries[#entries]
		local worst, worstName = 0, ""
		for name, data in first.Poses do
			local other = last.Poses[name]
			if other and data.Weight > 0.5 then
				local gap = Angle(data.CFrame, other.CFrame)
				if gap > worst then
					worst, worstName = gap, name
				end
			end
		end
		if worst > 0.12 then
			table.insert(warnings, string.format("Loop does not close: %s differs %d° between first and last frame", worstName, math.round(math.deg(worst))))
		end
	end

	local travel = 0
	local origin = entries[1].Poses.LowerTorso
	for _, entry in entries do
		local data = entry.Poses.LowerTorso
		if data and origin then
			travel = math.max(travel, (data.CFrame.Position - origin.CFrame.Position).Magnitude)
		end
	end
	if travel > 3 then
		table.insert(warnings, string.format("Torso travels %.1f studs, check Root scale", travel))
	end
	return warnings
end

AnimationConverter.Collect = Collect
AnimationConverter.Sample = Sample

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
	local mirror = options.Mirror > 0.5
	local entries = Timeline(keyframes, length, math.max(options.Fps, 1))
	local recorded, steps = Simulate(tracks, length, source.Loop, options)
	local warnings: { string } = {}

	for _, entry in entries do
		local time = entry.Time
		local frame = ReadFrame(tracks, time, options.RootScale, mirror)
		local position = math.min(time * SimRate, steps - 1)
		local low = math.floor(position)
		local high = math.min(low + 1, steps - 1)
		local blend = position - low

		local poses = entry.Poses
		local spineTop = Fraction(frame.TorsoRot, split)
		poses.HumanoidRootPart = { CFrame = frame.Root or CFrame.identity, Weight = frame.RootWeight }
		poses.LowerTorso = { CFrame = CFrame.new(frame.TorsoPos) * Fraction(frame.TorsoRot, 1 - split), Weight = frame.TorsoWeight }
		poses.UpperTorso = { CFrame = spineTop, Weight = frame.TorsoWeight }
		if frame.Head then
			poses.Head = { CFrame = frame.Head, Weight = frame.HeadWeight }
		end
		for index, limb in Limbs do
			local data = frame.Limbs[index]
			if data then
				local read = recorded[index]
				local mid = read.Mid[low + 1] + (read.Mid[high + 1] - read.Mid[low + 1]) * blend
				local tip = read.End[low + 1] + (read.End[high + 1] - read.End[low + 1]) * blend
				poses[limb.Upper] = { CFrame = if limb.Leg then spineTop * data.Local else data.Local, Weight = data.Weight }
				poses[limb.Lower] = { CFrame = CFrame.Angles(mid, 0, 0), Weight = data.Weight }
				poses[limb.Tip] = { CFrame = CFrame.Angles(tip, 0, 0), Weight = data.Weight }
			end
		end
	end

	for _, issue in Inspect(entries, source.Loop) do
		table.insert(warnings, issue)
	end
	for index, limb in Limbs do
		local read = recorded[index]
		local bound = if limb.Mid.Max > 0 then limb.Mid.Max else limb.Mid.Min
		local hits = 0
		for step = 1, steps do
			if math.abs(read.Mid[step]) >= math.abs(bound) * 0.97 then
				hits += 1
			end
		end
		if hits > steps * 0.1 then
			table.insert(warnings, string.format("%s is at full bend %d%% of the time, lower Secondary motion", limb.Lower, math.round(hits / steps * 100)))
		end
	end

	local dense = #entries
	local kept = Reduce(entries, options.Simplify * 0.05)

	local result = Instance.new("KeyframeSequence")
	result.Name = source.Name .. "_R15"
	result.Loop = source.Loop
	result.Priority = source.Priority

	local order = { "HumanoidRootPart", "LowerTorso", "UpperTorso" }
	local parentOf: { [string]: string } = { LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso" }
	for _, limb in Limbs do
		parentOf[limb.Upper] = if limb.Leg then "LowerTorso" else "UpperTorso"
		parentOf[limb.Lower] = limb.Upper
		parentOf[limb.Tip] = limb.Lower
	end
	table.insert(order, "Head")
	for _, limb in Limbs do
		table.insert(order, limb.Upper)
		table.insert(order, limb.Lower)
		table.insert(order, limb.Tip)
	end

	local poseCount = 0
	for _, entry in kept do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = entry.Time
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
		local made: { [string]: Pose } = {}
		for _, name in order do
			local data = entry.Poses[name]
			if data then
				local parentName = parentOf[name]
				made[name] = AddPose(if parentName then made[parentName] else keyframe, name, data.CFrame, data.Weight)
				poseCount += 1
			end
		end
		keyframe.Parent = result
	end

	return result, { Keyframes = #kept, Dense = dense, Length = length, Poses = poseCount, Warnings = warnings }
end

return AnimationConverter
