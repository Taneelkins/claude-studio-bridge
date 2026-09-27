--!strict
-- edit_script: replace an exact snippet inside a script instead of resending
-- the whole source. Reads/writes the live editor buffer (ScriptEditorService).

local ScriptEditorService = game:GetService("ScriptEditorService")
local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

local function countLines(s: string): number
	local _, n = string.gsub(s, "\n", "")
	return n
end

return function(args: any): string
	local instance = Resolver.resolve(args.path)
	if not instance:IsA("LuaSourceContainer") then
		error(instance.ClassName .. " is not a script")
	end
	local old, new = args.old_string, args.new_string
	if type(old) ~= "string" or old == "" then
		error("Missing 'old_string'")
	end
	if type(new) ~= "string" then
		error("Missing 'new_string'")
	end

	local okRead, source = pcall(function()
		return ScriptEditorService:GetEditorSource(instance :: any)
	end)
	if not okRead then
		error("Could not read the script (grant script-modification permission?): " .. tostring(source))
	end

	-- Find every occurrence (plain text).
	local positions = {}
	local from = 1
	while true do
		local s, e = string.find(source, old, from, true)
		if not s then
			break
		end
		table.insert(positions, s)
		from = (e :: number) + 1
	end

	if #positions == 0 then
		error("old_string not found in " .. instance:GetFullName() .. " (it must match exactly, including indentation)")
	end
	if #positions > 1 and not args.replace_all then
		error(
			string.format(
				"old_string appears %d times in %s; add surrounding context to make it unique, or pass replace_all",
				#positions,
				instance:GetFullName()
			)
		)
	end

	-- Splice back-to-front so earlier positions stay valid.
	local result = source
	for i = #positions, 1, -1 do
		local s = positions[i]
		result = string.sub(result, 1, s - 1) .. new .. string.sub(result, s + #old)
	end

	ScriptEditorService:UpdateSourceAsync(instance :: any, function()
		return result
	end)

	local firstLine = countLines(string.sub(source, 1, positions[1] - 1)) + 1
	return HttpService:JSONEncode({
		path = instance:GetFullName(),
		replacements = #positions,
		firstEditedLine = firstLine,
		lastEditedLine = firstLine + countLines(new),
		totalLines = countLines(result) + 1,
	})
end
