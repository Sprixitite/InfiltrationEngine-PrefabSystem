local glut = require("./GLUt")

local luaExprFuncs = {}

local function StaticGroupErr(groupName)
	error("Attempt to set StaticStateGroup " .. groupName .. " but encountered non-table element!")
end

local function returnArgs(...) return ... end

local function ExprFunc(fname, f, ...)
	local tblCallable = glut.fun_tblcallable(fname, returnArgs, ...)
	return function(inst, state, staticState, t)
		return f(inst, state, staticState, tblCallable(t))
	end
end

local function ExprFuncOverload(fname, f, foverloading, ...)
	local tblCallable = glut.fun_tblcallable(fname, returnArgs, ...)
	return function(inst, state, staticState, t)
		local overloaded = function() return foverloading(inst, state, staticState, t) end
		return f(inst, state, staticState, overloaded, tblCallable(t))
	end
end

luaExprFuncs.setAttributes = ExprFunc(
	"setAttributes",
	function(inst, state, staticState, attrs)
		for k, v in pairs(attrs) do
			inst:SetAttribute(k, v)
		end
		return true
	end,
	{ 1, "attributes", "table", false, vital=true }
)

luaExprFuncs.staticGroupExport = ExprFunc(
	"staticGroupExport",
	function(inst, state, staticState, groupName, exportValue, allowDuplicates)
		-- Exports a variable as a member of a staticState group, creating the group if it does not exist
		local groupPath = glut.str_split(groupName, '.')
		local success, groupTbl = glut.tbl_deepget(staticState, true, unpack(groupPath))
		if not success then StaticGroupErr(groupName) end
		if not allowDuplicates then
			if table.find(groupTbl, exportValue) then return exportValue end
		end
		table.insert(groupTbl, exportValue)
		return exportValue
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "exportValue", false, false, vital=true },
	{ 3, "allowDuplicates", "boolean", true, default=false }
)

luaExprFuncs.staticGroupCombine = ExprFunc(
	"staticGroupCombine",
	function(
		inst, state, staticState,
		groupName,
		combineOp,
		prefix,
		suffix,
		field,
		itemPrefix,
		itemSuffix
	)
		-- Concatenates the string representation of all members of a staticState group, using the specified operator inbetween all elements
		local groupPath = glut.str_split(groupName, '.')
		local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
		if not success then StaticGroupErr(groupName) end
		local str = prefix .. "("
		for i, v in ipairs(groupTbl) do
			if i ~= 1 then str = str .. combineOp end
			local vStr = (field == nil) and tostring(v) or tostring(v[field])
			str = str .. itemPrefix .. vStr .. itemSuffix
		end
		str = str .. ")" .. suffix
		return str
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "combineOp", "string", false, vital=true },
	{ 3, "prefix", "string", true, default="" },
	{ 4, "suffix", "string", true, default="" },
	{ 5, "field", false, true, default=nil },
	{ 6, "itemPrefix", "string", true, default="" },
	{ 7, "itemSuffix", "string", true, default="" }
)

luaExprFuncs.staticGroupEmpty = ExprFunc(
	"staticGroupEmpty",
	function(inst, state, staticState, groupName)
		-- Returns true if the StaticStateGroup at the given path is empty
		return luaExprFuncs.staticGroupSize(inst, state, staticState, { groupName }) == 0
	end,
	{ 1, "groupName", "string", false, vital=true }
) 

luaExprFuncs.staticGroupSize = ExprFunc( 
	"staticGroupSize",
	function(inst, state, staticState, groupName, asString, quietFail)
		-- Returns the size of the StaticStateGroup at the given path - optionally as a string
		local groupPath = glut.str_split(groupName, '.')
		local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
		if not success and not quietFail then
			StaticGroupErr(groupName)
		elseif not success then
			return 0
		end
		return (asString and tostring(#groupTbl)) or #groupTbl
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "asString", "boolean", true, default=false },
	{ 3, "quietFail", "boolean", true, default=false }
)

luaExprFuncs.moveFirstStaticElement = ExprFunc(
	"moveFirstStaticElement",
	function(
		inst, state, staticState,
		groupName,
		destName,
		pairItem,
		quietFail
	)
		-- Removes the first element of the StaticStateGroup at the given path, and places it
		if pairItem ~= 'k' and pairItem ~= 'v' then error("pairItem must be nil|\"k\"|\"v\"!") end
		local groupPath = glut.str_split(groupName, '.')
		local destPath = glut.str_split(destName, '.')
		local destKey = table.remove(destPath, #destPath)
		local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
		if not success then StaticGroupErr(groupName) end
		local success, destTbl = glut.tbl_deepget(staticState, true, unpack(destPath))
		if not success then StaticGroupErr(destName) end
		local groupKeys = glut.tbl_getkeys(groupTbl)
		local firstKey = groupKeys[1]
		if firstKey == nil and quietFail then return true end
		local moving = nil
		if type(firstKey) == "number" then 
			moving = table.remove(groupTbl, firstKey)
		else 
			moving = groupTbl[firstKey]
			groupTbl[firstKey] = nil 
		end
		if pairItem == 'k' then moving = firstKey end
		destTbl[destKey] = moving
		return true
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "destinationName", "string", false, vital=true },
	{ 3, "pairItem", "string", true, default="v" },
	{ 4, "quietFail", "boolean", true, default=false }
)

luaExprFuncs.getStaticVariable = ExprFunc( 
	"getStaticVariable",
	function(inst, state, staticState, varName)
		local varPath = glut.str_split(varName, '.')
		local varKey = table.remove(varPath, #varPath)
		local success, varTbl = glut.tbl_deepget(staticState, false, unpack(varPath))
		if not success then StaticGroupErr(varName) end
		return varTbl[varKey]
	end,
	{ 1, "varName", "string", false, vital=true }
)

luaExprFuncs.fallbackIfUnset = ExprFunc(
	"fallbackIfUnset",
	function(inst, state, staticState, maybeUnset, fallback)
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
	function(inst, state, staticState, overload, maybeUnset, fallback)
		return overload()
	end,
	{ 1, "maybeUnset", false, false, default=nil },
	{ 2, "fallback", false, false, default=nil }
)

luaExprFuncs.CreateExprFenv = function(inst, instState, staticState)
	return setmetatable(
		{},
		{
			__index = function(t, k)
				if instState[k] ~= nil then return instState[k] end
				if luaExprFuncs[k] == nil then return nil end
				return function(t)
					return luaExprFuncs[k](inst, instState, staticState, t)
				end
			end,
		}
	)
end

return luaExprFuncs