--!strict
-- publish_model: publish an instance as a Model asset from Studio (logged-in
-- account, no API key) and return its id; or push a new version of one.

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)
local AssetUtil = require(Root.AssetUtil)

return function(args: any): string
	local instance = Resolver.resolve(args.path)

	-- Model assets are published from a Model; wrap anything else in one.
	local object: Instance = instance
	local wrapper: Model? = nil
	if not instance:IsA("Model") then
		wrapper = Instance.new("Model")
		local w = wrapper :: Model
		w.Name = args.name or instance.Name
		instance:Clone().Parent = w
		object = w
	end

	local creatorId, creatorType = AssetUtil.creatorParams(args)
	local ok, result, value = pcall(function()
		if args.asset_id then
			return AssetService:CreateAssetVersionAsync(object, Enum.AssetType.Model, tonumber(args.asset_id) :: number, {
				CreatorId = creatorId,
				CreatorType = creatorType,
			})
		end
		return AssetService:CreateAssetAsync(object, Enum.AssetType.Model, {
			Name = args.name or instance.Name,
			Description = args.description or "",
			CreatorId = creatorId,
			CreatorType = creatorType,
		})
	end)
	if wrapper then
		wrapper:Destroy()
	end

	if not ok then
		error("Publishing failed: " .. tostring(result))
	end
	if result ~= Enum.CreateAssetResult.Success then
		error("Publishing failed: " .. tostring(result) .. " " .. tostring(value))
	end

	return HttpService:JSONEncode(if args.asset_id
		then { assetId = tonumber(args.asset_id), version = value }
		else { assetId = value, creatorId = creatorId, creatorType = creatorType.Name })
end
