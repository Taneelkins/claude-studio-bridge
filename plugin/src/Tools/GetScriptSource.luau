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

	-- Optional line range: return just those lines, numbered, to save tokens.
	local first, last = tonumber(args.start_line), tonumber(args.end_line)
	if first or last then
		local lines = string.split(source, "\n")
		local from = math.max(1, first or 1)
		local to = math.min(#lines, last or #lines)
		local out = table.create(math.max(0, to - from + 1))
		for i = from, to do
			table.insert(out, string.format("%5d  %s", i, lines[i]))
		end
		return string.format("-- %s lines %d-%d of %d\n", instance:GetFullName(), from, to, #lines)
			.. table.concat(out, "\n")
	end

	return source
end
