local glut = require("../Lib/GLUt")
local exprFuncs = require("./LuaExprFuncs")

local ShebangFuncs = {}

local tableCheck = function(o)
    return type(o) == "table"
end

ShebangFuncs.CreateShebangFenv = function(evalState)
    if not (tableCheck(evalState.InstanceState) and tableCheck(evalState.StaticState) and tableCheck(evalState.GlobalState)) then
        warn("Invalid EvalState given! Is as follows:")
        print(evalState)
        print(getmetatable(evalState))
    end
    
    local tableLib = glut.tbl_clone(table)
    local stringLib = glut.tbl_clone(string)

    stringLib.split = glut.str_split
    tableLib.getkeys = glut.tbl_getkeys

    local luaExprFuncs = setmetatable(
        {},
        {
            __index = function(tbl, k)
                return function(targs)
                    return exprFuncs[k](evalState, targs)
                end
            end,
        }
    )

    local fenvBase = {
        exprFuncs     = luaExprFuncs,
        luaExprFuncs  = luaExprFuncs,
        global        = evalState.GlobalState,
        globals       = evalState.GlobalState,
        globalState   = evalState.GlobalState,
        state         = evalState.InstanceState,
        static        = evalState.StaticState,
        staticState   = evalState.StaticState,
        math          = math,
        table         = tableLib,
        string        = stringLib,
        CFrame        = CFrame,
        Color3        = Color3,
        Vector2       = Vector2,
        Vector3       = Vector3,
        tostring      = tostring,
        tonumber      = tonumber,
        pairs         = pairs,
        ipairs        = ipairs,
        next          = next,
        print         = print,
        unpack        = unpack,
        setAttributes = function(t) for k, v in pairs(t) do evalState.PrefabElement:SetAttribute(k, v) end return true end
    }

    -- state can't overshadow builtin libraries
    setmetatable(
        fenvBase,
        { __index = evalState.InstanceState }
    )
    return fenvBase
end

return ShebangFuncs
