--!nonstrict
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local AnimationConverter = require(script.Parent.AnimationConverter)

local Pipeline = {}

local function Sources()
	local root = ServerStorage:FindFirstChild("TaruTools")
	if not root then
		root = Instance.new("Folder")
		root.Name = "TaruTools"
		root.Parent = ServerStorage
	end
	local folder = root:FindFirstChild("Sources")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Sources"
		folder.Parent = root
	end
	return folder
end

function Pipeline.IsConverted(instance)
	return instance:GetAttribute("TaruSource") ~= nil
end

function Pipeline.FindSource(instance)
	local guid = instance:GetAttribute("TaruSource")
	if not guid then
		return nil
	end
	local root = ServerStorage:FindFirstChild("TaruTools")
	local folder = root and root:FindFirstChild("Sources")
	return folder and folder:FindFirstChild(guid)
end

function Pipeline.ReadSettings(instance)
	local raw = instance:GetAttribute("TaruSettings")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(decoded) == "table" then decoded else nil
end

function Pipeline.Create(source, name, parent, settings, assetId)
	local result, report = AnimationConverter.Convert(source, settings)
	result.Name = name .. "_R15"
	local guid = HttpService:GenerateGUID(false)
	local copy = source:Clone()
	copy.Name = guid
	copy.Parent = Sources()
	result:SetAttribute("TaruSource", guid)
	result:SetAttribute("TaruName", name)
	result:SetAttribute("TaruSettings", HttpService:JSONEncode(settings))
	if assetId then
		result:SetAttribute("TaruAssetId", assetId)
	end
	result.Parent = parent
	return result, report
end

function Pipeline.Reapply(target, settings)
	local source = Pipeline.FindSource(target)
	if not source then
		error("the stored source copy is gone, convert from the original again")
	end
	local fresh, report = AnimationConverter.Convert(source, settings)
	for _, child in target:GetChildren() do
		child:Destroy()
	end
	for _, child in fresh:GetChildren() do
		child.Parent = target
	end
	target.Loop = fresh.Loop
	target.Priority = fresh.Priority
	target:SetAttribute("TaruSettings", HttpService:JSONEncode(settings))
	fresh:Destroy()
	return target, report
end

return Pipeline
