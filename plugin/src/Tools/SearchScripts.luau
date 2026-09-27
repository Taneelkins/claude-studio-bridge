--!strict
-- search_scripts: grep every script's source under an ancestor.

local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

return function(args: any): string
	local ancestor = Resolver.resolve(args.ancestor)
	local pattern = args.pattern
	if type(pattern) ~= "string" or pattern == "" then
		error("Missing 'pattern'")
	end
	local plain = not args.lua_pattern
	local caseSensitive = args.case_sensitive == true
	local needle = if caseSensitive then pattern else string.lower(pattern)
	local limit = tonumber(args.limit) or 200

	local matches = {}
	local scanned, unreadable = 0, 0
	local truncated = false

	for _, inst in ancestor:GetDescendants() do
		if not inst:IsA("LuaSourceContainer") then
			continue
		end
		local ok, source = pcall(function()
			return (inst :: any).Source
		end)
		if not ok then
			unreadable += 1
			continue
		end
		scanned += 1
		local lineNo = 0
		for line in string.gmatch(source .. "\n", "(.-)\r?\n") do
			lineNo += 1
			local hay = if caseSensitive then line else string.lower(line)
			if string.find(hay, needle, 1, plain) then
				table.insert(matches, {
					path = inst:GetFullName(),
					line = lineNo,
					text = if #line > 240 then string.sub(line, 1, 240) .. "…" else line,
				})
				if #matches >= limit then
					truncated = true
					break
				end
			end
		end
		if truncated then
			break
		end
		if scanned % 50 == 0 then
			task.wait() -- keep Studio responsive on huge places
		end
	end

	return HttpService:JSONEncode({
		matches = matches,
		count = #matches,
		scriptsScanned = scanned,
		unreadableScripts = unreadable,
		truncated = truncated,
	})
end
