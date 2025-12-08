local warnLogger = require(script.Parent.Slogger).init{
	postInit = table.freeze,
	logFunc = warn
}

local warn = warnLogger.new("PrefabSystem")

local glut = require(script.Parent.GLUt)
glut.configure{ warn = warn }

local apiConsumer = require(script.Parent.APIConsumer)

local luaExpr = require(script.Parent.LuaExpr)
local luaExprFuncs = require(script.Parent.LuaExprFuncs)
local shebangFuncs = require(script.Parent.ShebangFuncs)
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
		api.RemoveHook(token)
	end
	for i, extName, extAuth, extDereg, extToken in extHookIter(prefabSystemState.ExtHooks) do
		local ext = api.GetAPIExtension(extName, extAuth)
		if ext == nil then continue end
		if ext[extDereg] == nil then continue end
		ext[extDereg](extToken)
	end
	for _, extToken in ipairs(prefabSystemState.ApiExtensions) do
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
			prefabSystem.DeepAttributeEvaluator(
				prefab,
				prefabTargetGroup,
				prefabSystem.InterpolateValue,
				{ Instance = prefabStatic, Static = prefabStatic, Global = globalState }
			)
		end)
		
	end
	
	-- Prevent these from being exported and taking up mission space
	prefabFolder:Destroy()
	prefabInstanceFolder:Destroy()
end

function prefabSystem.UnpackPrefab(mission: Folder, prefab: Folder, scope: string, preUnpack)
	preUnpack = glut.default(preUnpack, function() end)
	for _, prefabTargetGroup in ipairs(prefab:GetChildren()) do
		if not prefabTargetGroup:IsA("Folder") then
			warn(`PrefabTargetGroup {prefabTargetGroup.Name} is invalid - expected Folder, got {prefabTargetGroup.ClassName}. Skipping.`)
			continue
		end
		
		if not prefabTargetGroup.Name:lower():find(`^{scope:lower()}`) then continue end
		local modifiedTargets = preUnpack(mission, prefabTargetGroup) or {prefabTargetGroup}
		for _, modifiedTarget in ipairs(modifiedTargets) do
			prefabSystem.UnpackPrefabTargets(mission, modifiedTarget)
		end
	end
end

function prefabSystem.UnpackPrefabTargets(mission: Folder, targetGroup: Folder)
	local warn = warnLogger.new("UnpackPrefabTarget", "Prefab Target Invalid")
	
	for _, prefabTarget in ipairs(targetGroup:GetChildren()) do
		if prefabTarget.Name == "InstanceBase" then continue end
		
		if prefabTarget:IsA("ValueBase") then
			continue
		end
		
		if not prefabTarget:IsA("Folder") then
			warn(`Expected Folder, got {prefabTarget.ClassName}`, "Target will be ignored")
			continue
		end

		local missionPrefabTarget = mission:FindFirstChild(prefabTarget.Name) 
		if missionPrefabTarget == nil then warn(`Destination {prefabTarget.Name} not present`, "Create it if needed") continue end
		for _, prefabTargetItem in ipairs(prefabTarget:GetChildren()) do
			local itemIsFolder = prefabTargetItem:IsA("Folder")
			local missionFolder = missionPrefabTarget:FindFirstChild(prefabTargetItem.Name)
			if itemIsFolder and missionFolder ~= nil then
				for _, child in ipairs(prefabTargetItem:GetChildren()) do
					child:Clone().Parent = missionFolder
				end
				continue
			end
			prefabTargetItem:Clone().Parent = missionPrefabTarget 
		end
	end
end

function prefabSystem.InstantiatePrefab(mission: Folder, prefab: Folder, prefabInstance: BasePart, staticState, globalState)
	local warn = warn.specialize("InstantiatePrefab", `Prefab {prefab.Name}`)
	
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
	
	local instanceSettings = {}
	for k, v in pairs(instanceBase:GetAttributes()) do
		if glut.str_has_match(k, "^imponly%.") then continue end
		instanceSettings[k:gsub("^noimp%.", "")] = v
	end
	
	for settingName, instanceValue in pairs(prefabInstance:GetAttributes()) do
		local warn = warn.specialize(`Ignoring invalid attribute {settingName}`)
		
		if settingName == "PrefabName" then continue end
		
		settingName = string.gsub(settingName, "^noimp%.", "")
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
	
	local cfrSet = prefabSystem.DeepAttributeEvaluator(
		prefab,
		instanceData,
		prefabSystem.InterpolateValue,
		{ Instance = instanceSettings, Static = staticState, Global = globalState },
		{ "this.CFrame" }
	)["this.CFrame"] or {}
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
	
	prefabSystem.UnpackPrefabTargets(mission, instanceData)
end

function prefabSystem.GetSortedAttributeList(instance)
	local instanceAttrs = instance:GetAttributes()
	local instanceAttrNames = {}
	for k, _ in pairs(instanceAttrs) do table.insert(instanceAttrNames, k) end
	
	table.sort(instanceAttrNames, function(a, b)
		local aIsHighP = string.match(a, "^highp%.") ~= nil
		local bIsHighP = string.match(b, "^highp%.") ~= nil
		local aIsLowP = string.match(a, "^lowp%.") ~= nil
		local bIsLowP = string.match(b, "^lowp%.") ~= nil
		
		local aNumericP = string.match(a, "^(%d+)%.")
		local bNumericP = string.match(b, "^(%d+)%.")
		local aIsNumericP = aNumericP ~= nil
		local bIsNumericP = bNumericP ~= nil
		
		if aIsNumericP and bIsNumericP then
			return tonumber(aNumericP) < tonumber(bNumericP)
		elseif aIsNumericP then
			return true
		elseif bIsNumericP then
			return false
		end
		
		if aIsHighP and not bIsHighP then
			return true
		elseif bIsHighP and not aIsHighP then
			return false
		elseif aIsLowP and not bIsLowP then
			return false
		elseif bIsLowP and not aIsLowP then
			return true
		else
			return a < b
		end
	end)
	
	return instanceAttrNames
end

function prefabSystem.IsProgrammable(inst)
	for n, _ in pairs(inst:GetAttributes()) do
		if glut.str_has_match(n, "ProgrammableDone$") then return true end
	end
	return false
end

function prefabSystem.DeepAttributeEvaluator(prefab: Folder, root: Instance, evaluator, evalData, attrCapture, programmableRecurse)
	attrCapture = glut.default(attrCapture, {})
	programmableRecurse = glut.default(programmableRecurse, false)
	local warn = warnLogger.new("Attribute Evaluation", `{root.Parent}.{root}`)
	
	if prefabSystem.IsProgrammable(root) and not programmableRecurse then
		local evalLimit = root:GetAttribute("ignore.ProgrammableEvalLimit")
		if type(evalLimit) ~= "number" then evalLimit = 2000 end
		
		local attrCapture = glut.tbl_clone(attrCapture)
		local allCaptured = {}
		if not table.find(attrCapture, "ignore.ProgrammableDone") then table.insert(attrCapture, "ignore.ProgrammableDone") end
		local i = 0
		repeat
			i = i + 1
			local rootClone = root:Clone()
			rootClone.Parent = root.Parent
			local setQuery = prefabSystem.DeepAttributeEvaluator(
				prefab,
				rootClone,
				evaluator,
				evalData,
				attrCapture,
				true
			)
			local doneSet = setQuery["ignore.ProgrammableDone"][rootClone]
			if doneSet then rootClone:Destroy() end
			allCaptured = glut.tbl_merge(allCaptured, setQuery)
		until doneSet or i >= evalLimit
		if i >= evalLimit then
			warn(
				`Error evaluating programmable instance - did not finish after {evalLimit} evaluations`,
				"If intentional - this limit may be altered by setting \"ignore.ProgrammableEvalLimit\" to a number of your choosing"
			)
		end
		root:Destroy()
		return allCaptured
	end
	
	local setQuery = {}
	for _, attrName in ipairs(prefabSystem.GetSortedAttributeList(root)) do
		local attrValue = root:GetAttribute(attrName)
		if type(attrValue) ~= "string" then continue end
		local success, interpolatedAttrValue = evaluator(prefab, root, attrName, attrValue, evalData)
		if not success then
			warn(interpolatedAttrValue, "Attribute will be ignored")
			root:SetAttribute(attrName, nil)
			continue
		end
		
		local pName = attrName:match("^highp%.(.+)$") or attrName:match("^lowp%.(.+)$") or attrName:match("^%d+%.(.+)$")
		if pName ~= nil then
			root:SetAttribute(attrName, nil)
			attrName = pName
		end
		
		for _, querying in ipairs(attrCapture) do
			if attrName == querying then
				setQuery[querying] = setQuery[querying] or {}
				setQuery[querying][root] = interpolatedAttrValue
			end
		end
		
		local ignoreName = attrName:match("^ignore%.([_%w]+)$")
		if ignoreName ~= nil then
			root:SetAttribute(attrName, nil)
			continue
		end
		
		local propName = attrName:match("^this%.([_%w]+)$")
		if propName ~= nil then
			local success, reason = pcall(function()
				if typeof(root[propName]) == "EnumItem" then
					interpolatedAttrValue = root[propName].EnumType:FromName(interpolatedAttrValue)
				end
				root[propName] = interpolatedAttrValue
			end)
			if not success then
				warn(`Failed to set Property {propName}`, reason) 
			end
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
		local childSet = prefabSystem.DeepAttributeEvaluator(prefab, child, evaluator, evalData, attrCapture, programmableRecurse)
		for attrName, hit in pairs(childSet) do
			setQuery[attrName] = setQuery[attrName] or {}
			local subTbl = setQuery[attrName]
			for inst, val in pairs(hit) do
				subTbl[inst] = val
			end
		end
	end
	
	return setQuery
end

function prefabSystem.InterpolateValue(prefab: Folder, element: Instance, name: string, value: string, state: { [string] : any }) : any
	local exprName = `{element.Parent}.{element}:{name}`
	local warn = warnLogger.new("Attribute Interpolation", exprName)
	
	local instState = state.Instance
	local staticState = state.Static
	local globalState = state.Global
	
	local shebangContents = string.match(value, "^#!/lua%s+(.*)$")
	if shebangContents ~= nil then
		local warn = warn.specialize("ShebangScriptExec")
		local success, count, args = glut.str_runlua(
			shebangContents,
			shebangFuncs.CreateShebangFenv(element, instState, staticState, globalState),
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
	
	local success, evalResult = luaExpr.Eval(
		value,
		luaExprFuncs.CreateExprFenv(element, instState, staticState),
		exprRules,
		exprName,
		false
	)
	
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
	if not isSfunc then return false, nil end

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