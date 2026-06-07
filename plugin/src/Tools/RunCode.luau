--!strict
-- run_code: compile and run arbitrary Luau in edit mode, capturing output.
-- print/warn are redirected into a per-run sandbox env so we don't clobber the
-- real globals; everything else falls through to the normal environment.

local HttpService = game:GetService("HttpService")

local function stringify(value: any): string
	local t = typeof(value)
	if t == "string" then
		return value
	elseif t == "table" then
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(value)
		end)
		return if ok then encoded else tostring(value)
	end
	return tostring(value)
end

local function joinArgs(...): string
	local packed = table.pack(...)
	local parts = table.create(packed.n)
	for i = 1, packed.n do
		parts[i] = stringify(packed[i])
	end
	return table.concat(parts, "\t")
end

return function(args: any): string
	local command = args.command
	if type(command) ~= "string" then
		error("Missing 'command' string")
	end

	if not loadstring then
		error("loadstring is unavailable in this context")
	end

	local chunk, compileErr = loadstring(command)
	if not chunk then
		error("Compile error: " .. tostring(compileErr))
	end

	local output = {}
	local function emit(header: string, ...)
		table.insert(output, header .. " " .. joinArgs(...))
	end

	-- Sandbox env: capture print/warn, inherit everything else (game, Instance, ...).
	local sandbox = setmetatable({}, { __index = getfenv(0) })
	sandbox.print = function(...)
		emit("[OUTPUT]", ...)
	end
	sandbox.warn = function(...)
		emit("[WARN]", ...)
	end
	setfenv(chunk, sandbox)

	local results = table.pack(pcall(chunk))
	if not results[1] then
		emit("[ERROR]", results[2])
	elseif results.n > 1 then
		emit("[RETURN]", table.unpack(results, 2, results.n))
	end

	if #output == 0 then
		return "(ran successfully, no output)"
	end
	return table.concat(output, "\n")
end
