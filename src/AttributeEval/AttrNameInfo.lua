local glut = require("../Lib/GLUt")
local multiPatterns = require("../Lib/MultiPatterns")

local warnLogger = require("../Lib/Slogger").init{
    postInit = table.freeze,
    logFunc = warn
}

local warn = warnLogger.new("PrefabSystem", "AttrNameInfo")

local AttrNameInfo = {}
AttrNameInfo.Patterns = {}

local priorityPatterns = {
    NUMERIC = "^(%d+)%.",
    HIGHP_DEPRECATED = "^highp%.",
    LOWP_DEPRECATED  = "^lowp."
}
AttrNameInfo.Patterns.Priority = priorityPatterns

local PRIORITY_RANGE_MAJOR = 128
local PRIORITY_RANGE_MINOR = 1 / PRIORITY_RANGE_MAJOR
local function newPriorityLevel(major)
    return function(minor)
        return (major * PRIORITY_RANGE_MAJOR) + (minor * PRIORITY_RANGE_MINOR)
    end
end

local DEBUG_PRIORITY_LEVEL   = newPriorityLevel(1) -- Priority of debug type attributes
local EXEC_PRIORITY_LEVEL    = newPriorityLevel(2) -- Priority of exec type attributes
local ORDERED_PRIORITY_LEVEL = newPriorityLevel(3) -- Priority of attributes with an explicit ordering
local STD_PRIORITY_LEVEL     = newPriorityLevel(4) -- Priority of unordered attributes
local THIS_PRIORITY_LEVEL    = newPriorityLevel(5) -- Priority of this type attributes

local function newScope(tbl: { Name: string, PriorityLevel: (number) -> number, PriorityPattern: string?, ScopePattern: string?, TargetPattern: string?, IsSpecial: boolean? })
    tbl.PriorityPattern = glut.default(tbl.PriorityPattern, priorityPatterns.NUMERIC)
    tbl.ScopePattern    = glut.default(
                                       tbl.ScopePattern,
                                       multiPatterns.concat(`^{tbl.Name}%.`, `%.{tbl.Name}%.`)
                                      )
    tbl.TargetPattern   = glut.default(tbl.TargetPattern  , `[^%.]+$`)
    tbl.IsSpecial       = glut.default(tbl.IsSpecial, true)
    return tbl
end

local SCOPES = {
    THIS          = newScope{
                              Name = "this",
                              PriorityLevel = THIS_PRIORITY_LEVEL
                            },
    EXEC          = newScope{
                              Name = "exec",
                              PriorityLevel = EXEC_PRIORITY_LEVEL
                            },
    IGNORE        = newScope{ Name = "ignore" },
    PEVAL         = newScope{ Name = "peval" },
    NOIMP         = newScope{ Name = "noimp" },
    IMPONLY       = newScope{ Name = "imponly" },
    DEBUG         = newScope{ 
                              Name = "debug",
                              PriorityLevel = DEBUG_PRIORITY_LEVEL
                            },
    ["@STANDARD"] = newScope{
                              Name          = "@standard",
                              ScopePattern  = multiPatterns.concat("^%d+%.[^%.]+$", "^[^%.]+$"),
                              IsSpecial     = false
                            },
}
AttrNameInfo.Scopes = SCOPES

function AttrNameInfo.GetTarget(attrName, attrScope)
    attrScope = attrScope or AttrNameInfo.GetScope(attrName)
    return string.match(attrName, SCOPES[attrScope].TargetPattern)
end

function AttrNameInfo.GetPriority(attrName, attrScope)
    attrScope = attrScope or AttrNameInfo.GetScope(attrName)

    local warn = warn.specialize("GetPriority", attrName)

    local defaultPriorityLevel = SCOPES[attrScope].PriorityLevel or STD_PRIORITY_LEVEL

    local pattern = SCOPES[attrScope].PriorityPattern
    if pattern == false then
        return defaultPriorityLevel(0)
    end

    local numP = string.match(attrName, pattern)
    if numP then
        return ORDERED_PRIORITY_LEVEL(tonumber(numP))
    end

    local highP = string.match(attrName, priorityPatterns.HIGHP_DEPRECATED)
    local lowP  = string.match(attrName, priorityPatterns.LOWP_DEPRECATED)
    if not highP and not lowP then
        return defaultPriorityLevel(1)
    end

    warn("Using deprecated highp/lowp syntax, replace with numeric priority to silence")
    if highP then
        return defaultPriorityLevel(0)
    elseif lowP then
        return defaultPriorityLevel(2)
    end
end

local function isMatch(s, m)
    local mType = type(m)
    local mRes
    if mType == "table" then
        mRes = m:match(s)
    elseif mType == "string" then
        mRes = s:match(m)
    else
        error("ScopePattern of invalid type")
    end
    return mRes ~= nil, mRes
end

local DEBUG_TYPES = {}
function AttrNameInfo.GetScope(attrName)
    local warn = warn.specialize("GetScope", attrName)

    local lastResort = nil

    local scope = nil
    for scopeName, scopeInfo in pairs(SCOPES) do
        local doDebug = table.find(DEBUG_TYPES, scopeName)
        
        if scopeInfo.ScopePattern == false then continue end
        if (not scopeInfo.IsSpecial) then lastResort = scopeName continue end

        local isMatch, matchRes = isMatch(attrName, scopeInfo.ScopePattern)
        if doDebug then
            print(`[ScopeClassify/{scopeName}] {attrName} - {isMatch} - {matchRes}`)
        end
        
        if isMatch and scope ~= nil then
            warn("More than one attribute scope provided")
        elseif isMatch then
            scope = scopeName
        end
    end

    if scope then return scope end

    for scopeName, scopeInfo in pairs(SCOPES) do
        if scopeInfo.ScopePattern == false then continue end
        if scopeInfo.IsSpecial then continue end

        local isMatch = isMatch(attrName, scopeInfo.ScopePattern)
        if isMatch then
            scope = scopeName
            break
        end
    end

    if scope == nil and lastResort == nil then
        warn(`Attribute {attrName} does not belong to any attribute type! Will default to @STANDARD`)
        return SCOPES["@STANDARD"].Name
    end

    return scope or lastResort
end


local attrInfo = {}
function attrInfo:IsScope(scope)
    return self.Scope:lower() == scope:lower()
end

function attrInfo:NameNoPriority()
    local raw = self.Raw
    for _, priorityPattern in priorityPatterns do
        raw = string.gsub(raw, priorityPattern, "")
    end
    return raw
end

attrInfo.__index = attrInfo
attrInfo.__tostring = function(self)
    return `{self.Raw} -> \{ Target: {self.Target}, Priority: {self.Priority}, Scope: {self.Scope} }`
end

function AttrNameInfo.GetInfo(attrName)
    local scope = AttrNameInfo.GetScope(attrName)
    local scopeInfo = SCOPES[scope]
    return setmetatable({
        Target    = AttrNameInfo.GetTarget(attrName, scope),
        Priority  = AttrNameInfo.GetPriority(attrName, scope),
        Scope     = scope,
        ScopeInfo = scopeInfo,
        Raw       = attrName
    }, attrInfo)
end

return AttrNameInfo