--!strict
-- set_properties: set one or more properties on an instance.
-- Set "Name" to rename; set "Parent" (Instance ref) to reparent/move.

local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)
local Serialize = require(Root.Serialize)

return function(args: any): string
	local instance = Resolver.resolve(args.path)
	if type(args.properties) ~= "table" then
		error("Missing 'properties' table")
	end

	local set = {}
	local errors: { [string]: string } = {}

	for propName, rawValue in args.properties do
		local ok, err = pcall(function()
			(instance :: any)[propName] = Serialize.decode(rawValue)
		end)
		if ok then
			table.insert(set, propName)
		else
			errors[propName] = tostring(err)
		end
	end

	local result: any = {
		path = instance:GetFullName(),
		set = set,
	}
	if next(errors) then
		result.errors = errors
	end
	return HttpService:JSONEncode(result)
end
