--!strict
-- Connection settings for the Claude bridge.
-- 127.0.0.1 (not "localhost") avoids IPv6/IPv4 resolution mismatches with the
-- Node bridge, which binds 127.0.0.1.

return {
	VERSION = "2.0.0",
	URL = "http://127.0.0.1:44755",
	REQUEST_ENDPOINT = "/request",
	RESPONSE_ENDPOINT = "/response",

	-- Seconds to wait before retrying after the bridge is unreachable.
	POLL_BACKOFF = 1,
	-- Print a help hint only after this many consecutive failures (~seconds).
	-- High enough that the brief reconnect after a playtest doesn't trigger it.
	HINT_AFTER_FAILURES = 20,
}
