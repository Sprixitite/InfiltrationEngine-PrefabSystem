--[[
    ObjectTags // Module for assigning metadata to tables/userdata without all the boilerplate

    © Sprixitite, 2026
]]

local objectTags = {}

local weakMeta = { __mode = 'k' }

---@class Object : table|userdata

---@class ObjectTag
---@field name string
---@field add fun(self: ObjectTag, obj: Object, data: any?)
---@field remove fun(self: ObjectTag, obj: Object)
---@field get fun(self: ObjectTag, obj: Object) : any
---@field has fun(self: ObjectTag, obj: Object) : boolean

local function object_check(caller, argNum, obj)
    local oT = type(obj)
    if oT ~= "userdata" and oT ~= "table" then
        error("[" .. caller .. "]: Arg #" .. argNum .. " \"obj\" - Expected table|userdata, got " .. oT)
    end
end

local function tagMethodName(tag, methodName)
    return tag.name .. ":" .. methodName
end

local function tag_add(tag, obj, data)
    object_check(
        tagMethodName(tag, "add"),
        1,
        obj
    )
    data = (data == nil) and true
    tag[obj] = data
end

local function tag_remove(tag, obj)
    object_check(
        tagMethodName(tag, "remove"),
        1,
        obj
    )
    tag[obj] = nil
end

local function tag_get(tag, obj)
    object_check(
        tagMethodName(tag, "get"),
        1,
        obj
    )
    return tag[obj]
end

local function tag_has(tag, obj)
    object_check(
        tagMethodName(tag, "has"),
        1,
        obj
    )
    return tag[obj] ~= nil
end

---@param name string
---@return ObjectTag
local function newTag(name)
    return setmetatable(
        {
            add = tag_add,
            remove = tag_remove,
            get = tag_get,
            has = tag_has,
            name = name
        },
        weakMeta
    )
end

local _tagDB = {}

local function getPublicTag(name)
    local tag = _tagDB[name]
    if tag ~= nil then return tag end

    _tagDB[name] = newTag(name)
    return _tagDB[name]
end

---Create a new tag for private use, usually for use within an external module
---@param tagName string
---@return ObjectTag
function objectTags.new_private_tag(tagName)
    if type(tagName) ~= "string" then error("Attempt to create private tag with non-string name \"" .. tostring(tagName) .. "\"!") end
    return newTag(tagName)
end

--- Assign an object to a tag, optionally providing tag-related data
--- @param obj table|userdata
--- @param tagName string
--- @param data any? Defaults to true if nil
--- @return boolean overwrote Flag indicating if data was previously stored for this object
--- @return any? oldData The previously stored data for this object, if applicable
function objectTags.tag(obj, tagName, data)
    data = (data == nil) and true or data

    local tag = getPublicTag(tagName)

    local old = tag:get(obj)
    tag:add(obj, data)

    return old ~= nil, old
end

function objectTags.tag_has(obj, tagName)
    local tag = getPublicTag(tagName)
    return tag:has(obj)
end

function objectTags.tag_get(obj, tagName)
    local tag = getPublicTag(tagName)
    return tag:get(obj)
end

--- Remove an object from a tag, provided it was previously assigned to that tag
--- @param obj table|userdata
--- @param tagName string
--- @return boolean deleted Flag indicating if data was previously stored for this object
--- @return any? oldData The previously stored data for this object, if applicable
function objectTags.untag(obj, tagName)
    local tag = getPublicTag(tagName)

    local old = tag:get(obj)
    tag:remove(obj)

    return old ~= nil, old
end

return objectTags