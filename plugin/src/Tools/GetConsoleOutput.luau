--!strict
-- get_console_output: return the most recent Studio output/console lines.

local LogService = game:GetService("LogService")

local TYPE_LABEL: { [Enum.MessageType]: string } = {
	[Enum.MessageType.MessageOutput] = "OUTPUT",
	[Enum.MessageType.MessageInfo] = "INFO",
	[Enum.MessageType.MessageWarning] = "WARN",
	[Enum.MessageType.MessageError] = "ERROR",
}

return function(args: any): string
	local count = tonumber(args.count) or 60
	local history = LogService:GetLogHistory()
	local total = #history
	local startIndex = math.max(1, total - count + 1)

	local lines = {}
	for i = startIndex, total do
		local entry: any = history[i]
		-- Field casing on the returned table is lowercase; guard just in case.
		local message = entry.message or entry.Message or ""
		local messageType = entry.messageType or entry.MessageType
		local label = TYPE_LABEL[messageType] or "OUTPUT"
		table.insert(lines, string.format("[%s] %s", label, message))
	end

	if #lines == 0 then
		return "(console is empty)"
	end
	return table.concat(lines, "\n")
end
