--!strict
-- Identifies this Studio window to the bridge so several Studios can be
-- connected at once and each chat can be linked to one of them.
--
-- studioId is random per plugin load (i.e. per Studio window/session); the
-- bridge re-finds a place after a restart by placeId instead.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local StudioService = game:GetService("StudioService")

local Config = require(script.Parent.Config)

local StudioInfo = {}

StudioInfo.studioId = string.lower((HttpService:GenerateGUID(false):gsub("-", ""))):sub(1, 12)

-- Published places report their real name (game.Name is often just "Place1");
-- looked up once per placeId because GetProductInfo yields.
local nameCache: { [number]: string } = {}
local lookupInFlight: { [number]: boolean } = {}

local function placeName(): string
	local placeId = game.PlaceId
	if placeId == 0 then
		return game.Name
	end
	local cached = nameCache[placeId]
	if cached then
		return cached
	end
	if not lookupInFlight[placeId] then
		lookupInFlight[placeId] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(placeId)
			end)
			nameCache[placeId] = if ok and info and info.Name then info.Name else game.Name
		end)
	end
	return game.Name
end

function StudioInfo.get(): { [string]: any }
	local userId = 0
	pcall(function()
		userId = StudioService:GetUserId()
	end)
	return {
		placeId = game.PlaceId,
		gameId = game.GameId,
		placeName = placeName(),
		creatorId = game.CreatorId,
		creatorType = game.CreatorType.Name,
		userId = userId,
		pluginVersion = Config.VERSION,
	}
end

-- URL-encoded JSON for the poll's query string.
function StudioInfo.encoded(): string
	return HttpService:UrlEncode(HttpService:JSONEncode(StudioInfo.get()))
end

return StudioInfo
