--!nonstrict
local CollectionService = game:GetService("CollectionService")

local Dummy = {}

local Tag = "TaruTestDummy"
local FolderName = "TaruConverted"

function Dummy.Find()
	for _, instance in CollectionService:GetTagged(Tag) do
		if instance:IsDescendantOf(game) and not instance:GetAttribute("TaruPreviewClone") then
			return instance
		end
	end
	return nil
end

function Dummy.Resolve(instance)
	local model = if instance:IsA("Model") then instance else instance:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model, humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Dummy.Set(instance)
	local model, humanoid = Dummy.Resolve(instance)
	if not model then
		return nil, "Select a rig with a Humanoid."
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil, model.Name .. " is not an R15 rig."
	end
	for _, tagged in CollectionService:GetTagged(Tag) do
		CollectionService:RemoveTag(tagged, Tag)
	end
	CollectionService:AddTag(model, Tag)
	return model
end

function Dummy.Clear()
	for _, tagged in CollectionService:GetTagged(Tag) do
		CollectionService:RemoveTag(tagged, Tag)
	end
end

function Dummy.Folder(model)
	local folder = model:FindFirstChild(FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FolderName
		folder.Parent = model
	end
	return folder
end

Dummy.Tag = Tag

return Dummy
