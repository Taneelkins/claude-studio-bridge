--!strict
-- Shared helpers for the asset tools: who owns a new asset, and base64 decoding
-- for pixel payloads sent by the bridge.

local StudioService = game:GetService("StudioService")

local AssetUtil = {}

-- Owner for assets created from Studio: explicit args > the place's owner
-- (so group games get group assets) > the logged-in Studio user.
function AssetUtil.creatorParams(args: any): (number, Enum.AssetCreatorType)
	if args.creator_type and args.creator_id then
		return tonumber(args.creator_id) :: number,
			if args.creator_type == "group" then Enum.AssetCreatorType.Group else Enum.AssetCreatorType.User
	end
	if game.PlaceId ~= 0 and game.CreatorId ~= 0 then
		return game.CreatorId,
			if game.CreatorType == Enum.CreatorType.Group
				then Enum.AssetCreatorType.Group
				else Enum.AssetCreatorType.User
	end
	return StudioService:GetUserId(), Enum.AssetCreatorType.User
end

local DECODE = table.create(256, -1)
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #alphabet do
		DECODE[string.byte(alphabet, i) + 1] = i - 1
	end
end

function AssetUtil.base64ToBuffer(s: string): buffer
	local len = #s
	while len > 0 and string.byte(s, len) == 61 do -- strip "=" padding
		len -= 1
	end
	local out = buffer.create(len * 3 // 4)
	local o = 0
	local acc, bits = 0, 0
	for i = 1, len do
		local v = DECODE[string.byte(s, i) + 1]
		if v >= 0 then
			acc = bit32.bor(bit32.lshift(acc, 6), v)
			bits += 6
			if bits >= 8 then
				bits -= 8
				buffer.writeu8(out, o, bit32.band(bit32.rshift(acc, bits), 0xFF))
				o += 1
				acc = bit32.band(acc, bit32.lshift(1, bits) - 1)
			end
		end
	end
	return out
end

-- Pulls a numeric id out of "rbxassetid://123" / "http://www.roblox.com/asset/?id=123".
function AssetUtil.idFromContent(content: string?): number?
	if type(content) ~= "string" then
		return nil
	end
	local id = string.match(content, "(%d+)%s*$")
	return if id then tonumber(id) else nil
end

return AssetUtil
