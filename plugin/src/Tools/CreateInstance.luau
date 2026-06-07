--!strict
-- create_instance: make a new instance under a parent, optionally with props.

local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)
local Serialize = require(Root.Serialize)

return function(args: any): string
	local className = args.class_name
	if type(className) ~= "string" then
		error("Missing 'class_name'")
	end

	local parent = Resolver.resolve(args.parent)

	local instance: Instance?
	local createOk, createErr = pcall(function()
		instance = Instance.new(className)
	end)
	if not createOk or not instance then
		error("Could not create a '" .. className .. "': " .. tostring(createErr))
	end
	local newInstance = instance :: Instance

	if type(args.name) == "string" then
		newInstance.Name = args.name
	end

	local propErrors: { [string]: string } = {}
	if type(args.properties) == "table" then
		for propName, rawValue in args.properties do
			local ok, err = pcall(function()
				(newInstance :: any)[propName] = Serialize.decode(rawValue)
			end)
			if not ok then
				propErrors[propName] = tostring(err)
			end
		end
	end

	-- Parent last so listeners fire with the instance fully configured.
	newInstance.Parent = parent

	local result: any = {
		path = newInstance:GetFullName(),
		className = newInstance.ClassName,
	}
	if next(propErrors) then
		result.propertyErrors = propErrors
	end
	return HttpService:JSONEncode(result)
end
