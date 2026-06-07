--!strict
-- play_control: manually start (start_play / run_server) or stop a playtest.

local Root = script.Parent.Parent
local PlayMode = require(Root.PlayMode)

return function(args: any): string
	local mode = args.mode
	if mode == "start_play" or mode == "run_server" then
		return PlayMode.start(mode)
	elseif mode == "stop" then
		return PlayMode.stopAndWait()
	end
	error("mode must be 'start_play', 'run_server', or 'stop'")
end
