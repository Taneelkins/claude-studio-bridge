--!strict
-- get_asset_info: catalog info for any asset id.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

-- Enum.AssetType values by id, for a readable type name.
local function typeName(id: number?): string?
	if not id then
		return nil
	end
	for _, item in Enum.AssetType:GetEnumItems() do
		if item.Value == id then
			return item.Name
		end
	end
	return nil
end

return function(args: any): string
	local id = tonumber(args.asset_id)
	if not id then
		error("Missing 'asset_id'")
	end
	local info = MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	return HttpService:JSONEncode({
		assetId = id,
		name = info.Name,
		description = info.Description,
		assetType = typeName(info.AssetTypeId),
		assetTypeId = info.AssetTypeId,
		creator = info.Creator,
		created = info.Created,
		updated = info.Updated,
		isPublicDomain = info.IsPublicDomain,
	})
end
