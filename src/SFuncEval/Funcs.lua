local HttpService = game:GetService("HttpService")

local glut = require("../Lib/GLUt")

local SFuncs = {}

local function checkArgCountRange(fname, expectedMin, expectedMax, ...)
    local argCount = select('#', ...)
    if argCount < expectedMin or argCount > expectedMax then
        local expected = (expectedMin == expectedMax) and expectedMin-2 or `{expectedMin-2}-{expectedMax-2}`
        error(`{fname} expects {expected} arguments, but got {argCount}!`)
    end
end

local function checkArgCount(fname, expected, ...) checkArgCountRange(fname, expected, expected, ...) end

local PREFAB_IDS  = glut.tbl_weak(true, false)
local ELEMENT_IDS = glut.tbl_weak(true, false)
local function getId(tbl, inst)
    local existing = tbl[inst]
    if existing ~= nil then return existing end

    local size = glut.tbl_findsize(tbl)
    tbl[inst] = size
    return size
end

local function strKeySub(str, key, value)
    key = tostring(key)
    value = tostring(value)
    return string.gsub(str, "([^{]){" .. key .. "}([^}])", function(d1, d2)
        return d1 .. value .. d2
    end)
end

function SFuncs.this_prop(prefab, element, property, ...)
    checkArgCount("SpecFunc.this", 3, prefab, element, property, ...)
    return element[property]
end

function SFuncs.child_prop(prefab, element, child, property, ...)
    checkArgCount("SpecFunc.child", 4, prefab, element, child, property, ...)
    return element:FindFirstChild(child)[property]
end

function SFuncs.this_attr(prefab, element, attrname, ...)
    checkArgCount("SpecFunc.this_attr", 3, prefab, element, attrname, ...)
    return element:GetAttribute(attrname)
end

function SFuncs.child_attr(prefab, element, child, attrname, ...)
    checkArgCount("SpecFunc.child_attr", 4, prefab, element, child, attrname, ...)
    return element:FindFirstChild(child):GetAttribute(attrname)
end

function SFuncs.str_varsub(prefab, element, str, ...)
    checkArgCount("SpecFunc.str_id_sub", 3, prefab, element, str, ...)
    local temp = ` {str} `
    temp = strKeySub(temp, "pid", getId(PREFAB_IDS, prefab))
    temp = strKeySub(temp, "eid", getId(ELEMENT_IDS, element))
    temp = strKeySub(temp, "pname", prefab.Name)
    temp = strKeySub(temp, "ename", element.Name)
    temp = strKeySub(temp, "rand", math.random(0, 9999))
    temp = strKeySub(temp, "hash_full", HttpService:GenerateGUID(false))
    temp = strKeySub(temp, "hash_6", HttpService:GenerateGUID(false):sub(0, 6))
    temp = temp:gsub("{{", "{"):gsub("}}", "}"):sub(2, -2)
    return temp
end

return SFuncs