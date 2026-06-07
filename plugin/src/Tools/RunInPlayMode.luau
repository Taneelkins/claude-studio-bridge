--!strict
-- run_in_play_mode: run Luau inside a real playtest, capture output, auto-stop.

local Root = script.Parent.Parent
local PlayMode = require(Root.PlayMode)

return function(args: any): string
	local code = args.code
	if type(code) ~= "string" or code == "" then
		error("Missing 'code' string")
	end

	local timeout = math.clamp(tonumber(args.timeout) or 10, 0.1, 120)
	local mode = if args.mode == "run_server" then "run_server" else "start_play"

	return PlayMode.runScript(code, timeout, mode)
end
