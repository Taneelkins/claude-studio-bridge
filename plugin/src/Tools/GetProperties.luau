--!strict
-- get_properties: read properties and attributes of an instance.

local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)
local Serialize = require(Root.Serialize)

-- Commonly-useful properties tried when the caller doesn't specify names.
-- Reads that error (property absent on this class) are skipped silently.
local DEFAULT_PROPS = {
	"Name",
	"ClassName",
	"Parent",
	"Archivable",
	"Anchored",
	"CanCollide",
	"CanTouch",
	"Position",
	"Orientation",
	"Size",
	"CFrame",
	"Shape",
	"Color",
	"BrickColor",
	"Material",
	"Transparency",
	"Reflectance",
	"Enabled",
	"Visible",
	"Value",
	"Text",
	"TextColor3",
	"BackgroundColor3",
	"Disabled",
	"SourceAssetId",
}

return function(args: any): string
	local instance = Resolver.resolve(args.path)

	local result: any = {
		path = instance:GetFullName(),
		className = instance.ClassName,
		name = instance.Name,
		properties = {},
		attributes = {},
	}

	local explicit = type(args.properties) == "table"
	local names = if explicit then args.properties else DEFAULT_PROPS

	for _, propName in names do
		local ok, value = pcall(function()
			return (instance :: any)[propName]
		end)
		if ok then
			local vt = typeof(value)
			if vt ~= "function" and vt ~= "RBXScriptSignal" and vt ~= "RBXScriptConnection" then
				result.properties[propName] = Serialize.encode(value)
			end
		elseif explicit then
			-- The caller asked for this one specifically; tell them why it failed.
			result.properties[propName] = { __error = tostring(value) }
		end
	end

	for attrName, attrValue in instance:GetAttributes() do
		result.attributes[attrName] = Serialize.encode(attrValue)
	end

	return HttpService:JSONEncode(result)
end
