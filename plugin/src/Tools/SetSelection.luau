--!strict
-- set_selection: select instances in the Explorer.

local Selection = game:GetService("Selection")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

return function(args: any): string
	local list = {}
	for _, path in (args.paths or {}) :: { string } do
		table.insert(list, Resolver.resolve(path))
	end
	Selection:Set(list)
	return string.format("Selected %d instance(s).", #list)
end
