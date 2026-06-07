--!strict
-- get_tree: return the Explorer hierarchy under a path as a nested tree.

local HttpService = game:GetService("HttpService")

local Root = script.Parent.Parent
local Resolver = require(Root.Resolver)

local DEFAULT_DEPTH = 3
local DEFAULT_MAX_NODES = 400

return function(args: any): string
	local rootInstance = Resolver.resolve(args.path)
	local maxDepth = tonumber(args.depth) or DEFAULT_DEPTH
	local maxNodes = tonumber(args.max_nodes) or DEFAULT_MAX_NODES

	local count = 0
	local truncated = false

	local function build(instance: Instance, depth: number): any
		count += 1
		local node: any = {
			name = instance.Name,
			className = instance.ClassName,
			path = instance:GetFullName(),
		}

		local children = instance:GetChildren()
		if #children == 0 then
			return node
		end

		if depth >= maxDepth then
			node.childCount = #children
			return node
		end

		local arr = {}
		for _, child in children do
			if count >= maxNodes then
				truncated = true
				break
			end
			table.insert(arr, build(child, depth + 1))
		end
		if #arr > 0 then
			node.children = arr
		end
		return node
	end

	local tree = build(rootInstance, 0)
	return HttpService:JSONEncode({
		tree = tree,
		nodeCount = count,
		truncated = truncated,
	})
end
