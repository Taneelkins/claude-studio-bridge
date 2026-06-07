--!strict
-- set_script_source: replace a script's source. Prefers the live editor buffer
-- (ScriptEditorService) so the change appears immediately in an open document.

local ScriptEditorService = game:GetService("ScriptEditorService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

return function(args: any): string
	local instance = Resolver.resolve(args.path)
	if not instance:IsA("LuaSourceContainer") then
		error(instance.ClassName .. " is not a script")
	end

	local source = args.source
	if type(source) ~= "string" then
		error("Missing 'source' string")
	end

	-- Preferred path: update the editor document (works whether or not it's open).
	local ok, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(instance, function()
			return source
		end)
	end)

	if not ok then
		-- Fallback: assign Source directly.
		local ok2, err2 = pcall(function()
			(instance :: any).Source = source
		end)
		if not ok2 then
			error(
				"Failed to set source. When prompted, grant script-modification "
					.. "permission, then retry. ("
					.. tostring(err)
					.. " / "
					.. tostring(err2)
					.. ")"
			)
		end
	end

	return string.format("Updated %s (%d characters).", instance:GetFullName(), #source)
end
