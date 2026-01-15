--[[
    EnumEngineer // Native Lua Rich Enum Module
    Enum items may contain arbitrary data, as well as be assigned methods

    Tested to be compatible with Lua5.1
    Presumed to be compatible with Lua5.2-5.5/LuaJIT

    © Sprixitite, 2026
]]

local function tblClone(tbl)
    local cloned = {}
    for k, v in pairs(tbl) do
        if type(v) ~= "table" then
            cloned[k] = v
        else
            cloned[k] = tblClone(v)
        end
    end
    return cloned
end

local function weakTbl(k, v)
    local modeStr = ((k and v) and "kv") or (k and 'k') or (v and 'v') or nil
    return setmetatable({}, {__mode=modeStr})
end

local EnumEngineer = {}
local newproxyAvailable = (_VERSION == "Luau" or _VERSION == "Lua 5.1")

local enumData = {}

local _enumData = weakTbl(true, false)
function enumData.new(obj, name, items, itemMethods, sealed)
    local itemsList = {}

    local itemCount = 0
    for _, _ in pairs(items) do itemCount = itemCount + 1 end
    _enumData[obj] = {
        Name = name,
        ItemsDict = items,
        ItemMethods = itemMethods,
        ItemCount = itemCount,
        Sealed = sealed
    }
end

function enumData.get(enum)
    return _enumData[enum]
end

function enumData.add_item(enum, enumItem)
    local data = enumData.get(enum)
    data.ItemCount = data.ItemCount + 1
    data.ItemsDict[enumItem.Name] = enumItem
end

local enumItem = {}

function enumItem.new(itemEnum, itemId, itemName, itemValue, itemMeta)
    if type(itemValue) ~= "table" then
        return setmetatable(
            { Id = itemId, Name = itemName, Value = itemValue, Enum = itemEnum },
            itemMeta
        )
    else
        return setmetatable(
            { Id = itemId, Name = itemName, Value = tblClone(itemValue), Enum = itemEnum },
            itemMeta
        )
    end
end

function enumItem.fromDict(enum, items, itemMeta)
    local wrapped = {}
    local i = 0
    for name, value in pairs(items) do
        i = i + 1
        wrapped[i] = enumItem.new(enum, i, name, value, itemMeta)
    end
    return wrapped
end

function enumItem.newMeta(methods)
    return {
        __index = enumItem.__index,
        __newindex = enumItem.__newindex,
        __tostring = enumItem.__tostring,
        ItemMethods = methods
    }
end

function enumItem.__index(t, k)
    if type(k) == "string" then
        -- MyEnum.nAmE -> MyEnum.Name
        local caseKey = k:sub(1, 1):upper() .. k:sub(2, -1):lower()
        local caseVal = rawget(t, caseKey)
        if caseVal ~= nil then return caseVal end
    end
    local itemMethods = getmetatable(t).ItemMethods
    return itemMethods[k]
end

function enumItem.__newindex(t, k, v)
    error("Attempt to set \"" .. tostring(k) .. " = " .. tostring(v) .. "\" on ")
end

function enumItem.__tostring(t)
    local enumName = enumData.get(rawget(t, "Enum")).Name

    local selfName = rawget(t, "Name")
    local selfId   = rawget(t, "Id")
    local selfVal  = rawget(t, "Value")
    return "Enum \"" .. enumName .. "\" / EnumItem \"" .. selfName .. "\" { Id = " .. tostring(selfId) .. ", Value = " .. tostring(selfVal) .. " }"
end

local function enumNewIndex(t, k, v)
    error("Attempt to set \"" .. tostring(k) .. " = " .. tostring(v) .. "\" on enum \"" .. EnumEngineer.get_name(t) .. "\"")
end

local function enumIndex(t, k)
    local enumItems = enumData.get(t).ItemsDict
    local queriedItem = enumItems[k]
    if queriedItem ~= nil then
        return queriedItem
    end
    local enumMethod = EnumEngineer[k]
    if enumMethod == EnumEngineer.new then
        return nil
    end

    if enumMethod == nil then
        error(
            "Attempted to index Enum for \"" .. tostring(k) .. "\" but no such EnumItem or Method exists!\n" .. 
                "Enum is as follows: " .. tostring(t)
        )
    end
    return enumMethod
end

local function enumLen(t)
    return enumData.get(t).ItemCount
end

local function enumTostring(t)
    local i = 0
    local n = #t
    local enumItems = enumData.get(t).ItemsDict

    local strRep = "Enum \"" .. EnumEngineer.get_name(t) .. "\" { "
    for k, _ in pairs(enumItems) do
        i = i + 1
        strRep = strRep .. tostring(k)
        if i < n then
            strRep = strRep .. ", "
        end
    end

    return strRep .. " }"
end

local function newEnum(name, itemMethods)
    local enumMeta

    local enumObj
    if newproxyAvailable then
        enumObj = newproxy(true)
        enumMeta = getmetatable(enumObj)
    else
        enumObj = {}
        enumMeta = {}
        setmetatable(enumObj, enumMeta)
    end

    enumMeta.__index    = enumIndex
    enumMeta.__newindex = enumNewIndex
    enumMeta.__len      = enumLen
    enumMeta.__tostring = enumTostring

    enumData.new(enumObj, name, {}, itemMethods, false)

    return enumObj
end

function EnumEngineer.new(name, items, itemMethods)
    items = items or {}

    local enumObj = newEnum(name, itemMethods)

    for name, value in pairs(items) do
        enumObj:add(name, value)
    end

    return enumObj
end

function EnumEngineer.add(enum, name, value)
    local valid, enum_data = EnumEngineer.is_enum(enum)
    if not valid then error("First argument to EnumEngineer.add must be an Enum!") end

    if enum_data.enumSeal then
        error("Attempt to add Enum Item to Sealed Enum \"" .. tostring(enum) .. "\"")
    end

    local newItem = enumItem.new(enum, enum_data.ItemCount+1, name, value, enumItem.newMeta(enum_data.ItemMethods))
    enumData.add_item(enum, newItem)
end

function EnumEngineer.seal(enum)
    if enum:is_sealed() then return end
    enumData.get(enum).enumSeal = true
    return enum
end

function EnumEngineer.is_sealed(enum)
    local valid, data = EnumEngineer.is_enum(enum)
    if not valid then
        error("Attempted to check Enum Seal of Non-Enum value \"" .. tostring(enum) .. "\"!")
    end
    return enumData.get(enum).enumSeal
end

function EnumEngineer.is_enum(enum)
    local enumData = enumData.get(enum)
    return enumData ~= nil, enumData
end

function EnumEngineer.get_name(enum)
    local valid, data = EnumEngineer.is_enum(enum)
    if not valid then
        error("Attempted to get Enum Name of Non-Enum value \"" .. tostring(enum) .. "\"!")
    end
    return data.Name
end

function EnumEngineer.item_exists(enum, itemName)
    local valid, data = EnumEngineer.is_enum(enum)
    if not valid then
        error("Attempted to get EnumItem of Non-Enum value \"" .. tostring(enum) .. "\"!")
    end
    local item = data.ItemsDict[itemName]
    return item ~= nil, item
end

return EnumEngineer