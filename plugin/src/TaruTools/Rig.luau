--!nonstrict
local Players = game:GetService("Players")

local AnimationConverter = require(script.Parent.AnimationConverter)

local Rig = {}

local generated = {}

function Rig.Generate(rigType)
	if not generated[rigType] then
		local description = Instance.new("HumanoidDescription")
		local grey = Color3.fromRGB(176, 176, 184)
		description.HeadColor = grey
		description.TorsoColor = grey
		description.LeftArmColor = grey
		description.RightArmColor = grey
		description.LeftLegColor = grey
		description.RightLegColor = grey
		generated[rigType] = Players:CreateHumanoidModelFromDescription(description, rigType)
	end
	return generated[rigType]:Clone()
end

local function CollectJoints(model)
	local found = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			if descendant.Part0 and descendant.Part1 then
				table.insert(found, { Part0 = descendant.Part0, Part1 = descendant.Part1, C0 = descendant.C0, C1 = descendant.C1 })
			end
		elseif descendant:IsA("AnimationConstraint") then
			local first, second = descendant.Attachment0, descendant.Attachment1
			if first and second and first.Parent and second.Parent then
				table.insert(found, { Part0 = first.Parent, Part1 = second.Parent, C0 = first.CFrame, C1 = second.CFrame })
			end
		end
	end
	return found
end

function Rig.Build(model)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local candidates = CollectJoints(model)
	local joints = {}
	local transforms = {}
	local solved = { [root] = true }
	local queue = { root }
	while #queue > 0 do
		local part = table.remove(queue, 1)
		for _, joint in candidates do
			if joint.Part0 == part and not solved[joint.Part1] then
				solved[joint.Part1] = true
				joint.Name = joint.Part1.Name
				table.insert(joints, joint)
				transforms[joint] = CFrame.identity
				table.insert(queue, joint.Part1)
			end
		end
	end

	local welds = {}
	for _, descendant in model:GetDescendants() do
		if (descendant:IsA("Weld") or descendant:IsA("WeldConstraint")) and descendant.Part0 and descendant.Part1 then
			table.insert(welds, descendant)
		end
	end
	local followers = {}
	local grew = true
	while grew do
		grew = false
		for _, weld in welds do
			local a, b = weld.Part0, weld.Part1
			if solved[a] and not solved[b] then
				solved[b] = true
				table.insert(followers, { Part = b, Parent = a, Offset = a.CFrame:Inverse() * b.CFrame })
				grew = true
			elseif solved[b] and not solved[a] then
				solved[a] = true
				table.insert(followers, { Part = a, Parent = b, Offset = b.CFrame:Inverse() * a.CFrame })
				grew = true
			end
		end
	end

	return { Model = model, Root = root, Joints = joints, Transforms = transforms, Followers = followers }
end

function Rig.Solve(rig)
	for _, joint in rig.Joints do
		joint.Part1.CFrame = joint.Part0.CFrame * joint.C0 * rig.Transforms[joint] * joint.C1:Inverse()
	end
	for _, follower in rig.Followers do
		follower.Part.CFrame = follower.Parent.CFrame * follower.Offset
	end
end

function Rig.Apply(rig, tracks, time)
	for _, joint in rig.Joints do
		local cframe = CFrame.identity
		local track = tracks and tracks[joint.Name]
		if track then
			local value, weight = AnimationConverter.Sample(track, time)
			if value then
				cframe = if weight >= 0.999 then value else CFrame.identity:Lerp(value, math.clamp(weight, 0, 1))
			end
		end
		rig.Transforms[joint] = cframe
	end
end

function Rig.Reset(rig)
	for _, joint in rig.Joints do
		rig.Transforms[joint] = CFrame.identity
	end
	Rig.Solve(rig)
end

function Rig.Stage(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Humanoid") or descendant:IsA("Animator") or descendant:IsA("Sound") or descendant:IsA("KeyframeSequence") or descendant:IsA("Folder") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	model:PivotTo(CFrame.new())
	local cframe, size = model:GetBoundingBox()
	model:PivotTo(CFrame.new(0, size.Y / 2 - cframe.Position.Y, 0))
	return Rig.Build(model)
end

return Rig
