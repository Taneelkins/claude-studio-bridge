--!strict
-- get_selection: what the user has selected in the Explorer.

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")

return function(_args: any): string
	local out = {}
	for _, inst in Selection:Get() do
		table.insert(out, { name = inst.Name, className = inst.ClassName, path = inst:GetFullName() })
	end
	return HttpService:JSONEncode({ selection = out, count = #out })
end
