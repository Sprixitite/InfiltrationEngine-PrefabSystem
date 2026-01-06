local glut = require("./GLUt")

local LuaExpr = {}

local LUA_EXPR_BODY_STRMATCH = "([\\\'\"%-%+%*%^%.,:/_%w%s{}<>!~=+|#`]+)"

function LuaExpr.NewEvalRules(prefix, delim)
    local bodyMatch = prefix .. LUA_EXPR_BODY_STRMATCH .. delim 
    return {
        BodyMatch = bodyMatch,
        SoleMatch = '^' .. bodyMatch .. '$'
    }
end

local LUA_EXPR_MATCH_DEFAULT = LuaExpr.NewEvalRules("%$%(", "%)")

local function isSoleExpr(str, rules)
    local soleExprData = string.match(str, rules.SoleMatch)
    return soleExprData ~= nil, soleExprData
end

local function evalSoleExpr(str, fenv, rules, exprName, multiRet)
    exprName = glut.default_typed(exprName, "LUAEXPR_UNNAMED", "exprName", "LuaExpr.EvalSoleExpr")
    multiRet = glut.default_typed(multiRet, false, "multiRet", "LuaExpr.EvalSoleExpr")
    
    local leadingReturn = string.match(str, "^return%s+")
    if leadingReturn == nil then str = "return " .. str end
    
    local success, count, args = glut.str_runlua(str, fenv, exprName)
    if not success then
        return false, "LuaExpr : " .. exprName .. " : Evaluation failed : " .. count
    end
    
    if multiRet then return success, args end
    
    if count < 1 then
        return false, "LuaExpr : " .. exprName .. " : Evaluation Succeeded But Return Invalid : Expected 1 return, got " .. count
    elseif count > 1 then
        return false, "LuaExpr : " .. exprName .. " : Evaluation Succeeded But Return Invalid : Expected 1 return, got " .. count
    end
    
    return success, args[1]
end

function LuaExpr.IsExpr(str, rules)
    rules = glut.default(rules, LUA_EXPR_MATCH_DEFAULT)
    local match = string.match(str, rules.BodyMatch)
    return match ~= nil, match
end

function LuaExpr.Eval(str, fenv, rules, exprName, soleOnly)
    if not glut.type_check(str, "string", "str", "LuaExpr.Eval") then return end
    if not glut.type_check(fenv, "table", "fenv", "LuaExpr.Eval") then return end
    
    rules = glut.default_typed(rules, LUA_EXPR_MATCH_DEFAULT, "rules", "LuaExpr.Eval")
    exprName = glut.default_typed(exprName, "LUAEXPR_UNNAMED", "epxrName", "LuaExpr.Eval")
    soleOnly = glut.default_typed(soleOnly, false, "soleOnly", "LuaExpr.Eval")
    
    local isSole, soleData = isSoleExpr(str, rules)
    if isSole then return evalSoleExpr(soleData, fenv, rules, exprName, soleOnly) end
    if soleOnly then return false, nil end
    
    local i = 0
    return true, string.gsub(str, rules.BodyMatch, function(subexpr)
        i = i+1
        local subExprName = exprName .. '#' .. tostring(i)
        local evalSuccess, evalVal = evalSoleExpr(subexpr, fenv, rules, subExprName, false)
        return tostring(evalVal)
    end)
end

return LuaExpr