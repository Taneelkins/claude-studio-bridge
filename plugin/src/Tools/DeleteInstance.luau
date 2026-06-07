--!strict
-- delete_instance: destroy an instance and its descendants.

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

return function(args: any): string
	local instance = Resolver.resolve(args.path)
	if instance == game then
		error("Refusing to destroy the DataModel (game)")
	end
	if instance:IsA("Workspace") or instance:IsA("ServiceProvider") then
		error("Refusing to destroy core service '" .. instance.ClassName .. "'")
	end

	local fullName = instance:GetFullName()
	instance:Destroy()
	return "Destroyed " .. fullName
end
