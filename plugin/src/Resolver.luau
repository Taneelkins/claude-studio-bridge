--!strict
-- Resolves dot-separated instance paths to Instances.
-- Accepts "game", "game.Workspace.Part", or service-rooted "Workspace.Part",
-- "ServerScriptService.Module", etc.

local Resolver = {}

function Resolver.resolve(path: string?): Instance
	if path == nil or path == "" or path == "game" or path == "Game" then
		return game
	end

	local parts = string.split(path, ".")
	local current: Instance?
	local startIndex = 2
	local first = parts[1]

	if first == "game" or first == "Game" then
		current = game
	else
		-- Try as a service first, then as a direct child of game.
		local ok, service = pcall(function()
			return game:GetService(first :: any)
		end)
		if ok and service then
			current = service
		else
			current = game:FindFirstChild(first)
		end
	end

	if not current then
		error(string.format("Could not resolve '%s' (unknown root '%s')", path, tostring(first)))
	end

	for i = startIndex, #parts do
		local segment = parts[i]
		local nextInstance = (current :: Instance):FindFirstChild(segment)
		if not nextInstance then
			error(
				string.format("Could not find '%s' under '%s'", segment, (current :: Instance):GetFullName())
			)
		end
		current = nextInstance
	end

	return current :: Instance
end

-- Non-throwing variant; returns nil if the path can't be resolved.
function Resolver.tryResolve(path: string?): Instance?
	local ok, result = pcall(Resolver.resolve, path)
	if ok then
		return result
	end
	return nil
end

return Resolver
