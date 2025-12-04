local glut = require("./GLUt")
local exprFuncs = require("./LuaExprFuncs")

local ShebangFuncs = {}

ShebangFuncs.CreateShebangFenv = function(inst, state, staticState, globalState)
	local tableLib = glut.tbl_clone(table)
	local stringLib = glut.tbl_clone(string)

	stringLib.split = glut.str_split
	tableLib.getkeys = glut.tbl_getkeys
	
	local luaExprFuncs = setmetatable(
		{},
		{
			__index = function(tbl, k)
				return function(targs)
					return exprFuncs[k](inst, state, staticState, targs)
				end
			end,
		}
	)
	
	local fenvBase = {
		exprFuncs = luaExprFuncs,
		luaExprFuncs = luaExprFuncs,
		global = globalState,
		globals = globalState,
		globalState = globalState,
		state = state,
		static = staticState,
		staticState = staticState,
		math = math,
		table = tableLib,
		string = stringLib,
		CFrame = CFrame,
		Color3 = Color3,
		Vector2 = Vector2,
		Vector3 = Vector3,
		tostring = tostring,
		tonumber = tonumber,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		print = print,
		unpack = unpack,
		setAttributes = function(t) for k, v in pairs(t) do inst:SetAttribute(k, v) end return true end
	}

	-- state can't overshadow builtin libraries
	setmetatable(
		fenvBase,
		{ __index = state }
	)
	return fenvBase
end

return ShebangFuncs
