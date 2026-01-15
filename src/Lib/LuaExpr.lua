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

local is_success = function(t)
    return t.EvalGood
end

local args_good = function(t)
    return t.ArgsGood
end

local worse_than = function(t, ot)
    return t.Severity > ot.Severity
end

local newStatus = function(evalSuccess, argsValid, severity)
    return { 
        EvalGood = evalSuccess,
        ArgsGood = argsValid,
        Severity = severity,
        
        is_success = is_success,
        args_good = args_good,
        worse_than = worse_than
    }
end

LuaExpr.Statuses = {}
LuaExpr.Statuses.SUCCESS = newStatus(true, true, 0)
LuaExpr.Statuses.SUCCESS_ARGWARN = newStatus(true, false, 1)
LuaExpr.Statuses.FAILURE = newStatus(false, false, 2)

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
        return LuaExpr.Statuses.FAILURE, nil, "LuaExpr : " .. exprName .. " : Evaluation failed : " .. count
    end

    if multiRet then return success, args end

    if count < 1 then
        return LuaExpr.Statuses.SUCCESS_ARGWARN, nil, "LuaExpr : " .. exprName .. " : Evaluation Succeeded But Return Invalid : Expected 1 return, got " .. count
    elseif count > 1 then
        return LuaExpr.Statuses.SUCCESS_ARGWARN, nil, "LuaExpr : " .. exprName .. " : Evaluation Succeeded But Return Invalid : Expected 1 return, got " .. count
    end

    return LuaExpr.Statuses.SUCCESS, args[1]
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
    local worstStatus = LuaExpr.Statuses.SUCCESS
    local worstMsg = nil
    local sub = string.gsub(str, rules.BodyMatch, function(subexpr)
        i = i+1
        local subExprName = exprName .. '#' .. tostring(i)
        local status, evalVal = evalSoleExpr(subexpr, fenv, rules, subExprName, false)
        if status ~= LuaExpr.Statuses.SUCCESS then
            if status:worse_than(worstStatus) then
                worstStatus = status
                worstMsg = evalVal
            end
        end
        return tostring(evalVal)
    end)
    
    return worstStatus, sub, worstMsg
end

return LuaExpr