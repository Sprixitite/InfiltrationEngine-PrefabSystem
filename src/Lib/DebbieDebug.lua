--[[
    DebbieDebug // Debug module with granular per-object debugging control

    © Sprixitite, 2026
]]

local DebbieDebug = {}
DebbieDebug.IsGlobalDebug = false
DebbieDebug.IsGlobalDebugFN = nil

local no_op_fn = function() end

function DebbieDebug.init(fIsGlobalDebug, noFail)
    if DebbieDebug.IsGlobalDebugFN ~= nil and not noFail then
        error("Attempt to initialize DebbieDebug twice!")
    elseif DebbieDebug.IsGlobalDebugFN then
        return DebbieDebug.refresh()
    end
    DebbieDebug.IsGlobalDebugFN = fIsGlobalDebug
    DebbieDebug.refresh()
end

local function is_debug()
    return DebbieDebug.IsGlobalDebug
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
local function set_obj_deb(obj, to)
    if not isObjectType(obj) then
        error("[DebbieDebug] Attempt to enable debugging for value type \"" .. tostring(obj) .. "\"")
    end
    debuggingObjects[obj] = to
end

local function get_obj_deb(obj)
    if not isObjectType(obj) then
        warn("[DebbieDebug] Attempt to check debug flag for value type \"" .. tostring(obj) .. "\"")
    end
    return debuggingObjects[obj]
end

local function obj_print(obj, ...)
    if not DebbieDebug.get_obj_deb(obj) then return end
    print(
        debbieTostring(obj),
        ...
    )
end

local function obj_warn(obj, ...)
    if not DebbieDebug.get_obj_deb(obj) then return end
    warn(
        debbieTostring(obj),
        ...
    )
end

local function globj_print(obj, ...)
    if not (DebbieDebug.IsGlobalDebug or DebbieDebug.get_obj_deb(obj)) then return end
    print(
        debbieTostring(obj),
        ...
    )
end

local function globj_warn(obj, ...)
    if not (DebbieDebug.IsGlobalDebug or DebbieDebug.get_obj_deb(obj)) then return end
    warn(
        debbieTostring(obj),
        ...
    )
end

local module_stdconf = {
    print = print,
    warn  = warn,
    
    is_debug = is_debug,
    set_obj_deb = set_obj_deb,
    get_obj_deb = get_obj_deb,
    obj_print = obj_print,
    obj_warn = obj_warn,
    globj_print = globj_print,
    globj_warn = globj_warn
}

local module_disabledconf = {
    print = no_op_fn,
    warn = no_op_fn,
    
    is_debug = is_debug,
    set_obj_deb = set_obj_deb,
    get_obj_deb = get_obj_deb,
    obj_print = obj_print,
    obj_warn = obj_warn,
    globj_print = globj_print,
    globj_warn = globj_warn
}

function DebbieDebug.refresh()
    DebbieDebug.IsGlobalDebug = DebbieDebug.IsGlobalDebugFN()
    local conf = DebbieDebug.IsGlobalDebug and module_stdconf or module_disabledconf
    for k, v in pairs(conf) do
        DebbieDebug[k] = v
    end
end

return DebbieDebug