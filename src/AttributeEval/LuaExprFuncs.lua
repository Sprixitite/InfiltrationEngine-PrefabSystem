local glut = require("../Lib/GLUt")
local debbie = require("../Lib/DebbieDebug")
local instanceMan = require("../InstanceManager")

local luaExprFuncs = {}

local function stateGroupErr(operation, groupPath)
    error("Attempted to " .. operation .. " State Group " .. groupPath .. " but encountered non-table element in path!")
end

local function stateValueErr(operation, valuePath)
    error("Attempted to " .. operation .. " State Value" .. valuePath .. "but path is invalid!")
end

local function returnArgs(...) return ... end

local function ExprFunc(fname, f, ...)
    local tblCallable = glut.fun_tblcallable(fname, returnArgs, ...)
    return function(exprCtx, t)
        return f(exprCtx, tblCallable(t))
    end
end

local function ExprFuncOverload(fname, f, foverloading, ...)
    local tblCallable = glut.fun_tblcallable(fname, returnArgs, ...)
    return function(exprCtx, t)
        local overloaded = function() return foverloading(exprCtx, t) end
        return f(exprCtx, overloaded, tblCallable(t))
    end
end

local function legacyArgUnpack(exprCtx)
    local inst = exprCtx.PrefabElement
    local attr = exprCtx.AttrName
    local instState = exprCtx.InstanceState
    local staticState = exprCtx.StaticState
    return inst, attr, instState, staticState
end

local function getStateGroup(state, groupPath, quietFail, createIfNil)
    createIfNil = glut.default(createIfNil, false)
    
    local groupKeys = glut.str_split(groupPath, '.')
    local success, groupTbl = glut.tbl_deepget(state, createIfNil, unpack(groupKeys))
    if not success and not quietFail then stateGroupErr("get", groupPath) end
    if not success and quietFail then return nil end
    return groupTbl, groupKeys
end

local function getStateValue(state, valuePath, quietFail, createIfNil)
    createIfNil = glut.default(createIfNil, false)
    
    local destPath = glut.str_split(valuePath, '.')
    local destKey = table.remove(destPath)
    local success, groupTbl = glut.tbl_deepget(state, createIfNil, unpack(destPath))
    
    if not success and not quietFail then stateValueErr("get", valuePath) end
    if not success and quietFail then return nil end
    
    return groupTbl[destKey]
end

local function setStateValue(state, valuePath, value)
    local destPath = glut.str_split(valuePath, '.')
    local destKey = table.remove(destPath)
    
    local success, groupTbl = glut.tbl_deepget(state, unpack(destPath))
    if not success then stateValueErr("set", valuePath) end
    
    groupTbl[destKey] = value
end

local _methodTokens = {}
local function storeMethodToken(methodName, obj, value)
    _methodTokens[methodName] = _methodTokens[methodName] or glut.tbl_weak(true, false)
    _methodTokens[methodName][obj] = value
end

local function getMethodToken(methodName, obj)
    if _methodTokens[methodName] == nil then return nil end
    return _methodTokens[methodName][obj]
end

luaExprFuncs.once = ExprFunc(
    "once",
    function(exprCtx, ret, condition)
        local attr = exprCtx.AttrName
        local inst = exprCtx.PrefabElement
        if condition and not getMethodToken("once", inst) then
            storeMethodToken("once", inst, true)
            return ret
        end
        return false
    end,
    { 1, "ret", false, false, default=false },
    { 2, "condition", "boolean", true, default=true }
)

luaExprFuncs.group_for = ExprFunc(
    "group_for",
    function(exprCtx, source, sink)
        local inst = exprCtx.PrefabElement
        local state = exprCtx.InstanceState
        
        local key = getMethodToken("group_for", state)
        local staticGroup = getStateGroup(state, source)
        local key, value = next(staticGroup, key)
        storeMethodToken("group_for", state, key)
        
        setStateValue(state, sink, value)
        return key == nil
    end,
    { 1, "source", "string", false, vital=true },
    { 2, "sink", "string", false, vital=true }
)

luaExprFuncs.runScript = ExprFunc(
    "runScript",
    function(exprCtx, scriptPath)
        local prefabData = exprCtx.PrefabData
        local prefabFolder = prefabData.MainFolder
        local prefabScopeData = prefabData.ScopeData
        local dataScopeData = prefabScopeData.DATA
        if dataScopeData == nil then
            error("Attempt to run Prefab script but no group of type \"DATA\" found!")
        end
        
        local dataFolder = dataScopeData.ScopeFolder
        local toExec = instanceMan.PathTraverse(dataFolder, scriptPath)
        if toExec == nil then
            error(`Attempt to run Prefab script {scriptPath} but no such script exists under {prefabFolder}.{dataFolder.Parent}.{dataFolder}`)
        end
        
        local attrName = exprCtx.AttrName
        local success, n, args = glut.str_runlua(toExec.Source, exprCtx.ShebangFenv, attrName)
        if not success then error(n) end
        
        return args[1]
    end,
    { 1, "scriptPath", "string", false, vital=true }
)

luaExprFuncs.thisProp = ExprFunc(
    "thisProp",
    function(exprCtx, propName)
        local inst = exprCtx.PrefabElement
        return inst[propName]
    end,
    { 1, "propName", "string", false, vital=true }
)

luaExprFuncs.thisAttr = ExprFunc(
    "thisAttr",
    function(exprCtx, attrName)
        local inst = exprCtx.PrefabElement
        return inst:GetAttribute(attrName)
    end,
    { 1, "attrName", "string", false, vital=true }
)

luaExprFuncs.tostring = ExprFunc(
    "tostring",
    function(exprCtx, value)
        return tostring(value)
    end,
    { 1, "value", false, false, vital=true }
)

luaExprFuncs.tonumber = ExprFunc(
    "tonumber",
    function(exprCtx, str)
        return tonumber(str)
    end,
    { 1, "str", "string", false, vital=true }
)

luaExprFuncs.strsan = ExprFunc(
    "strsan",
    function(exprCtx, str)
        -- Sanitize a string for use as a global variable name
        if string.sub(str, 1, 1):match("^%d") then
            str = '_' .. str
        end
        return str:gsub("[^%w]", "_")
    end,
    { 1, "str", "string", false, vital=true }
)

luaExprFuncs.stror = ExprFunc(
    "stror",
    function(exprCtx, condition, str1, str2)
        -- Selects one of two strings depending on the state of a condition variable
        -- Outputs str1 when condition == false
        -- Otherwise outputs str2
        return condition and str2 or str1
    end,
    { 1, "condition", "boolean", false, vital=true },
    { 2, "str1", "string", false, vital=true },
    { 3, "str2", "string", false, vital=true }
)

luaExprFuncs.setAttributes = ExprFunc(
    "setAttributes",
    function(exprCtx, attrs)
        local inst = exprCtx.PrefabElement
        for k, v in pairs(attrs) do
            inst:SetAttribute(k, v)
        end
        return true
    end,
    { 1, "attributes", "table", false, vital=true }
)

luaExprFuncs.setStateValue = ExprFunc(
    "setStateValues",
    function(exprCtx, name, value, override)
        local state = exprCtx.InstanceState
        debbie.print(state)
        debbie.print(name, value, override)
        
        if state[name] ~= nil and not override then
            error("Attempt to set already-existing StateValue \"" .. name .. "\"!")
        end
        state[name] = value
        return true
    end,
    { 1, "name", "string", false, vital=true },
    { 2, "value", false, false, vital=true },
    { 3, "override", "boolean", true, default=false }
)

luaExprFuncs.stringSplit = ExprFunc(
    "stringSplit",
    function(exprCtx, value, separator)
        return glut.str_split(value, separator)
    end,
    { 1, "value", "string", false, vital=true },
    { 2, "separator", "string", false, vital=true }
)

luaExprFuncs.unpackToState = ExprFunc(
    "unpackToState",
    function(exprCtx, unpacking, ...)
        local state = exprCtx.InstanceState
        
        local locTbl = { ... }
        for i, v in ipairs(unpacking) do
            local locPath = locTbl[i]
            if locPath == nil then break end
            local unpackPath = glut.str_split(locPath, '.')
            local unpackLast = table.remove(unpackPath)
            setStateValue(state, locPath, v)
        end
        return true
    end,
    -- Ugly hack
    -- You get 16 unpack locations, use em wisely
    {  1, "unpacking", "table", false, vital=true },
    {  2, "state#1", "string", false, vital=true },
    {  3, "state#2", "string?", false, default=nil },
    {  4, "state#3", "string?", false, default=nil },
    {  5, "state#4", "string?", false, default=nil },
    {  6, "state#5", "string?", false, default=nil },
    {  7, "state#6", "string?", false, default=nil },
    {  8, "state#7", "string?", false, default=nil },
    {  9, "state#8", "string?", false, default=nil },
    { 10, "state#9", "string?", false, default=nil },
    { 11, "state#10", "string?", false, default=nil },
    { 12, "state#11", "string?", false, default=nil },
    { 13, "state#12", "string?", false, default=nil },
    { 14, "state#13", "string?", false, default=nil },
    { 15, "state#14", "string?", false, default=nil },
    { 16, "state#15", "string?", false, default=nil },
    { 17, "state#16", "string?", false, default=nil }
)

luaExprFuncs.staticGroupToLocalArray = ExprFunc(
    "staticGroupToLocalArray",
    function(exprCtx, groupName, elementPrefix, stateScriptAccess, genAccessString)
        local inst = exprCtx.PrefabElement
        local state = exprCtx.InstanceState
        
        local groupTbl = getStateGroup(state, groupName, false)
        inst:SetAttribute(elementPrefix .. "Count", #groupTbl)
        local statescriptAccessor = "INIT #StateScriptAccessLocalArrayTemp 0"
        for i, v in ipairs(groupTbl) do
            statescriptAccessor = statescriptAccessor .. "\n SET #StateScriptAccessLocalArrayTemp #" .. elementPrefix .. tostring(i) 
            inst:SetAttribute(elementPrefix .. tostring(i), v)
        end
        if stateScriptAccess ~= "NO!" then
            inst:SetAttribute(stateScriptAccess, statescriptAccessor)
        end
        return true
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "elementPrefix", "string", false, vital=true },
    { 3, "stateScriptAccess", "string", true, default="NO!" }
)

luaExprFuncs.importStaticGroup = ExprFunc(
    "importStaticGroup",
    function(exprCtx, groupName, importLocation, allowDuplicates, quietFail)
        local inst = exprCtx.PrefabElement
        local state = exprCtx.InstanceState
        local staticState = exprCtx.StaticState
        
        local alreadyImported = getMethodToken("importStaticGroup", state)
        if alreadyImported then return end
        
        local groupTbl = getStateGroup(staticState, groupName, quietFail, false)
        if groupTbl == nil then
            setStateValue(state, importLocation, {})
            return
        end
        groupTbl = glut.tbl_clone(groupTbl, false)
        
        if not allowDuplicates then
            local noDupes = {}
            
            for k, v in pairs(groupTbl) do
                if table.find(noDupes, v) ~= nil then continue end
                if type(k) == "number" then table.insert(noDupes, v) continue end
                
                noDupes[k] = v
            end
            
            groupTbl = noDupes
        end
        
        storeMethodToken("importStaticGroup", state, true)
        setStateValue(state, importLocation, groupTbl)
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "importLocation", "string", false, vital=true },
    { 3, "allowDuplicates", "boolean", true, default=true },
    { 4, "quietFail", "boolean", true, default=false }
)

luaExprFuncs.staticGroupExport = ExprFunc(
    "staticGroupExport",
    function(exprCtx, groupName, exportValue, allowDuplicates)
        -- Exports a variable as a member of a staticState group, creating the group if it does not exist
        local staticState = exprCtx.StaticState
        
        local group = getStateGroup(staticState, groupName, false, true)
        
        local isDupe = table.find(group, exportValue)
        if not allowDuplicates and isDupe then return true end
        
        table.insert(group, exportValue)
        return isDupe
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "exportValue", false, false, vital=true },
    { 3, "allowDuplicates", "boolean", true, default=false }
)

luaExprFuncs.staticGroupCombine = ExprFunc(
    "staticGroupCombine",
    function(
        exprCtx,
        groupName,
        combineOp,
        prefix,
        suffix,
        field,
        itemPrefix,
        itemSuffix,
        autoBrackets
    )
        -- Concatenates the string representation of all members of a staticState group, using the specified operator inbetween all elements
        local staticState = exprCtx.StaticState
        
        local groupTbl = getStateGroup(staticState, groupName, false)
        
        local openBracket = autoBrackets and "(" or ""
        local closeBracket = autoBrackets and ")" or ""
        local str = prefix .. openBracket
        for i, v in ipairs(groupTbl) do
            if i ~= 1 then str = str .. combineOp end
            local vStr = (field == nil) and tostring(v) or tostring(v[field])
            str = str .. itemPrefix .. vStr .. itemSuffix
        end
        str = str .. closeBracket .. suffix
        return str
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "combineOp", "string", false, vital=true },
    { 3, "prefix", "string", true, default="" },
    { 4, "suffix", "string", true, default="" },
    { 5, "field", false, true, default=nil },
    { 6, "itemPrefix", "string", true, default="" },
    { 7, "itemSuffix", "string", true, default="" },
    { 8, "autoBrackets", "boolean", true, default=true }
)

luaExprFuncs.staticGroupEmpty = ExprFunc(
    "staticGroupEmpty",
    function(exprCtx, groupName, quietFail)
        -- Returns true if the StaticStateGroup at the given path is empty
        return luaExprFuncs.staticGroupSize(exprCtx, { groupName, quietFail=quietFail }) == 0
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "quietFail", "boolean", true, default=false }
) 

luaExprFuncs.staticGroupSize = ExprFunc( 
    "staticGroupSize",
    function(exprCtx, groupName, asString, quietFail)
        -- Returns the size of the StaticStateGroup at the given path - optionally as a string
        debbie.print("staticGroupSize", groupName)
        local staticState = exprCtx.StaticState
        local group = getStateGroup(staticState, groupName, quietFail)
        debbie.print(group)
        
        local size
        if group == nil then
            size = 0
        else
            size = #group
        end
        
        return (asString and tostring(size)) or size
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "asString", "boolean", true, default=false },
    { 3, "quietFail", "boolean", true, default=false }
)

luaExprFuncs.moveFirstStaticElement = ExprFunc(
    "moveFirstStaticElement",
    function(
        exprCtx,
        groupPath,
        destPath,
        pairItem,
        quietFail
    )
        -- Removes the first element of the StaticStateGroup at the given path, and places it
        local staticState = exprCtx.StaticState
        
        if pairItem ~= 'k' and pairItem ~= 'v' then error("pairItem must be nil|\"k\"|\"v\"!") end
        
        local groupTbl, indexKeys = getStateGroup(staticState, groupPath, quietFail)
        if groupTbl == nil then
            return true
        end
        
        local groupKeys = glut.tbl_getkeys(groupTbl)
        local firstKey = groupKeys[1]
        
        if firstKey == nil and quietFail then
            return true
        elseif firstKey == nil then
            error("StaticGroup " .. groupPath .. " has no elements")
        end
        
        local moving = nil
        if type(firstKey) == "number" then 
            moving = table.remove(groupTbl, firstKey)
        else 
            moving = groupTbl[firstKey]
            groupTbl[firstKey] = nil 
        end
        
        if pairItem == 'k' then moving = firstKey end
        setStateValue(staticState, destPath, moving)
        return true
    end,
    { 1, "groupName", "string", false, vital=true },
    { 2, "destinationName", "string", false, vital=true },
    { 3, "pairItem", "string", true, default="v" },
    { 4, "quietFail", "boolean", true, default=false }
)

luaExprFuncs.getStaticVariable = ExprFunc( 
    "getStaticVariable",
    function(exprCtx, valuePath, quietFail)
        local staticState = exprCtx.StaticState
        return getStateValue(staticState, valuePath, quietFail)
    end,
    { 1, "valuePath", "string", false, vital=true },
    { 2, "quietFail", "boolean", true, default=false }
)

luaExprFuncs.fallbackIfUnset = ExprFunc(
    "fallbackIfUnset",
    function(exprCtx, maybeUnset, fallback)
        -- Returns the second argument if the first contains the substring "UNSET" (case-sensitive)
        if maybeUnset == nil then return fallback end
        if type(maybeUnset) ~= "string" then return maybeUnset end
        if glut.str_has_match(maybeUnset, "UNSET") then return fallback end
        if glut.str_has_match(maybeUnset, "DEFAULT") then return fallback end
        return maybeUnset
    end,
    { 1, "maybeUnset", false, false, default=nil },
    { 2, "fallback", false, false, default=nil }
)

-- Convenience if you forget the name
luaExprFuncs.fallbackIfDefault = ExprFuncOverload(
    "fallbackIfDefault",
    function(exprCtx, overload, maybeUnset, fallback)
        return overload()
    end,
    { 1, "maybeUnset", false, false, default=nil },
    { 2, "fallback", false, false, default=nil }
)

luaExprFuncs.CreateExprFenv = function(evalContext)
    local fenvMeta = { }
    fenvMeta.__index = function(t, k)
        local result = evalContext.InstanceState[k]
        if result ~= nil then return result end
        if k:match("^Globals?$") then return evalContext.GlobalState end
        if luaExprFuncs[k] == nil then return nil end
        
        return function(t)
            return luaExprFuncs[k](evalContext, t)
        end
    end
    
    return setmetatable({}, fenvMeta)
end

return luaExprFuncs