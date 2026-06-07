--!strict
-- Long-poll transport. Repeatedly GETs /request; when the bridge hands back a
-- command it runs the supplied handler and POSTs the result to /response.
--
-- The plugin can't accept connections, so it pulls work from the bridge:
--   200 -> command body {id, args}; handle it, then poll again immediately
--   423 -> nothing queued yet; poll again immediately (this is the long-poll idle)
--   else -> bridge unreachable; back off, then retry

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)

export type Message = { id: string, args: { [string]: any } }
-- handler(message) -> success, responseText
export type Handler = (Message) -> (boolean, string)

export type Connection = {
	stop: () -> (),
	isRunning: () -> boolean,
}

local Transport = {}

local function httpRequest(method: string, url: string, body: any?)
	return pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = { ["Content-Type"] = "application/json" },
			Body = if body then HttpService:JSONEncode(body) else nil,
			Compress = Enum.HttpCompression.None,
		})
	end)
end

function Transport.start(handler: Handler): Connection
	local running = true
	local requestUrl = Config.URL .. Config.REQUEST_ENDPOINT
	local responseUrl = Config.URL .. Config.RESPONSE_ENDPOINT
	local failures = 0
	local hintShown = false

	task.spawn(function()
		while running do
			local ok, response = httpRequest("GET", requestUrl)

			if ok and response and response.StatusCode == 200 and response.Success then
				failures = 0
				hintShown = false

				local decodeOk, message = pcall(function()
					return HttpService:JSONDecode(response.Body)
				end)

				if decodeOk and type(message) == "table" and message.id then
					local success, result = handler(message)
					if running then
						httpRequest("POST", responseUrl, {
							id = message.id,
							success = success,
							response = result,
						})
					end
				end
				-- loop immediately for the next command
			elseif ok and response and response.StatusCode == 423 then
				-- idle long-poll returned empty; poll again right away
				failures = 0
				hintShown = false
			else
				failures += 1
				if failures >= Config.HINT_AFTER_FAILURES and not hintShown then
					hintShown = true
					warn(
						"[Claude Bridge] Can't reach the bridge at "
							.. Config.URL
							.. ". Make sure the Node bridge is running (Claude Code launches it), "
							.. "and that Studio is allowed to make HTTP requests "
							.. '(Game Settings > Security > "Allow HTTP Requests", '
							.. 'or run game:GetService("HttpService").HttpEnabled = true in the command bar).'
					)
				end
				task.wait(Config.POLL_BACKOFF)
			end
		end
	end)

	return {
		stop = function()
			running = false
		end,
		isRunning = function()
			return running
		end,
	}
end

return Transport
