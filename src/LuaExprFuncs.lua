local glut = require("./GLUt")

local luaExprFuncs = {}

local function StaticGroupErr(groupName)
	error("Attempt to set StaticStateGroup " .. groupName .. " but encountered non-table element!")
end

luaExprFuncs.staticGroupExport = function(state, staticState, t)
	-- Exports a variable as a member of a staticState group, creating the group if it does not exist
	local groupName = t[1]
	local value = t[2]
	local noDuplicates = t[3] or false
	local groupPath = glut.str_split(groupName, '.')
	local success, groupTbl = glut.tbl_deepget(staticState, true, unpack(groupPath))
	if not success then StaticGroupErr(groupName) end
	if noDuplicates then
		if table.find(groupTbl, value) then return value end
	end
	table.insert(groupTbl, value)
	return value
end

luaExprFuncs.staticGroupCombine = function(state, staticState, t)
	-- Concatenates the string representation of all members of a staticState group, using the specified operator inbetween all elements
	local groupName = t[1]
	local combineOp = t[2]
	local prefixOp = t[3]
	local suffixOp = t[4]
	local field = t[5]
	local elem_prefix = t.elem_prefix or ""
	local elem_suffix = t.elem_suffix or ""
	local groupPath = glut.str_split(groupName, '.')
	local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
	if not success then StaticGroupErr(groupName) end
	local str = (prefixOp or "") .. "("
	for i, v in ipairs(groupTbl) do
		if i ~= 1 then str = str .. combineOp end
		local vStr = (field == nil) and tostring(v) or tostring(v[field])
		str = str .. elem_prefix .. vStr .. elem_suffix
	end
	str = str .. ")" .. (suffixOp or "")
	return str
end

luaExprFuncs.staticGroupEmpty = function(state, staticState, t)
	-- Returns true if the StaticStateGroup at the given path is empty
	return luaExprFuncs.staticGroupSize(state, staticState, { t[1] }) == 0
end

luaExprFuncs.staticGroupSize = function(state, staticState, t)
	-- Returns the size of the StaticStateGroup at the given path - optionally as a string
	local groupName = t[1]
	local toStr = t[2] or false
	local zero_if_none = t[3] or false
	local groupPath = glut.str_split(groupName, '.')
	local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
	if not success and not zero_if_none then StaticGroupErr(groupName)
	else return 0 end
	return toStr and tostring(#groupTbl) or #groupTbl
end

luaExprFuncs.moveFirstStaticElement = function(state, staticState, t)
	-- Removes the first element of the StaticStateGroup at the given path, and places it
	local groupName = t[1]
	local destName = t[2]
	local wantPart = t[3] or 'v' -- Do you want the key or the value?
	if wantPart ~= 'k' and wantPart ~= 'v' then error("WantPart must be nil|\"k\"|\"v\"!") end
	local groupPath = glut.str_split(groupName, '.')
	local destPath = glut.str_split(destName, '.')
	local destKey = table.remove(destPath, #destPath)
	local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
	if not success then StaticGroupErr(groupName) end
	local success, destTbl = glut.tbl_deepget(staticState, true, unpack(destPath))
	if not success then StaticGroupErr(destName) end
	local groupKeys = glut.tbl_getkeys(groupTbl)
	local firstKey = groupKeys[1]
	local moving = nil
	if type(firstKey) == "number" then moving = table.remove(groupTbl, firstKey)
	else moving = groupTbl[firstKey] groupTbl[firstKey] = nil end
	if wantPart == 'k' then moving = firstKey end
	destTbl[destKey] = moving
	return true
end

luaExprFuncs.getStaticVariable = function(state, staticState, t)
	local varname = t[1]
	local varPath = glut.str_split(varname, '.')
	local varKey = table.remove(varPath, #varPath)
	local success, varTbl = glut.tbl_deepget(staticState, false, unpack(varPath))
	if not success then StaticGroupErr(varname) end
	return varTbl[varKey]
end

luaExprFuncs.fallbackIfUnset = function(state, staticState, t)
	-- Returns the second argument if the first contains the substring "UNSET" (case-sensitive)
	local maybeUnset = t[1]
	local fallback = t[2]
	if maybeUnset == nil then return fallback end
	if type(maybeUnset) ~= "string" then return maybeUnset end
	if glut.str_has_match(maybeUnset, "UNSET") then return fallback end
	if glut.str_has_match(maybeUnset, "DEFAULT") then return fallback end
	return maybeUnset
end

-- Convenience if you forget the name
luaExprFuncs.fallbackIfDefault = function(state, staticState, t) return luaExprFuncs.fallbackIfUnset(t) end

luaExprFuncs.CreateExprFenv = function(instState, staticState)
	return setmetatable(
		{},
		{
			__index = function(t, k)
				if instState[k] ~= nil then return instState[k] end
				if luaExprFuncs[k] == nil then return nil end
				return function(t)
					return luaExprFuncs[k](instState, staticState, t)
				end
			end,
		}
	)
end

return luaExprFuncs