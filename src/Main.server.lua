local PREFABSYS_DEBUG_MODE = false

local warnLogger = require("./Lib/Slogger").init{
	postInit = table.freeze,
	logFunc = warn
}

local warn = warnLogger.new("PrefabSystem")

local debbieDebug = require("./Lib/DebbieDebug")
debbieDebug.init(function()
    return PREFABSYS_DEBUG_MODE or workspace:GetAttribute("PrefabSys_Debug") == true
end)

local glut = require("./Lib/GLUt")
glut.configure{ warn = warn }

local apiConsumer = require("./Lib/APIConsumer")

local luaExpr = require("./Lib/LuaExpr")
local luaExprFuncs = require("./LuaExprFuncs")
local shebangFuncs = require("./ShebangFuncs")

local attrEval = require("./AttributeEval/Main")
local sFuncEval = require("./SFuncEval/Main")

local PrefabScope  = require("./PrefabScope")
local PrefabTarget = require("./PrefabTarget")

local exprRules = luaExpr.NewEvalRules("%$%(", "%)")

type APIReference = apiConsumer.APIReference

local hookName = nil
local API_ID = "InfiltrationEngine-PrefabSystem"

local prefabSystem = {}

function prefabSystem.OnAPILoaded(api: APIReference, prefabSystemState)
	prefabSystemState.Hooks = prefabSystemState.Hooks or {}
	prefabSystemState.ExtHooks = prefabSystemState.ExtHooks or {}
	prefabSystemState.ApiExtensions = prefabSystemState.ApiExtensions or {}
	prefabSystem.OnAPIUnloaded(api, prefabSystemState)
	
	hookName = api.GetRegistrantFactory("Sprix", "PrefabSystem")
	local attributeImporterAPI = api.GetAPIExtension("AttributeImporter", "Sprix")
	if attributeImporterAPI then
		prefabSystem.OnAPIExtensionLoaded(prefabSystemState, nil, "AttributeImporter", "Sprix", attributeImporterAPI)
	end
	
	prefabSystemState.Hooks[1] = api.AddHook("PreSerialize", hookName("PreSerialize"), prefabSystem.OnSerializerExport)
	prefabSystemState.Hooks[2] = api.AddHook("APIExtensionLoaded", hookName("APIExtensionLoaded"), prefabSystem.OnAPIExtensionLoaded, prefabSystemState)
	prefabSystemState.Hooks[3] = api.AddHook("APIExtensionUnloaded", hookName("APIExtensionUnloaded"), prefabSystem.OnAPIExtensionUnloaded, prefabSystemState)
end

function prefabSystem.ImportAttributesForPrefab(prefabName)
	local warn = warn.specialize("AttributeImport")
	
	local mission = workspace:FindFirstChild("DebugMission")
	if mission == nil then
		warn("No Mission folder found!")
	end
	
	local prefabs = mission:FindFirstChild("Prefabs")
	
	if prefabs == nil then
		warn("No Prefabs folder found!")
		return {} 
	end
	
	local prefab = nil
	for _, potentialPrefab in ipairs(prefabs:GetChildren()) do
		if potentialPrefab.Name ~= prefabName then continue end
		prefab = potentialPrefab
	end
	
	if prefab == nil then
		warn(`Prefab {prefabName} not found!`)
		return {} 
	end
	
	local instance = prefab:FindFirstChild("Instance")
	if instance == nil then
		warn(`Failed to find instance scope for Prefab {prefabName}`)
		return {} 
	end
	
	local instanceBase = instance:FindFirstChild("InstanceBase")
	if instanceBase == nil then
		warn(`Failed to find InstanceBase for Prefab {prefabName}`)
		return {}
	end
	
	local importing = {}
	for attrName, attrDefault in pairs(instanceBase:GetAttributes()) do
		if glut.str_has_match(attrName, "^noimp%.") then continue end
		importing[attrName:gsub("^imponly%.", "")] = { type(attrDefault), attrDefault }
	end
	
	return importing
end

function prefabSystem.OnAPIExtensionLoaded(prefabSystemState, _, name, author, contents)
	if author ~= "Sprix" or name ~= "AttributeImporter" then return end
	
	-- Register ourselves with the Attribute Importer if available
	prefabSystemState.ExtHooks[1] = {
		Name = "AttributeImporter",
		Auth = "Sprix",
		Dereg = "RemoveAbstractionImporter",
		Token = contents.AddAbstractionImporter(
			"PrefabSystem",
			require("./AttributeImporterSearchInfo"),
			prefabSystem.ImportAttributesForPrefab
		)	
	}
end

local extHookIter = glut.custom_iter_template("Name", "Auth", "Dereg", "Token")
function prefabSystem.OnAPIExtensionUnloaded(prefabSystemState, _, name, author, contents)
	local removing = {}
	for i, extName, extAuth, extDereg, extToken in extHookIter(prefabSystemState.ExtHooks) do
		if name ~= extName or author ~= extAuth then continue end
		if contents[extDereg] == nil then continue end
		contents[extDereg](extToken)
		removing[#removing] = i
	end
	for idx=#removing, 1, -1 do
		table.remove(prefabSystemState.ExtHooks, removing[idx])
	end 
end

function prefabSystem.OnAPIUnloaded(api: APIReference, prefabSystemState)
	for _, token in ipairs(prefabSystemState.Hooks) do
		if token == nil then
			warn(`Attempt to de-register nil hook?`)
			continue
		end
		api.RemoveHook(token)
	end
	for i, extName, extAuth, extDereg, extToken in extHookIter(prefabSystemState.ExtHooks) do
		local ext = api.GetAPIExtension(extName, extAuth)
		if ext == nil then continue end
		if ext[extDereg] == nil then continue end
		ext[extDereg](extToken)
	end
	for _, extToken in ipairs(prefabSystemState.ApiExtensions) do
		if extToken == nil then
			warn(`Attempt to de-register nil API Extension?`)
		end
		api.RemoveAPIExtension(extToken)
	end
end

function prefabSystem.OnSerializerExport(hookState: {any}, invokeState, mission: Folder)
	local warn = warnLogger.new("OnSerializerExport")
	
	local prefabFolder = mission:FindFirstChild("Prefabs")
	if not prefabFolder then return end
	
	local first = true
	repeat
		if not first then coroutine.yield() end
		local _, present = invokeState.Get("Sprix_AttributeAuditor_PreSerialize_Present")
		local success, done = invokeState.Get("Sprix_AttributeAuditor_PreSerialize", "Done")
		first = false
	until (not present) or (success and done)
	
	if workspace:GetAttribute("EmeraldMode") then
		print("Hi i'm prefabsystem :3")
	end
	
	local prefabInstanceFolder = mission:FindFirstChild("PrefabInstances")
	if not prefabInstanceFolder then
		-- Prevents prefabs from being exported & wasting space in the mission code
		prefabFolder:Destroy()
		return
	end

	local globalState = table.freeze({})
	local staticStates = {}
	local prefabInstances = prefabInstanceFolder:GetDescendants()
	local i = 1
	while i <= #prefabInstances do
		local prefabInstance = prefabInstances[i]
		i = i + 1
		
		local warn = warn.specialize(`PrefabInstance {prefabInstance.Name} is invalid`)
		
		if prefabInstance:IsA("Folder") then continue end
		if prefabInstance.Parent:IsA("BasePart") then continue end
		
		if not prefabInstance:IsA("BasePart") then
			warn(`Expected BasePart, got {prefabInstance.ClassName}. Skipping.`)
			continue
		end
		
		local prefabInstanceType = prefabInstance:GetAttribute("PrefabName")
		if type(prefabInstanceType) ~= "string" then
			warn(`PrefabName attribute is of wrong datatype or otherwise invalid. Skipping.`)
			continue
		end
		
		local instantiatingPrefab = prefabFolder:FindFirstChild(prefabInstanceType)
		if instantiatingPrefab == nil then
			warn(`PrefabName points to non-existing prefab {prefabInstanceType}. Skipping.`)
			continue
		end
		
		local prefabStatic = staticStates[instantiatingPrefab] or {}
		prefabSystem.InstantiatePrefab(mission, instantiatingPrefab, prefabInstance, prefabStatic, globalState)
		staticStates[instantiatingPrefab] = prefabStatic
		for _, i in ipairs(prefabInstanceFolder:GetDescendants()) do
			if not table.find(prefabInstances, i) then prefabInstances[#prefabInstances+1] = i end
		end
	end
	
	for _, prefab in ipairs(prefabFolder:GetChildren()) do
		if not prefab:IsA("Folder") then
			warn(`Prefab {prefab.Name} is invalid`, `Expected Folder, got {prefab.ClassName}`, "Prefab Will Be Ignored")
			continue
		end

		local prefabStatic = staticStates[prefab] or {}
		prefabSystem.UnpackPrefab(mission, prefab, "Static", function(mission, prefabTargetGroup)
			attrEval.EvaluateAllRecurse(prefabTargetGroup, { Instance = prefabStatic, Static = prefabStatic, Global = globalState })
		end)
		
	end
	
	-- Prevent these from being exported and taking up mission space
	prefabFolder:Destroy()
	prefabInstanceFolder:Destroy()
end

function prefabSystem.UnpackPrefab(mission: Folder, prefab: Folder, scope: string, preUnpack)
	preUnpack = glut.default(preUnpack, function() end)
	
	local scopeFolder = PrefabScope.GetScopeOfType(prefab, scope)
	if scopeFolder == nil then return end
	local modifiedScopes = preUnpack(mission, scopeFolder) or {scopeFolder}
	for _, modifiedScope in ipairs(modifiedScopes) do
		PrefabScope.UnpackToMission(modifiedScope, mission)
	end
end

function prefabSystem.InstantiatePrefab(mission: Folder, prefab: Folder, prefabInstance: BasePart, staticState, globalState)
	local warn = warn.specialize("InstantiatePrefab", `Prefab {prefab.Name}`)
	
	local instanceScope = PrefabScope.GetScopeOfType(prefab, "Instance")
	if not instanceScope then
		warn("Prefab may not be instantiated!")
		return
	end
	
	local instanceData = instanceScope:Clone()
	local instanceBase = instanceData:FindFirstChild("InstanceBase")
	if not instanceBase then
		warn("Instance folder found but no InstanceBase part present!")
		return
	end
	
	if not instanceBase:IsA("Part") then
		warn("InstanceBase found but not a part!")
		return
	end
	
	local sFuncTree = sFuncEval.DeriveSFuncTree(instanceBase)
	sFuncEval.RunSFuncTree(sFuncTree, prefab, prefabInstance)
	
	local instanceSettings = {}
	for k, v in pairs(instanceBase:GetAttributes()) do
		if glut.str_has_match(k, "^imponly%.") then continue end
		local kBase = k:gsub("^noimp%.", "")
		if instanceSettings[kBase] ~= nil then
			warn(`Attribute {kBase} is defined multiple times, conflicting with {k}`)
			warn(`Delete {kBase} or replace with imponly.{kBase} to silence!`)
		end
		instanceSettings[kBase] = v
	end
	
	for settingName, instanceValue in pairs(prefabInstance:GetAttributes()) do
		local warn = warn.specialize(`Ignoring invalid attribute {settingName}`)
		
		if settingName == "PrefabName" then continue end
		
		settingName = string.gsub(settingName, "^noimp%.", "")
		local defaultValue = instanceSettings[settingName] 
		
		if type(defaultValue) == "string" then
			local isSFunc = sFuncEval.IsSFunc(defaultValue)
			if isSFunc then instanceSettings[settingName] = instanceValue continue end
		end
		
		if defaultValue == nil then
			warn("Attribute not present on InstanceBase")
			continue
		end
		
		if type(defaultValue) ~= type(instanceValue) then
			warn(`Expected type {type(defaultValue)} but got {type(instanceValue)}`)
			continue
		end
		
		instanceSettings[settingName] = instanceValue
	end
	
	local evalState = { Instance = instanceSettings, Static = staticState, Global = globalState }
	local cfrSet = attrEval.EvaluateAllRecurse(instanceData, evalState, { "this.CFrame" })["this.CFrame"] or {}
	
	staticState.Attrs = staticState.Attrs or {}
	staticState.Attr = staticState.Attrs
	local staticAttrs = staticState.Attrs
	for k, v in pairs(instanceSettings) do
		staticAttrs[k] = staticAttrs[k] or {}
		local attrTbl = staticAttrs[k]
		table.insert(attrTbl, v)
	end
	
	for _, prefabElement in pairs(instanceData:GetDescendants()) do
		if prefabElement == instanceBase then continue end
		if not prefabElement:IsA("BasePart") then continue end
		if cfrSet[prefabElement] ~= nil then continue end
		local baseToElement = instanceBase.CFrame:ToObjectSpace(prefabElement.CFrame)
		prefabElement.CFrame = prefabInstance.CFrame:ToWorldSpace(baseToElement)
	end
	
	PrefabScope.UnpackToMission(instanceData, mission)
	
	local remoteTargetGroup = PrefabScope.GetScopeOfType(prefab, "Remote")
	if not remoteTargetGroup then return end
	
	for _, target in ipairs(remoteTargetGroup:GetChildren()) do
		local remoteFuncs = {}
		for _, v in ipairs(target:GetDescendants()) do
			if v:IsA("Folder") then continue end
			if not v:IsA("ValueBase") then
				warn(`Instance {v} in {prefab}.{remoteTargetGroup}.{target} is invalid`, `Expected ValueBase|Folder, got {v.ClassName}`)
			end
			remoteFuncs[#remoteFuncs+1] = v
		end
		
		local missionTarget = PrefabTarget.ToMissionTarget(target, mission)
		if missionTarget == nil then continue end
		for _, missionTargetItem in ipairs(missionTarget:GetDescendants()) do
			if not missionTargetItem:IsA("BasePart") then continue end
			if not prefabSystem.PointInPartBounds(instanceBase, missionTargetItem.Position) then continue end
			
			for _, remoteFunc in ipairs(remoteFuncs) do
				
			end
			
		end
	end
	
end

function prefabSystem.PointInPartBounds(part, point)
	point = part.CFrame:PointToObjectSpace(point):Abs() * 0.5
	return (point.X <= part.Size.X) and (point.Y <= part.Size.Y) and (point.Z <= part.Size.Z)
end

apiConsumer.DoAPILoop(plugin, API_ID, prefabSystem.OnAPILoaded, prefabSystem.OnAPIUnloaded)