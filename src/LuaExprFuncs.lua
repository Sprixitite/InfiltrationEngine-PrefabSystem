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

luaExprFuncs.setStateValue = ExprFunc(
	"setStateValues",
	function(inst, state, staticState, name, value)
		if state[name] ~= nil then
			error("Attempt to set already-existing StateValue \"" .. name .. "\"!")
		end 
		state[name] = value
		return true
	end,
	{ 1, "name", "string", false, vital=true },
	{ 2, "value", false, false, vital=true }
)

luaExprFuncs.stringSplit = ExprFunc(
	"stringSplit",
	function(inst, state, staticState, value, separator)
		return glut.str_split(value, separator)
	end,
	{ 1, "value", "string", false, vital=true },
	{ 2, "separator", "string", false, vital=true }
)

luaExprFuncs.unpackToState = ExprFunc(
	"unpackToState",
	function(inst, state, staticState, unpacking, ...)
		local locTbl = { ... }
		for i, v in ipairs(unpacking) do
			local locPath = locTbl[i]
			if locPath == nil then break end
			local unpackPath = glut.str_split(locPath, '.')
			local unpackLast = table.remove(unpackPath)
			local success, unpackTbl = glut.tbl_deepget(state, true, unpack(unpackPath))
			if not success then StaticGroupErr(locPath) end
			unpackTbl[unpackLast] = v
		end
		return true
	end,
	-- Ugly hack
	-- You get 16 unpack locations, use em wisely
	{  1, "unpacking", "table", false, vital=true },
	{  2, "state#1", "string", false, vital=true },
	{  3, "state#2", "string?", false, default=nil },
	{  4, "state#3", "string?", false, default=nil },
	{  5, "state#4", "string?", false, default=nil },
	{  6, "state#5", "string?", false, default=nil },
	{  7, "state#6", "string?", false, default=nil },
	{  8, "state#7", "string?", false, default=nil },
	{  9, "state#8", "string?", false, default=nil },
	{ 10, "state#9", "string?", false, default=nil },
	{ 11, "state#10", "string?", false, default=nil },
	{ 12, "state#11", "string?", false, default=nil },
	{ 13, "state#12", "string?", false, default=nil },
	{ 14, "state#13", "string?", false, default=nil },
	{ 15, "state#14", "string?", false, default=nil },
	{ 16, "state#15", "string?", false, default=nil },
	{ 17, "state#16", "string?", false, default=nil }
)

luaExprFuncs.staticGroupToLocalArray = ExprFunc(
	"staticGroupToLocalArray",
	function(inst, state, staticState, groupName, elementPrefix, stateScriptAccess)
		local groupPath = glut.str_split(groupName, '.')
		local success, groupTbl = glut.tbl_deepget(state, unpack(groupPath))
		if not success then StaticGroupErr(groupName) end
		inst:SetAttribute(elementPrefix .. "Count", #groupTbl)
		local statescriptAccessor = "INIT #StateScriptAccessLocalArrayTemp 0"
		for i, v in ipairs(groupTbl) do
			statescriptAccessor = statescriptAccessor .. "\n SET #StateScriptAccessLocalArrayTemp #" .. elementPrefix .. tostring(i) 
			inst:SetAttribute(elementPrefix .. tostring(i), v)
		end
		if stateScriptAccess ~= "NO!" then
			inst:SetAttribute(stateScriptAccess, statescriptAccessor)
		end
		return true
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "elementPrefix", "string", false, vital=true },
	{ 3, "stateScriptAccess", "string", true, default="NO!" }
)

luaExprFuncs.importStaticGroup = ExprFunc(
	"importStaticGroup",
	function(inst, state, staticState, groupName, importLocation, allowDuplicates)
		local importPath = glut.str_split(importLocation, '.')
		local importKey = table.remove(importPath)
		local success, importTbl = glut.tbl_deepget(state, true, unpack(importPath))
		if not success then StaticGroupErr(importPath) end
		if importTbl[importKey] ~= nil then return end
		local groupPath = glut.str_split(groupName, '.')
		local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
		if not success then StaticGroupErr(groupName) end
		groupTbl = glut.tbl_clone(groupTbl, false)
		if not allowDuplicates then
			local noDupes = {}
			for k, v in pairs(groupTbl) do
				if table.find(noDupes, v) ~= nil then continue end
				if type(k) == "number" then table.insert(noDupes, v) continue end
				noDupes[k] = v
			end
			groupTbl = noDupes
		end
		importTbl[importKey] = groupTbl
		return true
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "importLocation", "string", false, vital=true },
	{ 3, "allowDuplicates", "boolean", true, default=true }
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
		itemSuffix,
		autoBrackets
	)
		-- Concatenates the string representation of all members of a staticState group, using the specified operator inbetween all elements
		local groupPath = glut.str_split(groupName, '.')
		local success, groupTbl = glut.tbl_deepget(staticState, false, unpack(groupPath))
		if not success then StaticGroupErr(groupName) end
		local openBracket = autoBrackets and "(" or ""
		local closeBracket = autoBrackets and ")" or ""
		local str = prefix .. openBracket
		for i, v in ipairs(groupTbl) do
			if i ~= 1 then str = str .. combineOp end
			local vStr = (field == nil) and tostring(v) or tostring(v[field])
			str = str .. itemPrefix .. vStr .. itemSuffix
		end
		str = str .. closeBracket .. suffix
		return str
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "combineOp", "string", false, vital=true },
	{ 3, "prefix", "string", true, default="" },
	{ 4, "suffix", "string", true, default="" },
	{ 5, "field", false, true, default=nil },
	{ 6, "itemPrefix", "string", true, default="" },
	{ 7, "itemSuffix", "string", true, default="" },
	{ 8, "autoBrackets", "boolean", true, default=true }
)

luaExprFuncs.staticGroupEmpty = ExprFunc(
	"staticGroupEmpty",
	function(inst, state, staticState, groupName, quietFail)
		-- Returns true if the StaticStateGroup at the given path is empty
		return luaExprFuncs.staticGroupSize(inst, state, staticState, { groupName, quietFail=quietFail }) == 0
	end,
	{ 1, "groupName", "string", false, vital=true },
	{ 2, "quietFail", "boolean", true, default=false }
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

luaExprFuncs.CreateExprFenv = function(inst, instState, staticState, globalState)
	return setmetatable(
		{},
		{
			__index = function(t, k)
				if instState[k] ~= nil then return instState[k] end
				if k == "Global" or k == "Globals" then return globalState end
				if luaExprFuncs[k] == nil then return nil end
				return function(t)
					return luaExprFuncs[k](inst, instState, staticState, t)
				end
			end,
		}
	)
end

return luaExprFuncs