--!strict
-- search_instances: find instances by name substring and/or class under an ancestor.

local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

local DEFAULT_LIMIT = 100

return function(args: any): string
	local ancestor = Resolver.resolve(args.ancestor)
	local query = if type(args.query) == "string" and args.query ~= ""
		then string.lower(args.query)
		else nil
	local className = if type(args.class_name) == "string" and args.class_name ~= ""
		then args.class_name
		else nil
	local limit = tonumber(args.limit) or DEFAULT_LIMIT

	local matches = {}
	local truncated = false

	for _, descendant in ancestor:GetDescendants() do
		local nameOk = query == nil or string.find(string.lower(descendant.Name), query, 1, true) ~= nil
		local classOk = true
		if className then
			local ok, isA = pcall(function()
				return descendant:IsA(className)
			end)
			classOk = ok and isA
		end

		if nameOk and classOk then
			table.insert(matches, {
				name = descendant.Name,
				className = descendant.ClassName,
				path = descendant:GetFullName(),
			})
			if #matches >= limit then
				truncated = true
				break
			end
		end
	end

	return HttpService:JSONEncode({
		matches = matches,
		count = #matches,
		truncated = truncated,
	})
end
