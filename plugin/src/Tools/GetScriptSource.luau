--!strict
-- get_script_source: read the source of a Script / LocalScript / ModuleScript.

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

return function(args: any): string
	local instance = Resolver.resolve(args.path)
	if not instance:IsA("LuaSourceContainer") then
		error(instance.ClassName .. " is not a script (expected Script/LocalScript/ModuleScript)")
	end

	local ok, source = pcall(function()
		return (instance :: any).Source
	end)
	if not ok then
		error(
			"Could not read Source. When prompted, grant this plugin "
				.. "script-modification permission, then retry. ("
				.. tostring(source)
				.. ")"
		)
	end

	return source
end
