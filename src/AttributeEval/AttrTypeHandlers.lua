local DEBUGGING_ATTRS = setmetatable({}, {__mode='k'})
local DebbieDebug = require("../Lib/DebbieDebug")

local function debug_print(t, inst, attrInfo, value, msg)
    if DEBUGGING_ATTRS[inst] == nil then return end
    if DEBUGGING_ATTRS[inst][attrInfo.Raw] ~= true then return end
    local msgFull = `ATTR_DEBUG/{t} : {inst.Parent}.{inst}@{attrInfo.Raw} : {inst:GetAttribute(attrInfo.Raw)} : Evaluated to {value}`
    if msg ~= nil then msgFull = msgFull .. ` : {msg}` end
    warn(msgFull)
end

local function delete_attr(inst, name)
    inst:SetAttribute(name, nil)
end

local function move_and_set_attr(inst, from, to, value)
    delete_attr(inst, from)
    inst:SetAttribute(to  , value)
end

return {
    DEBUG = function(inst, attrInfo, value)
        delete_attr(inst, attrInfo.Raw)
        
        if attrInfo.Target == "this" then
            DebbieDebug.set_obj_deb(inst, true)
            return
        end
        
        local targetValid = inst:GetAttribute(attrInfo.Target) ~= nil
        local valueValid  = type(value) == "boolean"
        if not targetValid then
            return false, `{attrInfo.Raw} is invalid! Debug target {attrInfo.Target} does not exist on {inst.Parent}.{inst}`
        elseif not valueValid then
            return false, `{attrInfo.Raw} is invalid! Debug setting {value} is not a boolean!`
        end
        
        DEBUGGING_ATTRS[inst] = DEBUGGING_ATTRS[inst] or {}
        DEBUGGING_ATTRS[inst][attrInfo.Target] = value
        
        DEBUGGING_ATTRS[inst][attrInfo.Raw] = true
        debug_print("DEBUG", inst, attrInfo, value, `Setting {attrInfo.Raw}'s Debug flag to {value}`)
        DEBUGGING_ATTRS[inst][attrInfo.Raw] = nil
        
        return true, nil
    end,
    THIS = function(inst, attrInfo, value)
        debug_print("IGNORE", inst, attrInfo, value, `Discarding {attrInfo.Raw} & Setting ({inst}.{attrInfo.Target} = {value})`)
        delete_attr(inst, attrInfo.Raw)
        return pcall(function()
            inst[attrInfo.Target] = value
        end)
    end,
    EXEC = function(inst, attrInfo, value)
        debug_print("EXEC", inst, attrInfo, value, "Discarding of attribute")
        delete_attr(inst, attrInfo.Raw)
        return true, nil
    end,
    IGNORE = function(inst, attrInfo, value)
        warn(`{inst.Parent}.{inst} is using deprecated "ignore" attribute type - swap to "exec" to silence`)
        debug_print("IGNORE", inst, attrInfo, value, "Discarding of attribute")
        delete_attr(inst, attrInfo.Raw)
        return true, nil
    end,
    PEVAL = function(inst, attrInfo, value)
        debug_print("PEVAL", inst, attrInfo, value, "Discarding of attribute")
        inst:SetAttribute(attrInfo.Raw, value)
        return true, nil
    end,
    IMPONLY = function(inst, attrInfo, value)
        debug_print("IMPONLY", inst, attrInfo, value, "Discarding of attribute")
        delete_attr(inst, attrInfo.Raw)
        return true, nil
    end,
    NOIMP = function(inst, attrInfo, value)
        debug_print("NOIMP", inst, attrInfo, value, `Setting ({attrInfo.Target} = {value})`)
        move_and_set_attr(inst, attrInfo.Raw, attrInfo.Target, value)
        return true, nil
    end,
    ["@STANDARD"] = function(inst, attrInfo, value)
        debug_print("STANDARD", inst, attrInfo, value, `Setting ({attrInfo.Target} = {value})`)
        move_and_set_attr(inst, attrInfo.Raw, attrInfo.Target, value)
        return true, nil
    end,
}