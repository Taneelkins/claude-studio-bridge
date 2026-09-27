--!strict
-- insert_asset: bring an asset into the place by id. Picks the right way to
-- materialise it from the asset's type (Sound for audio, MeshPart for meshes,
-- Decal for images, LoadAsset for everything else).

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")
local Selection = game:GetService("Selection")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

local AUDIO, IMAGE, MESH, MESHPART = 3, 1, 4, 40

return function(args: any): string
	local id = tonumber(args.asset_id)
	if not id then
		error("Missing 'asset_id'")
	end
	local parent = Resolver.resolve(args.parent or "Workspace")
	local unpack = args.unpack ~= false

	local typeId: number? = nil
	local name = "Asset" .. id
	pcall(function()
		local info = MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
		typeId = info.AssetTypeId
		name = info.Name or name
	end)

	local inserted: { Instance } = {}

	if typeId == AUDIO then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxassetid://" .. id
		sound.Parent = parent
		table.insert(inserted, sound)
	elseif typeId == IMAGE then
		local decal = Instance.new("Decal")
		decal.Name = name
		decal.Texture = "rbxassetid://" .. id
		decal.Parent = parent
		table.insert(inserted, decal)
	elseif typeId == MESH or typeId == MESHPART then
		local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(id))
		part.Name = name
		part.Parent = parent
		table.insert(inserted, part)
	else
		local ok, model = pcall(function()
			return InsertService:LoadAsset(id)
		end)
		local roots: { Instance }
		if ok then
			roots = if unpack then (model :: Instance):GetChildren() else { model :: Instance }
		else
			roots = game:GetObjects("rbxassetid://" .. id)
		end
		for _, obj in roots do
			obj.Parent = parent
			table.insert(inserted, obj)
		end
		if ok and unpack then
			(model :: Instance):Destroy()
		end
	end

	Selection:Set(inserted)
	local paths = {}
	for _, inst in inserted do
		table.insert(paths, { path = inst:GetFullName(), className = inst.ClassName })
	end
	return HttpService:JSONEncode({ assetId = id, name = name, inserted = paths })
end
