--!strict
-- undo / redo: step Studio's change history.

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local function step(redo: boolean, args: any): string
	local steps = math.clamp(tonumber(args.steps) or 1, 1, 50)
	local done = {}
	for _ = 1, steps do
		local can, name = if redo then ChangeHistoryService:GetCanRedo() else ChangeHistoryService:GetCanUndo()
		if not can then
			break
		end
		if redo then
			ChangeHistoryService:Redo()
		else
			ChangeHistoryService:Undo()
		end
		table.insert(done, tostring(name))
	end
	if #done == 0 then
		return "Nothing to " .. (if redo then "redo." else "undo.")
	end
	return (if redo then "Redid: " else "Undid: ") .. table.concat(done, ", ")
end

return {
	undo = function(args: any): string
		return step(false, args)
	end,
	redo = function(args: any): string
		return step(true, args)
	end,
}
