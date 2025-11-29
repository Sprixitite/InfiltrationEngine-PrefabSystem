--[[
	GLUt // GoodLuaUtilities // Lua5.1 utilities module
	
	© Sprixitite, 2025
]]

local GLUt = {}

local GLUtCfg = {
	print = print,
	warn  = function(...) print("WARNING", ...) end,
	error = error,
	type  = type
}

local patternSpecChars = { '(', ')', '.', '%', '+', '-', '*', '?', '[', ']', '^', '$' }

function GLUt.configure(tbl)
	for k, v in pairs(tbl) do
		if GLUtCfg[k] ~= nil then
			GLUtCfg[k] = v
		else
			GLUtCfg.warn("Attempt to set invalid GLUtCfg Key \"" .. tostring(k) .. "\"")
		end
	end
end

function GLUt.default(arg, default)
	return (arg == nil) and default or arg
end

function GLUt.default_exec(arg, fn)
	return (arg == nil) and fn() or arg
end

function GLUt.default_typed(arg, default, argName, funcName)
	local argType = GLUtCfg.type(arg)
	local defaultType = GLUtCfg.type(default)
	if argType == defaultType then return arg end
	if argType == "nil" then return default end
	GLUt.type_warn(argName, funcName, defaultType, argType)
	return default
end

function GLUt.type_warn(argName, funcName, expected, got)
	if argName == nil or expected == got then return end

	local warnStart = GLUt.type_is(funcName, "string") and (funcName .. ": expected arg \"") or "Expected arg \""
	GLUtCfg.warn(warnStart .. argName .. "\" of type \"" .. expected .. "\" got type \"" .. got .. "\"!")
	GLUtCfg.warn("Traceback: " .. debug.traceback())
end

function GLUt.type_check(arg, expected, argName, funcName)
	local argType = GLUtCfg.type(arg)

	expected = string.gsub(expected, '?', "|nil")
	for _, validType in pairs(GLUt.str_split(expected, '|')) do
		if validType == argType then return true end
	end

	GLUt.type_warn(argName, funcName, expected, argType)

	return false
end

function GLUt.type_is(a1, t)
	return GLUtCfg.type(a1) == t
end

function GLUt.type_eq(a1, a2)
	return GLUtCfg.type(a1) == GLUtCfg.type(a2)
end

function GLUt.vararg_capture(...)
	local n = select('#', ...)
	return n, { ... }
end

function GLUt.vararg_iter(...)
	local n, t = GLUt.vararg_capture(...)
	local i = 0
	return function()
		i = i + 1
		if i <= n then return i, t[i], n end
	end, t
end

function GLUt.str_split(str, separator)
	str = str .. separator
	separator = GLUt.str_escape_pattern(separator)

	local substrs = {}
	for substr in string.gmatch(str, "(.-)" .. separator) do
		substrs[#substrs+1] = substr
	end
	return substrs
end

function GLUt.str_has_match(str, pattern)
	return string.match(str, pattern) ~= nil
end

function GLUt.str_escape_pattern(str)
	local escaped = str
	for _, specChar in ipairs(patternSpecChars) do
		local escapedSpec = '%' .. specChar
		escaped = string.gsub(escaped, escapedSpec, (specChar == '%') and "%%" or '%' .. escapedSpec)
	end
	return escaped
end

function GLUt.str_double_substr(str, substr)
	local safe = GLUt.str_escape_pattern(substr)
	return string.gsub(str, safe, safe .. safe)
end

function GLUt.str_isempty(str)
	return string.match(str, "^%s$") ~= nil
end

function GLUt.str_chariter(str)
	local n = #str
	local i = 0
	return function()
		i = i + 1
		if i <= n then return GLUt.str_getchar(str, i) end
	end
end

function GLUt.str_getchar(str, i)
	return string.sub(str, i, i)
end

local unidentified = -1
function GLUt.str_runlua(source, fenv, chunkName)
	chunkName = GLUt.default_exec(chunkName, function()
		unidentified = unidentified + 1
		return "loadstring#" .. tostring(unidentified) 
	end)

	local strFun, failReason = loadstring(source, chunkName)
	if GLUtCfg.type(strFun) ~= "function" then
		return false, "Loadstring : " .. chunkName .. " : Evaluation failed : " .. failReason
	end

	strFun = setfenv(strFun, fenv)

	return pcall(function()
		return GLUt.vararg_capture(strFun())
	end)
end

function GLUt.str_runlua_unsafe(source, chunkName)
	local strFun, failReason = loadstring(source, chunkName)
	if GLUtCfg.type(strFun) ~= "function" then
		return false, "Loadstring : " .. chunkName .. " : Evaluation failed : " .. failReason
	end

	return pcall(function()
		return GLUt.vararg_capture()
	end)
end

function GLUt.kvp_tostring(k, v)
	return tostring(k) .. " = " .. tostring(v)
end

function GLUt.tbl_tryindex(tbl, ...)
	local indexing = tbl
	for _, k in GLUt.vararg_iter(...) do
		if GLUtCfg.type(indexing) ~= "table" then
			return false, indexing
		end
		indexing = indexing[tostring(k)]
	end

	return true, indexing
end

function GLUt.tbl_deepget(tbl, create_missing, ...)
	local indexing = tbl
	for _, k in GLUt.vararg_iter(...) do
		k = tostring(k)
		if GLUtCfg.type(indexing) ~= "table" then
			return false, indexing
		end
		
		if indexing[k] == nil and create_missing then
			indexing[k] = {}
		end
		
		indexing = indexing[k]
	end
	
	return true, indexing
end

function GLUt.tbl_getkeys(tbl)
	local keys = {}
	for k, _ in pairs(tbl) do keys[#keys+1] = k end
	return keys
end

function GLUt.tbl_clone(tbl, shallow)
	shallow = GLUt.default(shallow, false)

	local cloned = {}
	for k, v in pairs(tbl) do
		if GLUtCfg.type(v) == "table" and not shallow then
			cloned[k] = GLUt.tbl_clone(v, shallow)
		else
			cloned[k] = v
		end
	end
	return cloned
end

function GLUt.tbl_findsize(tbl)
	local i = 0
	for _, _ in pairs(tbl) do i = i + 1 end
	return i
end

local function tbl_tostring(tblName, tbl, levels, level)
	local str = tblName .. " = {"
	local indent = string.rep("  ", level)
	local n = GLUt.tbl_findsize(tbl)
	local i = 0
	for k, v in pairs(tbl) do
		i = i + 1
		str = str .. '\n' .. indent
		if GLUtCfg.type(v) == "table" and levels > level then
			str = str .. tbl_tostring(k, v, levels, level+1)
		else
			str = str .. GLUt.kvp_tostring(k, v)
		end
		if i < n then str = str .. ',' end
	end
	return str
end

function GLUt.tbl_tostring(tbl, levels, tblName)
	GLUt.default(tblName, tostring(tbl))
	return tbl_tostring(tblName, tbl, levels, 1)
end

function GLUt.tbl_any(tbl, f)
	local anySucceed = nil
	for k, v in pairs(tbl) do
		anySucceed = GLUt.default(anySucceed, false) or f(k, v)
		if anySucceed then break end
	end
	return anySucceed
end

function GLUt.tbl_all(tbl, f)
	local allSucceed = nil
	for k, v in pairs(tbl) do
		allSucceed = GLUt.default(allSucceed, true) and f(k, v)
		if not allSucceed then break end
	end
	return allSucceed
end

return GLUt