--!strict
-- Connection settings for the Claude bridge.
-- 127.0.0.1 (not "localhost") avoids IPv6/IPv4 resolution mismatches with the
-- Node bridge, which binds 127.0.0.1.

return {
	URL = "http://127.0.0.1:44755",
	REQUEST_ENDPOINT = "/request",
	RESPONSE_ENDPOINT = "/response",

	-- Seconds to wait before retrying after the bridge is unreachable.
	POLL_BACKOFF = 1,
	-- Print a help hint after this many consecutive connection failures.
	HINT_AFTER_FAILURES = 5,
}
