local apiConsumerInit = require(script.Parent.APIConsumer)
local apiConsumer = apiConsumerInit(plugin)

type SerializerAPI = apiConsumerInit.SerializerAPI

local API_ID = "InfiltrationEngine-PrefabSystem"

local prefabSystem = {}

function prefabSystem.OnAPILoaded(api: SerializerAPI, prefabSystemState)
	prefabSystemState.ExportCallbackToken = api.AddHook("PreSerialize", API_ID, prefabSystem.OnSerializerExport)
end

function prefabSystem.OnAPIUnloaded(api: SerializerAPI, prefabSystemState)
	if prefabSystemState.ExportCallbackToken then
		-- More of a formality than anything in this case
		-- Hooks should be GC'd after serializer unload
		api.RemoveHook("PreSerialize", prefabSystemState.ExportCallbackToken)
	end
end

function prefabSystem.OnSerializerExport(mission: Folder)
	local prefabFolder = mission:FindFirstChild("Prefabs")
	if not prefabFolder then return end
	
	for _, prefab in ipairs(prefabFolder:GetChildren()) do
		if not prefab:IsA("Folder") then
			warn(`Prefab {prefab.Name} is invalid - expected Folder, got {prefab.ClassName}. Skipping.`)
			continue
		end
		
		prefabSystem.UnpackPrefab(mission, prefab, "Static")
	end
	
	local prefabInstanceFolder = mission:FindFirstChild("PrefabInstances")
	if not prefabInstanceFolder then
		-- Prevents prefabs from being exported & wasting space in the mission code
		prefabFolder:Destroy()
		return
	end
	
	for _, prefabInstance in ipairs(prefabInstanceFolder:GetChildren()) do
		if not prefabInstance:IsA("BasePart") then
			warn(`PrefabInstance {prefabInstance.Name} is invalid - expected BasePart, got {prefabInstance.ClassName}. Skipping.`)
			continue
		end
		
		local prefabInstanceType = prefabInstance:GetAttribute("PrefabName")
		if type(prefabInstanceType) ~= "string" then
			warn(`PrefabInstance {prefabInstance.Name} is invalid - PrefabName attribute is of wrong datatype or otherwise invalid. Skipping.`)
			continue
		end
		
		local instantiatingPrefab = prefabFolder:FindFirstChild(prefabInstanceType)
		if instantiatingPrefab == nil then
			warn(`PrefabInstance {prefabInstance.Name} is invalid - PrefabName points to non-existing prefab {prefabInstanceType}. Skipping.`)
			continue
		end
		
		prefabSystem.InstantiatePrefab(mission, instantiatingPrefab, prefabInstance)
	end
	
	-- Prevent these from being exported and taking up mission space
	prefabFolder:Destroy()
	prefabInstanceFolder:Destroy()
end

function prefabSystem.UnpackPrefab(mission: Folder, prefab: Folder, scope: string)
	for _, prefabTargetGroup in ipairs(prefab:GetChildren()) do
		if not prefabTargetGroup:IsA("Folder") then
			warn(`PrefabTargetGroup {prefabTargetGroup.Name} is invalid - expected Folder, got {prefabTargetGroup.ClassName}. Skipping.`)
			continue
		end
		
		if not prefabTargetGroup.Name:lower():find(`^{scope:lower()}`) then continue end
		prefabSystem.UnpackPrefabTargets(mission, prefabTargetGroup)
	end
end

function prefabSystem.UnpackPrefabTargets(mission: Folder, targetGroup: Folder)
	for _, prefabTarget in ipairs(targetGroup:GetChildren()) do
		if prefabTarget.Name == "InstanceBase" then continue end
		
		if not prefabTarget:IsA("Folder") then
			warn(`PrefabTarget {prefabTarget.Name} is invalid - expected Folder, got {prefabTarget.ClassName}. Skipping.`)
			continue
		end

		local missionPrefabTarget = mission:FindFirstChild(prefabTarget.Name) 
		if missionPrefabTarget == nil then warn(`Prefab target {prefabTarget.Name} does not exist! Create it if needed.`) continue end
		for _, prefabTargetItem in ipairs(prefabTarget:GetChildren()) do
			prefabTargetItem:Clone().Parent = missionPrefabTarget 
		end
	end
end

function prefabSystem.InstantiatePrefab(mission: Folder, prefab: Folder, prefabInstance: BasePart)
	local instanceTargetGroup = prefab:FindFirstChild("Instance") or prefab:FindFirstChild("instance")
	if not instanceTargetGroup then
		warn(`Prefab {prefab.Name} may not be instantiated!`)
		return
	end
	
	local instanceData = instanceTargetGroup:Clone()
	local instanceBase = instanceData:FindFirstChild("InstanceBase")
	if not instanceBase then
		warn(`Prefab {prefab.Name} has an Instance folder but no InstanceBase part!`)
		return
	end
	
	if not instanceBase:IsA("Part") then
		warn(`Prefab {prefab.Name} has an InstanceBase but it is not a part!`)
		return
	end
	
	local instanceSettings = instanceBase:GetAttributes()
	for settingName, instanceValue in pairs(prefabInstance:GetAttributes()) do
		if settingName == "PrefabName" then continue end
		
		local defaultValue = instanceSettings[settingName] 
		if defaultValue == nil then
			warn(`Attribute {settingName} is not valid for instances of prefab {prefab.Name}! Ignoring.`)
			continue
		end
		
		if type(defaultValue) ~= type(instanceValue) then
			warn(`{prefabInstance.Parent.Name}.{prefabInstance.Name} : Attribute {settingName} is expected to be of type {type(defaultValue)} for instances of prefab {prefab.Name}, but got {type(instanceValue)}! Ignoring.`)
			continue
		end
		
		instanceSettings[settingName] = instanceValue
	end
	
	prefabSystem.DeepAttributeInterpolate(prefab, instanceData, instanceSettings)
	
	for _, prefabElement in pairs(instanceData:GetDescendants()) do
		if prefabElement == instanceBase then continue end
		if not prefabElement:IsA("BasePart") then continue end
		local baseToElement = instanceBase.CFrame:ToObjectSpace(prefabElement.CFrame)
		prefabElement.CFrame = prefabInstance.CFrame:ToWorldSpace(baseToElement)
	end
	
	prefabSystem.UnpackPrefabTargets(mission, instanceData)
end

local ATTRIBUTE_SUBSTITUTION_PATTERN = "%$%(([_%w]+)%)"
function prefabSystem.DeepAttributeInterpolate(prefab: Folder, root: Instance, state: { [string] : any })
	for attrName, attrValue in pairs(root:GetAttributes()) do
		if type(attrValue) ~= "string" then continue end
		local success, interpolatedAttrValue = prefabSystem.InterpolateValue(prefab, root, attrValue, state)
		if not success then continue end
		root:SetAttribute(attrName, interpolatedAttrValue)
	end
	
	local success, interpolatedName = prefabSystem.InterpolateValue(prefab, root, root.Name, state)
	if success and type(interpolatedName) == "string" then
		root.Name = interpolatedName
	elseif success then
		warn(`Attribute Interpolation : {root.Parent.Name}.{root.Name} : Name interpolation resolved to a non-string value!`)
	end
	
	for _, child in ipairs(root:GetChildren()) do
		prefabSystem.DeepAttributeInterpolate(prefab, child, state)
	end
end

function prefabSystem.InterpolateValue(prefab: Folder, element: Instance, value: string, state: { [string] : any }) : any
	local fullReplaceName = string.match(value, `^{ATTRIBUTE_SUBSTITUTION_PATTERN}$`)
	if fullReplaceName ~= nil then
		local fullReplaceValue = state[fullReplaceName]
		if fullReplaceValue == nil then
			warn(`Attribute Interpolation : {element.Parent.Name}.{element.Name} : Full-Substitute variable \"{fullReplaceName}\" not found!`)
			return false, nil
		end
		return true, fullReplaceValue
	end
	
	return true, string.gsub(value, ATTRIBUTE_SUBSTITUTION_PATTERN, function(subName)
		local subValue = state[subName]
		if subValue == nil then
			warn(`Attribute Interpolation : {element.Parent.Name}.{element.Name} : Partial-Substitute variable \"{subName}\" not found!`)
		end
		return tostring(subValue) or `ATTRSUB_FAIL_{subName}_NOTFOUND`
	end)
end

apiConsumer.DoAPILoop(API_ID, prefabSystem.OnAPILoaded, prefabSystem.OnAPIUnloaded)