local DebbieDebug = require("../Lib/DebbieDebug")
local ObjectTags = require("../Lib/ObjectTag")
local Tags = require("./Tags")

local function debug_print(t, inst, attrInfo, value, msg, always)
    if not always then
        local instData = ObjectTags.tag_get(inst, Tags.DEBUG)
        if instData == nil then return end
        if instData[attrInfo.Raw] ~= true then return end
    end
    
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
            return true, nil
        end
        
        error("I can't be bothered making this feature work right now, if you're reading this - make a pull request or go away")
        
        --local targetValid = inst:GetAttribute(attrInfo.Target) ~= nil
        --local valueValid  = type(value) == "boolean"
        --if not targetValid then
        --    return false, `{attrInfo.Raw} is invalid! Debug target {attrInfo.Target} does not exist on {inst.Parent}.{inst}`
        --elseif not valueValid then
        --    return false, `{attrInfo.Raw} is invalid! Debug setting {value} is not a boolean!`
        --end
        
        --if not debug_tag:has(inst) then
        --    debug_tag:add(inst, {})
        --end
        
        --local instAttrDebug = debug_tag:get(inst)
        --instAttrDebug[attrInfo.Target] = value
        
        --debug_print("DEBUG", inst, attrInfo, value, `Setting {attrInfo.Raw}'s Debug flag to {value}`, true)
        
        --return true, nil
    end,
    THIS = function(inst, attrInfo, value)
        debug_print("IGNORE", inst, attrInfo, value, `Discarding {attrInfo.Raw} & Setting ({inst}.{attrInfo.Target} = {value})`)
        delete_attr(inst, attrInfo.Raw)
        return pcall(function()
            inst[attrInfo.Target] = value
        end)
    end,
    STATE = function(inst, attrInfo, value, evalCtx)
        debug_print("STATE", inst, attrInfo, value, `Discarding {attrInfo.Raw} & Setting (state.{attrInfo.Target} = {value})`)
        delete_attr(inst, attrInfo.Raw)
        if evalCtx.InstanceState[attrInfo.Target] ~= nil then
            return false, `State value {attrInfo.Target} is already set!`
        end
        evalCtx.InstanceState[attrInfo.Target] = value
        return true, nil
    end,
    EXEC = function(inst, attrInfo, value)
        debug_print("EXEC", inst, attrInfo, value, "Discarding of attribute")
        delete_attr(inst, attrInfo.Raw)
        return true, nil
    end,
    IGNORE = function(inst, attrInfo, value)
        debug_print("IGNORE", inst, attrInfo, value, "Discarding of attribute")
        delete_attr(inst, attrInfo.Raw)
        return true, nil
    end,
    PEVAL = function(inst, attrInfo, value)
        debug_print("PEVAL", inst, attrInfo, value, `Setting ({attrInfo.Raw} = {value})`)
        inst:SetAttribute(attrInfo.Raw, value)
        if value == true and attrInfo.Target == "Done" then
            ObjectTags.tag(inst, Tags.EVAL_DONE)
        end
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
    ESCAPE = function(inst, attrInfo, value)
        debug_print("ESCAPE", inst, attrInfo, value, `Setting ({attrInfo.Target} = {value})`)
        move_and_set_attr(inst, attrInfo.Raw, attrInfo.Target, value)
        return true, nil
    end,
    ["@STANDARD"] = function(inst, attrInfo, value)
        debug_print("STANDARD", inst, attrInfo, value, `Setting ({attrInfo.Target} = {value})`)
        move_and_set_attr(inst, attrInfo.Raw, attrInfo.Target, value)
        return true, nil
    end,
}