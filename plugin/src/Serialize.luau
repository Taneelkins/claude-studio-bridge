--!strict
-- Converts Roblox datatypes to/from the JSON-friendly tagged form Claude uses.
-- See the VALUE_FORMAT explainer in bridge/src/tools.ts for the wire shape.

local Resolver = require(script.Parent.Resolver)

local Serialize = {}

local function hex(c: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.clamp(math.floor(c.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
	)
end

-- Roblox value -> JSON-friendly value
function Serialize.encode(value: any): any
	local t = typeof(value)
	if value == nil or t == "number" or t == "string" or t == "boolean" then
		return value
	elseif t == "Instance" then
		return { __type = "Instance", path = value:GetFullName(), className = value.ClassName }
	elseif t == "EnumItem" then
		return { __type = "Enum", value = (tostring(value):gsub("^Enum%.", "")) }
	elseif t == "Vector3" then
		return { __type = "Vector3", x = value.X, y = value.Y, z = value.Z }
	elseif t == "Vector2" then
		return { __type = "Vector2", x = value.X, y = value.Y }
	elseif t == "Color3" then
		return { __type = "Color3", r = value.R, g = value.G, b = value.B, hex = hex(value) }
	elseif t == "UDim" then
		return { __type = "UDim", scale = value.Scale, offset = value.Offset }
	elseif t == "UDim2" then
		return {
			__type = "UDim2",
			xScale = value.X.Scale,
			xOffset = value.X.Offset,
			yScale = value.Y.Scale,
			yOffset = value.Y.Offset,
		}
	elseif t == "CFrame" then
		return {
			__type = "CFrame",
			x = value.Position.X,
			y = value.Position.Y,
			z = value.Position.Z,
			components = { value:GetComponents() },
		}
	elseif t == "BrickColor" then
		return { __type = "BrickColor", value = tostring(value) }
	elseif t == "NumberRange" then
		return { __type = "NumberRange", min = value.Min, max = value.Max }
	elseif t == "Rect" then
		return { __type = "Rect", minX = value.Min.X, minY = value.Min.Y, maxX = value.Max.X, maxY = value.Max.Y }
	else
		return tostring(value)
	end
end

-- JSON-friendly value -> Roblox value
function Serialize.decode(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local kind = value.__type
	if not kind then
		return value -- plain table, left as-is
	end

	if kind == "Vector3" then
		return Vector3.new(value.x or 0, value.y or 0, value.z or 0)
	elseif kind == "Vector2" then
		return Vector2.new(value.x or 0, value.y or 0)
	elseif kind == "Color3" then
		if value.hex then
			return Color3.fromHex(value.hex)
		end
		return Color3.new(value.r or 0, value.g or 0, value.b or 0)
	elseif kind == "UDim" then
		return UDim.new(value.scale or 0, value.offset or 0)
	elseif kind == "UDim2" then
		return UDim2.new(value.xScale or 0, value.xOffset or 0, value.yScale or 0, value.yOffset or 0)
	elseif kind == "CFrame" then
		if value.components then
			return CFrame.new(table.unpack(value.components))
		end
		local cf = CFrame.new(value.x or 0, value.y or 0, value.z or 0)
		if value.orientation then
			cf = cf
				* CFrame.Angles(
					math.rad(value.orientation.x or 0),
					math.rad(value.orientation.y or 0),
					math.rad(value.orientation.z or 0)
				)
		end
		return cf
	elseif kind == "Enum" then
		local enumName, itemName = string.match(value.value, "([%w_]+)%.([%w_]+)")
		if enumName and itemName then
			return (Enum :: any)[enumName][itemName]
		end
		error("Invalid Enum value: " .. tostring(value.value))
	elseif kind == "BrickColor" then
		return BrickColor.new(value.value)
	elseif kind == "Instance" then
		return Resolver.resolve(value.path)
	elseif kind == "NumberRange" then
		return NumberRange.new(value.min or 0, value.max or value.min or 0)
	elseif kind == "Rect" then
		return Rect.new(value.minX or 0, value.minY or 0, value.maxX or 0, value.maxY or 0)
	end

	error("Unknown __type: " .. tostring(kind))
end

return Serialize
