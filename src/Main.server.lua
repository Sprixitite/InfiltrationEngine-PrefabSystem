local warnLogger = require(script.Parent.Slogger).init{
	postInit = table.freeze,
	logFunc = warn
}

local warn = warnLogger.new("PrefabSystem")

local glut = require(script.Parent.GLUt)
glut.configure{ warn = warn }

local apiConsumer = require(script.Parent.APIConsumer)

local luaExpr = require(script.Parent.LuaExpr)
local exprRules = luaExpr.MakeEvalRules("%$%(", "%)")

type APIReference = apiConsumer.APIReference

local hookName = nil
local API_ID = "InfiltrationEngine-PrefabSystem"

local prefabSystem = {}

local function CheckArgCountRange(fname, expectedMin, expectedMax, ...)
	local argCount = select('#', ...)
	if argCount < expectedMin or argCount > expectedMax then
		local expected = (expectedMin == expectedMax) and expectedMin-2 or `{expectedMin-2}-{expectedMax-2}`
		error(`{fname} expects {expected} arguments, but got {argCount}!`)
	end
end

local function CheckArgCount(fname, expected, ...) CheckArgCountRange(fname, expected, expected, ...) end

local PREFAB_IDS = {}
local ELEMENT_IDS = {}

local function GetId(tbl, inst)
	local existing = tbl[inst]
	if existing ~= nil then return existing end
	
	local max = tbl.Total or 0
	tbl[inst] = max
	tbl.Total = max + 1
	return max
end

local function strKeySub(str, key, value)
	key = tostring(key)
	value = tostring(value)
	return string.gsub(str, "([^{]){" .. key .. "}([^}])", function(d1, d2)
		return d1 .. value .. d2
	end)
end

local SPECIAL_FUNCS = {
	this_prop = function(prefab, element, property, ...)
		CheckArgCount("SpecFunc.this", 3, prefab, element, property, ...)
		return element[property]
	end,
	child_prop = function(prefab, element, child, property, ...)
		CheckArgCount("SpecFunc.child", 4, prefab, element, child, property, ...)
		return element:FindFirstChild(child)[property]
	end,
	this_attr = function(prefab, element, attrname, ...)
		CheckArgCount("SpecFunc.this_attr", 3, prefab, element, attrname, ...)
		return element:GetAttribute(attrname)
	end,
	child_attr = function(prefab, element, child, attrname, ...)
		CheckArgCount("SpecFunc.child_attr", 4, prefab, element, child, attrname, ...)
		return element:FindFirstChild(child):GetAttribute(attrname)
	end,
	str_varsub = function(prefab, element, str, ...)
		CheckArgCount("SpecFunc.str_id_sub", 3, prefab, element, str, ...)
		local temp = ` {str} `
		temp = strKeySub(temp, "pid", GetId(PREFAB_IDS, prefab))
		temp = strKeySub(temp, "eid", GetId(ELEMENT_IDS, element))
		temp = strKeySub(temp, "pname", prefab.Name)
		temp = strKeySub(temp, "ename", element.Name)
		temp = strKeySub(temp, "rand", math.random(0, 9999))
		temp = temp:gsub("{{", "{"):gsub("}}", "}"):sub(2, -2)
		return temp
	end,
}

function prefabSystem.OnAPILoaded(api: APIReference, prefabSystemState)
	hookName = api.GetRegistrantFactory("Sprix", "PrefabSystem")
	prefabSystemState.ExportCallbackToken = api.AddHook("PreSerialize", hookName("PreSerialize"), prefabSystem.OnSerializerExport)
end

function prefabSystem.OnAPIUnloaded(api: APIReference, prefabSystemState)
	if prefabSystemState.ExportCallbackToken then
		-- The unload function passed to DoAPILoop is called
		-- both when the API unloads, and when this plugin unloads
		-- as a result, removing any hooks in the unload function is no longer
		-- a "formality", but rather required
		api.RemoveHook(prefabSystemState.ExportCallbackToken)
	end
end

function prefabSystem.OnSerializerExport(hookState: {any}, invokeState: nil, mission: Folder)
	local warn = warnLogger.new("OnSerializerExport")
	local prefabFolder = mission:FindFirstChild("Prefabs")
	if not prefabFolder then return end
	
	for _, prefab in ipairs(prefabFolder:GetChildren()) do
		if not prefab:IsA("Folder") then
			warn(`Prefab {prefab.Name} is invalid`, `Expected Folder, got {prefab.ClassName}`, "Prefab Will Be Ignored")
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
		local warn = warn.specialize(`PrefabInstance {prefabInstance.Name} is invalid`)
		
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
	local warn = warnLogger.new("UnpackPrefabTarget", "Prefab Target Invalid")
	
	for _, prefabTarget in ipairs(targetGroup:GetChildren()) do
		if prefabTarget.Name == "InstanceBase" then continue end
		
		if not prefabTarget:IsA("Folder") then
			warn(`Expected Folder, got {prefabTarget.ClassName}`, "Target will be ignored")
			continue
		end

		local missionPrefabTarget = mission:FindFirstChild(prefabTarget.Name) 
		if missionPrefabTarget == nil then warn(`Destination {prefabTarget.Name} not present`, "Create it if needed") continue end
		for _, prefabTargetItem in ipairs(prefabTarget:GetChildren()) do
			prefabTargetItem:Clone().Parent = missionPrefabTarget 
		end
	end
end

function prefabSystem.InstantiatePrefab(mission: Folder, prefab: Folder, prefabInstance: BasePart)
	local warn = warnLogger.new("InstantiatePrefab", `Prefab {prefab.Name}`)
	
	local instanceTargetGroup = prefab:FindFirstChild("Instance") or prefab:FindFirstChild("instance")
	if not instanceTargetGroup then
		warn("Prefab may not be instantiated!")
		return
	end
	
	local instanceData = instanceTargetGroup:Clone()
	local instanceBase = instanceData:FindFirstChild("InstanceBase")
	if not instanceBase then
		warn("Instance folder found but no InstanceBase part present!")
		return
	end
	
	if not instanceBase:IsA("Part") then
		warn("InstanceBase found but not a part!")
		return
	end
	
	local sFuncStructure = prefabSystem.CollectSpecFuncAttrs(prefab, instanceBase, SPECIAL_FUNCS)
	prefabSystem.EvaluateSpecFuncs(prefab, prefabInstance, SPECIAL_FUNCS, sFuncStructure)
	
	local instanceSettings = instanceBase:GetAttributes()
	for settingName, instanceValue in pairs(prefabInstance:GetAttributes()) do
		local warn = warn.specialize(`Ignoring invalid attribute {settingName}`)
		
		if settingName == "PrefabName" then continue end
		
		local defaultValue = instanceSettings[settingName] 
		
		if type(defaultValue) == "string" then
			local isSFunc = prefabSystem.StrIsSpecFunc(defaultValue)
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
	
	local cfrSet = prefabSystem.DeepAttributeEvaluator(prefab, instanceData, prefabSystem.InterpolateValue, instanceSettings)
	
	for _, prefabElement in pairs(instanceData:GetDescendants()) do
		if prefabElement == instanceBase then continue end
		if not prefabElement:IsA("BasePart") then continue end
		if cfrSet[prefabElement] then continue end
		local baseToElement = instanceBase.CFrame:ToObjectSpace(prefabElement.CFrame)
		prefabElement.CFrame = prefabInstance.CFrame:ToWorldSpace(baseToElement)
	end
	
	prefabSystem.UnpackPrefabTargets(mission, instanceData)
end

function prefabSystem.DeepAttributeEvaluator(prefab: Folder, root: Instance, evaluator, evalData)
	local warn = warnLogger.new("Attribute Evaluation", `{root.Parent}.{root}`)
	
	local whoSetCfr = {}
	for attrName, attrValue in pairs(root:GetAttributes()) do
		if type(attrValue) ~= "string" then continue end
		local success, interpolatedAttrValue = evaluator(prefab, root, attrName, attrValue, evalData)
		if not success then
			warn(interpolatedAttrValue, "Attribute will be ignored")
			root:SetAttribute(attrName, nil)
			continue
		end
		
		local propName = attrName:match("^this%.([_%w]+)$")
		if propName ~= nil then
			local success, reason = pcall(function()
				root[propName] = interpolatedAttrValue
			end)
			if not success then
				warn(`Failed to set Property {propName}`, reason) 
			end
			whoSetCfr[root] = whoSetCfr[root] or propName == "CFrame"
			root:SetAttribute(attrName, nil)
			continue
		end
		
		root:SetAttribute(attrName, interpolatedAttrValue)
	end
	
	local success, interpolatedName = evaluator(prefab, root, `{root}.Name`, root.Name, evalData)
	if success and type(interpolatedName) == "string" then
		root.Name = interpolatedName
	elseif success then
		warn("Name evaluation resolved to a non-string value")
	end
	
	for _, child in ipairs(root:GetChildren()) do
		local childSet = prefabSystem.DeepAttributeEvaluator(prefab, child, evaluator, evalData)
		for inst, set in pairs(childSet) do
			whoSetCfr[inst] = set
		end
	end
	
	return whoSetCfr
end

function prefabSystem.CreateShebangFenv(state)
	local fenvBase = {
		state = state,
		math = math,
		string = string,
		CFrame = CFrame,
		Color3 = Color3,
		Vector2 = Vector2,
		Vector3 = Vector3,
		tostring = tostring,
		tonumber = tonumber,
	}
	
	-- state can't overshadow builtin libraries
	setmetatable(fenvBase, { __index = state })
	return fenvBase
end

function prefabSystem.InterpolateValue(prefab: Folder, element: Instance, name: string, value: string, state: { [string] : any }) : any
	local exprName = `{element.Parent}.{element}:{name}`
	local warn = warnLogger.new("Attribute Interpolation", exprName)
	
	local shebangContents = string.match(value, "^#!/lua%s+(.*)$")
	if shebangContents ~= nil then
		local warn = warn.specialize("ShebangScriptExec")
		local success, count, args = glut.str_runlua(
			shebangContents,
			{
				math = math,
				string = string,
				CFrame = CFrame,
				Color3 = Color3,
				Vector2 = Vector2,
				Vector3 = Vector3,
			},
			exprName
		)
		
		if not success then
			return success, count
		end
		
		if count > 1 then
			warn(`Script execution succeeded, but {count-1} extra values were returned`, "Extra values will be ignored")
		elseif count == 0 then
			warn("Script execution succeeded, but no value was returned", "Attribute will be ignored")
			return false, nil
		end
		return success, args[1]
	end
	
	local success, evalResult = luaExpr.Eval(value, state, exprRules, exprName, false)
	
	if not success then
		if type(evalResult) == "string" then
			warn(evalResult)
		end
		evalResult = nil
	end

	return success, evalResult
end

function prefabSystem.CollectSpecFuncAttrs(prefab, root, sfuncs)
	local selfTbl = { Attributes = {}, Children = {} }
	
	for attrName, attrVal in pairs(root:GetAttributes()) do
		if type(attrVal) ~= "string" then continue end
		local success, sfuncData = prefabSystem.ParseSpecFunc(prefab, root, attrVal, sfuncs)
		if not success then continue end
		
		selfTbl.Attributes[attrName] = sfuncData
	end
	
	for _, baseElem in ipairs(root:GetChildren()) do
		selfTbl.Children[baseElem.Name] = prefabSystem.CollectSpecFuncAttrs(prefab, baseElem, sfuncs)
	end
	
	return selfTbl
end

function prefabSystem.EvaluateSpecFuncs(prefab, root, sfuncs, data)
	local warn = warnLogger.new("EvaluateSpecFuncs")
	
	for childName, childData in pairs(data.Children) do
		local childInstance = root:FindFirstChild(childName)
		if childInstance == nil then warn(`Expected instance {root.Name}.{childName} not found`) continue end
		prefabSystem.EvaluateSpecFuncs(prefab, childInstance, sfuncs, childData)
	end

	for attrName, sFuncData in pairs(data.Attributes) do
		if root:GetAttribute(attrName) ~= nil then continue end
		local success, result = prefabSystem.EvaluateSpecFunc(prefab, root, sFuncData)
		if not success then continue end
		root:SetAttribute(attrName, result)
	end
end

local SPECFUNCS_SUBSTITUTION_PATTERN = "%${(.+)}"
function prefabSystem.StrIsSpecFunc(str)
	local sfuncContent = string.match(str, `^{SPECFUNCS_SUBSTITUTION_PATTERN}$`)
	return sfuncContent ~= nil, sfuncContent
end

function prefabSystem.ParseSpecFunc(prefab, element, sfuncStr, sfuncs)
	local warn = warnLogger.new("SFuncParsing", `{element.Parent.Name}.{element.Name}`, sfuncStr)
	
	local isSfunc, sfuncContent = prefabSystem.StrIsSpecFunc(sfuncStr)
	if isSfunc == nil then return false, nil end

	local sfuncArgs = {}
	local sfuncCurrentArg = ""
	local escaping = false
	local inStr = false
	for c in string.gmatch(sfuncContent, ".") do
		if c:match("^%s$") and not inStr then continue end
		if c == "\\" and not escaping then escaping = true continue end
		if c == "\"" and not escaping and not inStr then inStr = true continue end
		if c == "\"" and not escaping and inStr then inStr = false continue end

		if c == "," and not escaping and not inStr then
			table.insert(sfuncArgs, sfuncCurrentArg)
			sfuncCurrentArg = ""
			continue
		end

		if c == 'n' and escaping then
			sfuncCurrentArg = sfuncCurrentArg .. "\n"
		elseif c == 't' and escaping then
			sfuncCurrentArg = sfuncCurrentArg .. "\t"
		elseif escaping then
			warn(`Received unknown escape \"\\{c}\", ignoring backslash and treating as a normal character`)
			sfuncCurrentArg = sfuncCurrentArg .. c
		else
			sfuncCurrentArg = sfuncCurrentArg .. c
		end

		escaping = false
	end
	table.insert(sfuncArgs, sfuncCurrentArg)

	local sfuncExpectedType = table.remove(sfuncArgs, 1)
	local sfuncName = table.remove(sfuncArgs, 1)
	local sfunc = sfuncs[sfuncName]
	if sfunc == nil then
		warn(`SpecialFunc \"{sfuncName}\" not found!`)
		return false, nil
	end
	
	return true, {
		Func = sfunc,
		Name = sfuncName,
		Args = sfuncArgs,
		Type = sfuncExpectedType,
		Expr = sfuncContent
	}
end

function prefabSystem.EvaluateSpecFunc(prefab, element, sfuncData)
	local warn = warnLogger.new("SFuncExec", sfuncData.Expr, sfuncData.Name)
	
	local success, result = pcall(sfuncData.Func, prefab, element, unpack(sfuncData.Args))
	if success and typeof(result) == sfuncData.Type then return success, result end
	if not success then
		warn(`Execution failed with reason \"{result}\"`)
		return success, result
	end
	
	warn(`Executed successfully but did not return expected type {sfuncData.Type}`)
	return false, nil
end

apiConsumer.DoAPILoop(plugin, API_ID, prefabSystem.OnAPILoaded, prefabSystem.OnAPIUnloaded)