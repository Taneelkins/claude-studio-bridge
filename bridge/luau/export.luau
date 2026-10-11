-- export_to_blender, Studio side. Runs through the plugin's run_code, so it
-- needs no plugin change. Strictly read-only: nothing is parented, renamed or
-- set. EditableMesh / EditableImage objects are created unparented and
-- destroyed before returning.
--
-- The bridge prepends `local Args = {...}` and calls this once per page:
--   scan   { path, offset, limit }        -> nodes[offset+1 .. offset+limit]
--   meshes { ids }                        -> packed geometry per mesh id
--   image  { id, y0, rows }               -> RGBA rows [y0, y0+rows) of one image
-- Every reply is "RBXEXPORT:" .. base64(zstd(json)) so it stays small on the wire.

local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")

local function Pack(value)
	local raw = buffer.fromstring(HttpService:JSONEncode(value))
	local z = EncodingService:CompressBuffer(raw, Enum.CompressionAlgorithm.Zstd, 3)
	return "RBXEXPORT:" .. buffer.tostring(EncodingService:Base64Encode(z))
end

local function PackBuffer(b)
	local z = EncodingService:CompressBuffer(b, Enum.CompressionAlgorithm.Zstd, 3)
	return buffer.tostring(EncodingService:Base64Encode(z))
end

local function Resolve(path)
	local rest = path:gsub("^game%.?", "")
	local node = game
	while rest ~= "" do
		-- longest child name that prefixes the rest, so names with dots still work
		local best
		for _, child in node:GetChildren() do
			local n = child.Name
			if (rest == n or rest:sub(1, #n + 1) == n .. ".") and (not best or #n > #best.Name) then
				best = child
			end
		end
		if not best and node == game then
			local seg = rest:match("^[^%.]+")
			local ok, service = pcall(game.GetService, game, seg)
			if ok and service then best = service end
		end
		local after
		if not best then
			-- Name[N] picks the Nth child with that name (duplicates are common in maps)
			local name, index, tail = rest:match("^(.-)%[(%d+)%](.*)$")
			if name then
				local seen = 0
				for _, child in node:GetChildren() do
					if child.Name == name then
						seen += 1
						if seen == tonumber(index) then best = child break end
					end
				end
				after = tail:gsub("^%.", "")
			end
		end
		if not best then error("No instance at '" .. path .. "' (stuck at '" .. rest .. "')") end
		node = best
		rest = after or rest:sub(#best.Name + 2)
	end
	return node
end

local function Cf(cf)
	return { cf:GetComponents() }
end

local function V3(v)
	return { v.X, v.Y, v.Z }
end

local function Rgb(c)
	return { c.R, c.G, c.B }
end

local function ContentId(value)
	if typeof(value) == "Content" then return value.Uri or "" end
	return value or ""
end

local Shapes = { Block = "Block", Cylinder = "Cylinder", Ball = "Ball", Wedge = "Wedge", CornerWedge = "CornerWedge" }

local function Describe(inst, root, ids)
	local node = {
		id = ids[inst],
		parent = inst ~= root and ids[inst.Parent] or nil,
		name = inst.Name,
		class = inst.ClassName,
		path = inst:GetFullName(),
	}
	if inst:IsA("BasePart") then
		node.cf = Cf(inst.CFrame)
		node.size = V3(inst.Size)
		node.color = Rgb(inst.Color)
		node.material = inst.Material.Name
		node.transparency = inst.Transparency
		node.reflectance = inst.Reflectance
		if inst:IsA("Part") then
			node.kind = "shape"
			node.shape = Shapes[inst.Shape.Name] or "Block"
		elseif inst:IsA("WedgePart") then
			node.kind = "shape"
			node.shape = "Wedge"
		elseif inst:IsA("CornerWedgePart") then
			node.kind = "shape"
			node.shape = "CornerWedge"
		elseif inst:IsA("MeshPart") then
			node.kind = "mesh"
			node.mesh = ContentId(inst.MeshId)
			node.texture = ContentId(inst.TextureID)
			node.meshSize = V3(inst.MeshSize)
		elseif inst:IsA("TrussPart") then
			node.kind = "shape"
			node.shape = "Block"
			node.note = "TrussPart exported as a solid block"
		else
			node.kind = "placeholder"
			node.reason = inst:IsA("PartOperation") and "Union/negate geometry isn't readable from Studio" or (inst.ClassName .. " has no readable geometry")
		end
		local special = inst:FindFirstChildOfClass("SpecialMesh")
		if special and node.kind == "shape" then
			local t = special.MeshType.Name
			node.special = { type = t, scale = V3(special.Scale), offset = V3(special.Offset), mesh = ContentId(special.MeshId), texture = ContentId(special.TextureId), tint = V3(special.VertexColor) }
			if t == "FileMesh" then
				node.kind = "mesh"
				node.mesh = node.special.mesh
				node.texture = node.special.texture
			elseif t == "Brick" then node.shape = "Block"
			elseif t == "Cylinder" then node.shape = "Cylinder"
			elseif t == "Sphere" then node.shape = "Ball"
			elseif t == "Wedge" then node.shape = "Wedge"
			else
				node.kind = "placeholder"
				node.reason = "SpecialMesh type " .. t .. " isn't supported"
			end
		end
		local sa = inst:FindFirstChildOfClass("SurfaceAppearance")
		if sa then
			node.surface = { colorMap = ContentId(sa.ColorMap), alphaMode = sa.AlphaMode.Name, tint = Rgb(sa.Color) }
		end
		local decals = {}
		for _, d in inst:GetChildren() do
			if d:IsA("Decal") then
				table.insert(decals, { class = d.ClassName, face = d.Face.Name, texture = ContentId(d.Texture) })
			end
		end
		if #decals > 0 then node.decals = decals end
	elseif inst:IsA("Model") then
		node.pivot = Cf(inst:GetPivot())
	end
	return node
end

local function Scan()
	local root = Resolve(Args.path)
	-- containers are kept only if something exported sits under them
	local parts = {}
	if root:IsA("BasePart") then table.insert(parts, root) end
	local skipped = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif not d:IsA("Model") and not d:IsA("Folder") and not d:IsA("SpecialMesh") and not d:IsA("SurfaceAppearance") and not d:IsA("Decal") then
			skipped[d.ClassName] = (skipped[d.ClassName] or 0) + 1
		end
	end
	local keep, order = {}, {}
	local function Mark(inst)
		if keep[inst] then return end
		if inst ~= root then Mark(inst.Parent) end
		keep[inst] = true
		table.insert(order, inst)
	end
	Mark(root)
	for _, p in parts do Mark(p) end
	local ids = {}
	for i, inst in order do ids[inst] = i end
	local from, count = Args.offset or 0, Args.limit or 1500
	local nodes = {}
	for i = from + 1, math.min(#order, from + count) do
		table.insert(nodes, Describe(order[i], root, ids))
	end
	local cam = workspace.CurrentCamera
	return {
		total = #order,
		nodes = nodes,
		skipped = skipped,
		root = root:GetFullName(),
		placeId = game.PlaceId,
		creator = { type = game.CreatorType.Name, id = game.CreatorId },
		camera = { cf = Cf(cam.CFrame), fov = cam.FieldOfView, viewport = { cam.ViewportSize.X, cam.ViewportSize.Y } },
	}
end

-- Layout (little endian), all indices 0-based, 0xFFFFFFFF = none:
--   u32 nv, nuv, nn, nf | f32 pos[nv*3] | f32 uv[nuv*2] | f32 nrm[nn*3] | u32 face[nf*9] (v0..2, uv0..2, n0..2)
local function DumpMesh(id)
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri(id))
	local vIndex, uvIndex, nIndex = {}, {}, {}
	local verts, uvs, normals, faces = em:GetVertices(), em:GetUVs(), em:GetNormals(), em:GetFaces()
	for i, v in verts do vIndex[v] = i - 1 end
	for i, v in uvs do uvIndex[v] = i - 1 end
	for i, v in normals do nIndex[v] = i - 1 end
	local nv, nuv, nn, nf = #verts, #uvs, #normals, #faces
	local b = buffer.create(16 + nv * 12 + nuv * 8 + nn * 12 + nf * 36)
	buffer.writeu32(b, 0, nv)
	buffer.writeu32(b, 4, nuv)
	buffer.writeu32(b, 8, nn)
	buffer.writeu32(b, 12, nf)
	local o = 16
	for _, v in verts do
		local p = em:GetPosition(v)
		buffer.writef32(b, o, p.X); buffer.writef32(b, o + 4, p.Y); buffer.writef32(b, o + 8, p.Z)
		o += 12
	end
	for _, v in uvs do
		local p = em:GetUV(v)
		buffer.writef32(b, o, p.X); buffer.writef32(b, o + 4, p.Y)
		o += 8
	end
	for _, v in normals do
		local p = em:GetNormal(v)
		buffer.writef32(b, o, p.X); buffer.writef32(b, o + 4, p.Y); buffer.writef32(b, o + 8, p.Z)
		o += 12
	end
	local none = 0xFFFFFFFF
	for _, f in faces do
		local fv, fuv, fn = em:GetFaceVertices(f), em:GetFaceUVs(f), em:GetFaceNormals(f)
		for k = 1, 3 do buffer.writeu32(b, o, vIndex[fv[k]] or none); o += 4 end
		for k = 1, 3 do buffer.writeu32(b, o, fuv[k] and uvIndex[fuv[k]] or none); o += 4 end
		for k = 1, 3 do buffer.writeu32(b, o, fn[k] and nIndex[fn[k]] or none); o += 4 end
	end
	em:Destroy()
	return { data = PackBuffer(b), vertices = nv, faces = nf }
end

local function Meshes()
	local out = {}
	for _, id in Args.ids do
		local ok, res = pcall(DumpMesh, id)
		out[id] = ok and res or { error = tostring(res) }
	end
	return out
end

local function Image()
	local img = AssetService:CreateEditableImageAsync(Content.fromUri(Args.id))
	local size = img.Size
	local y0 = Args.y0 or 0
	local rows = math.min(Args.rows or size.Y, size.Y - y0)
	local b = img:ReadPixelsBuffer(Vector2.new(0, y0), Vector2.new(size.X, rows))
	img:Destroy()
	return { width = size.X, height = size.Y, y0 = y0, rows = rows, data = PackBuffer(b) }
end

local Modes = { scan = Scan, meshes = Meshes, image = Image }
local ok, res = pcall(Modes[Args.mode])
if not ok then return Pack({ error = tostring(res) }) end
return Pack(res)
