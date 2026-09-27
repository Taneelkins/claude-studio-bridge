--!strict
-- create_image_asset (internal, used by upload_asset without an API key):
-- rebuild an image from raw RGBA pixels in an EditableImage and publish it as
-- an Image asset with the logged-in Studio account.

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local AssetUtil = require(Root.AssetUtil)

return function(args: any): string
	local w, h = tonumber(args.width), tonumber(args.height)
	if not w or not h or type(args.pixels_b64) ~= "string" then
		error("Missing width/height/pixels_b64")
	end
	local size = Vector2.new(w, h)
	local pixels = AssetUtil.base64ToBuffer(args.pixels_b64)
	if buffer.len(pixels) ~= w * h * 4 then
		error(string.format("Pixel data is %d bytes; expected %d", buffer.len(pixels), w * h * 4))
	end

	local image = AssetService:CreateEditableImage({ Size = size })
	if not image then
		error("Studio couldn't allocate an EditableImage (memory budget?)")
	end
	image:WritePixelsBuffer(Vector2.zero, size, pixels)

	local creatorId, creatorType = AssetUtil.creatorParams(args)
	local ok, result, value = pcall(function()
		return AssetService:CreateAssetAsync(image, Enum.AssetType.Image, {
			Name = args.name or "Image",
			Description = args.description or "",
			CreatorId = creatorId,
			CreatorType = creatorType,
		})
	end)
	image:Destroy()

	if not ok then
		error("Upload failed: " .. tostring(result))
	end
	if result ~= Enum.CreateAssetResult.Success then
		error("Upload failed: " .. tostring(result) .. " " .. tostring(value))
	end
	return HttpService:JSONEncode({ assetId = value, creatorId = creatorId, creatorType = creatorType.Name })
end
