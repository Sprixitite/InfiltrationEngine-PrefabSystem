--[[
    DebbieDebug // Debug module with granular per-object debugging control

    © Sprixitite, 2026
]]

local DebbieDebug = {}
DebbieDebug.IsGlobalDebug = false
DebbieDebug.IsGlobalDebugFN = nil

function DebbieDebug.init(fIsGlobalDebug, noFail)
    if DebbieDebug.IsGlobalDebugFN ~= nil and not noFail then
        error("Attempt to initialize DebbieDebug twice!")
    elseif DebbieDebug.IsGlobalDebugFN then
        return DebbieDebug.refresh()
    end
    DebbieDebug.IsGlobalDebugFN = fIsGlobalDebug
end

function DebbieDebug.refresh()
    DebbieDebug.IsGlobalDebug = DebbieDebug.IsGlobalDebugFN()
end

function DebbieDebug.print(...)
    if not DebbieDebug.IsGlobalDebug then return end
    print(...)
end

function DebbieDebug.warn(...)
    if not DebbieDebug.IsGlobalDebug then return end
    warn(...)
end

local function isObjectType(o)
    local oType = type(o)
    return oType == "table" or oType == "userdata"
end

local function debbieTostring(o)
    local tostringFn

    local oMeta = getmetatable(o)
    if oMeta then
        tostringFn = oMeta["@debbietostring"] or tostring
    else
        tostringFn = tostring
    end
    
    return tostringFn(o)
end

local debuggingObjects = setmetatable({}, {__mode = 'k'})
function DebbieDebug.set_obj_deb(obj, to)
    if not isObjectType(obj) then
        error("[DebbieDebug] Attempt to enable debugging for value type \"" .. tostring(obj) .. "\"")
    end
    debuggingObjects[obj] = to
end

function DebbieDebug.get_obj_deb(obj)
    if not isObjectType(obj) then
        warn("[DebbieDebug] Attempt to check debug flag for value type \"" .. tostring(obj) .. "\"")
    end
    return debuggingObjects[obj]
end

function DebbieDebug.obj_print(obj, ...)
    if not DebbieDebug.get_obj_deb(obj) then return end
    print(
        debbieTostring(obj),
        ...
    )
end

function DebbieDebug.obj_warn(obj, ...)
    if not DebbieDebug.get_obj_deb(obj) then return end
    warn(
        debbieTostring(obj),
        ...
    )
end

function DebbieDebug.globj_print(obj, ...)
    if not (DebbieDebug.IsGlobalDebug or DebbieDebug.get_obj_deb(obj)) then return end
    print(
        debbieTostring(obj),
        ...
    )
end

function DebbieDebug.globj_warn(obj, ...)
    if not (DebbieDebug.IsGlobalDebug or DebbieDebug.get_obj_deb(obj)) then return end
    warn(
        debbieTostring(obj),
        ...
    )
end

return DebbieDebug