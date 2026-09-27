--!strict
-- resolve_image_id: Decal asset id -> the Image id it wraps.

local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")

local Root = script.Parent.Parent
local AssetUtil = require(Root.AssetUtil)

local function findTexture(root: Instance): string?
	local decal = if root:IsA("Decal") then root else root:FindFirstChildWhichIsA("Decal", true)
	return if decal then (decal :: Decal).Texture else nil
end

return function(args: any): string
	local id = tonumber(args.asset_id)
	if not id then
		error("Missing 'asset_id'")
	end

	local texture: string? = nil
	local ok, err = pcall(function()
		local model = InsertService:LoadAsset(id)
		texture = findTexture(model)
		model:Destroy()
	end)
	if not texture then
		pcall(function()
			for _, obj in game:GetObjects("rbxassetid://" .. id) do
				texture = texture or findTexture(obj)
				obj:Destroy()
			end
		end)
	end

	local imageId = AssetUtil.idFromContent(texture)
	if not imageId then
		error(
			"Couldn't read an image from asset "
				.. id
				.. " (still processing/moderating, or not a Decal). "
				.. (if ok then "" else tostring(err))
		)
	end
	return HttpService:JSONEncode({ decalId = id, imageId = imageId, content = "rbxassetid://" .. imageId })
end
