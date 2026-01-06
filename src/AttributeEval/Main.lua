local GLUt = require("../Lib/GLUt")
local LuaExpr = require("../Lib/LuaExpr")
local SprixEnum = require("../Lib/EnumEngineer")
local DebbieDebug = require("../Lib/DebbieDebug")

local EvalResult = SprixEnum.new("AttributeEvalResult", {
    NO_EVAL_NEEDED = 0,
    EVAL_SUCCEEDED = 1,
    EVAL_FAILED    = 2
}, {
    is_success = function(self) return self.Value < 2 end,
    did_eval   = function(self) return self.Value ~= 0 end
})

local InstanceMan = require("../InstanceManager")
local ShebangFuncs = require("../ShebangFuncs")
local LuaExprFuncs = require("../LuaExprFuncs")

local warnLogger = require("../Lib/Slogger").init{
    postInit = table.freeze,
    logFunc = warn
}

local warn = warnLogger.new("PrefabSystem", "AttributeEval")

local AttributeEval = {}
AttributeEval.NameInfo = require("./AttrNameInfo")
AttributeEval.TypeHandlers = require("./AttrTypeHandlers")
AttributeEval._DEBUG = false

function AttributeEval.AttributeSort(attrName1, attrName2)
    local attr1 = AttributeEval.NameInfo.GetInfo(attrName1)
    local attr2 = AttributeEval.NameInfo.GetInfo(attrName2)

    return attr1.Priority < attr2.Priority
end

function AttributeEval.SortedAttributes(attributes)
    local sorted = {}
    for k, v in pairs(attributes) do
        sorted[#sorted+1] = k
    end
    table.sort(sorted, AttributeEval.AttributeSort)
    return sorted
end

function AttributeEval.AttributeIsExpression(attrVal)
    local shebangContents = attrVal:match("^#!/lua%s+(.+)$")
    
    local isExpr = true
    local isShebang = shebangContents ~= nil
    local isLuaExpr = LuaExpr.IsExpr(attrVal)

    local warnMsg = nil
    if not isShebang and not isLuaExpr then
        isExpr = false
        if attrVal:match("%$%(.*%)") then
            warnMsg = "Potential expression detection failure false-negative"
        end
    end
    
    if isShebang and isLuaExpr then
        isExpr = false
        warnMsg = "Expression detection double-positive"
    end
    
    if not isExpr then
        return false, warnMsg, nil
    else
        return true, isLuaExpr, shebangContents
    end
end

function AttributeEval.EvaluateAttributeValue(attrName, attrVal, makeFenv)
    local warn = warn.specialize("EvaluateAttributeValue", attrName)

    local success, value
    
    local isExpr, isLuaExpr, shebangContents = AttributeEval.AttributeIsExpression(attrVal)
    if not isExpr then
        return EvalResult.NO_EVAL_NEEDED, isLuaExpr
    end
    
    local isShebang = not isLuaExpr

    local fenv = makeFenv(isShebang, isLuaExpr)
    if isLuaExpr then
        success, value = LuaExpr.Eval(attrVal, fenv, nil, attrName)
        if not success then
            return EvalResult.EVAL_FAILED, value
        end
        return EvalResult.EVAL_SUCCEEDED, value
    elseif isShebang then
        local warn = warn.specialize("ShebangScript")
        local success, count, retVals = GLUt.str_runlua(shebangContents, fenv, attrName)
        if not success then
            return EvalResult.EVAL_FAILED, count
        end

        if count > 1 then
            warn("Multiple returns are not supported, will use first returned value")
        elseif count < 1 then
            warn("No value returned, return something to silence")
        end

        return EvalResult.EVAL_SUCCEEDED, retVals[1]
    end

    error("Critical error in attribute evaluation - this error should be unreachable")
end

function AttributeEval.EvaluateAttributeOn(element, attrName, evaluationState)
    return AttributeEval.EvaluateAttributeValueOn(element, attrName, element:GetAttribute(attrName), evaluationState)
end

function AttributeEval.EvaluateAttributeValueOn(element, attrName, attrVal, evalState)
    local instanceState = evalState.Instance
    local staticState = evalState.Static
    local globalState = evalState.Global
    return AttributeEval.EvaluateAttributeValue(attrName, attrVal, function(isShebang, isLuaExpr) 
        if isShebang then return ShebangFuncs.CreateShebangFenv(element, attrName, instanceState, staticState, globalState)
        elseif isLuaExpr then return LuaExprFuncs.CreateExprFenv(element, attrName, instanceState, staticState, globalState)
        else
            error("Internal error: Attribute was neither a ShebangFunc or a LuaExpr")
        end
    end)
end

function AttributeEval.EvaluateProperty(on, propName, evalState)
    return AttributeEval.EvaluateAttributeValueOn(on, `{on}.{propName}`, on[propName], evalState)
end

local function evalAndSetProp(on, propName, evalState)
    local status, evalRes = AttributeEval.EvaluateProperty(on, propName, evalState)
    if not status:is_success() then
        warn(`Evaluation of {on}.{propName} "{on[propName]}" failed with {evalRes}`)
    elseif not status:did_eval() then
        if evalRes ~= nil then
            warn(`Potential false-negative in determining execution viability? {evalRes}`)
        end
    elseif type(evalRes) ~= "string" then
        warn(`{on}.{propName} \"{on[propName]}\" did not resolve to string value`)
    else
        on[propName] = evalRes
    end
end

local function programmableRecurse(inst, evalState, watchForSet, pevalName)
    local programmableOutput = {}
    
    local hasEvalLimit, _, evalLimit = InstanceMan.HasAttribute(inst, "peval%.EvalLimit$", true)
    
    if not hasEvalLimit or type(evalLimit) ~= "number" then
        evalLimit = 2000
    end

    local i = 0
    repeat
        i = i + 1
        local instClone = inst:Clone()
        instClone.Parent = inst.Parent

        local cloneEvalResults = AttributeEval.EvaluateAllRecurse(instClone, evalState, watchForSet, true)

        local pDone = instClone:GetAttribute(pevalName)
        instClone:SetAttribute(pevalName, nil)
        if type(pDone) ~= "boolean" then
            warn(`{inst.Parent}.{inst}`, `Malformed peval.Done expression - expected boolean, got {type(pDone)} - exiting recurse eval.`)
            pDone = true
        end

        if pDone then
            instClone:Destroy()
        else
            programmableOutput = GLUt.tbl_merge(programmableOutput, cloneEvalResults)
        end
    until pDone or i > evalLimit
    inst:Destroy()

    return programmableOutput
end

local function childSort(c1, c2)
    if c1.Name == "InstanceBase" then return true end
    if c2.Name == "InstanceBase" then return false end

    local c1T = c1.ClassName
    local c2T = c2.ClassName
    if c1T == c2T then return false end
    if c1T == "ValueBase" then return true end
    if c2T == "ValueBase" then return false end
    return c1.Name < c2.Name
end

function AttributeEval.EvaluateAllRecurse(
    root           : Instance,
    evalState      : { Instance: {}, Static: {}, Global: {} },
    watchForSet    : { string },
    noProgrammable : boolean
)
    watchForSet = GLUt.default(watchForSet, {})

    local watchDict = {}
    for _, v in ipairs(watchForSet) do
        watchDict[v] = true
    end

    local watchResults = {}
    local evalResults = InstanceMan.DeepExecute(root, function(instance)
        DebbieDebug.globj_print(instance, `Evaluating attributes:`)
        local deprecProgrammable, depProgName = InstanceMan.HasAttribute(instance, "ignore%.ProgrammableDone$", true)
        if deprecProgrammable then
            warn(`{instance.Parent.Parent}.{instance.Parent}.{instance} is using the deprecated ignore.ProgrammableDone attribute! Switch to peval.Done to silence`)
            instance:SetAttribute("peval.Done", instance:GetAttribute(depProgName))
            instance:SetAttribute(depProgName, nil)
        end

        local pevalPresent, pevalName, pevalVal = InstanceMan.HasAttribute(instance, "peval%.Done$", true)
        if not noProgrammable and pevalPresent and type(pevalVal) == "string" then
            return programmableRecurse(instance, evalState, watchForSet, pevalName)
        end

        InstanceMan.AttributeExecute(instance, function(instance, attrName, attrValue)
            local displayAttrVal = tostring(attrValue):gsub("\n", " ")
            if #displayAttrVal > 32 then
                displayAttrVal = displayAttrVal:sub(1, 26)
                displayAttrVal = displayAttrVal .. " (...)"
            end
            
            local attrInfo = AttributeEval.NameInfo.GetInfo(attrName)

            local attrType = type(attrValue)
            
            local attrIsStandard = not attrInfo.ScopeInfo.IsSpecial
            if attrIsStandard and (attrType ~= "string" or not AttributeEval.AttributeIsExpression(attrValue)) then
                DebbieDebug.globj_print(instance, `\tAttribute {attrName} [{displayAttrVal}] does not require evaluation, skipping...`)
                return nil
            end
            
            local success, newValue
            if attrType == "string" then
                DebbieDebug.globj_print(instance, `Attribute {attrName} [{displayAttrVal}] is undergoing evaluation...`)
                success, newValue = AttributeEval.EvaluateAttributeOn(instance, attrName, evalState)
            else
                success, newValue = true, attrValue
            end

            if not success then
                warn("\tFunction execution failed", newValue, "Attribute will be discarded")
                instance:SetAttribute(attrName, nil)
                return nil
            end

            local priorityStripped = attrInfo:NameNoPriority()
            if watchDict[priorityStripped] then
                watchResults[priorityStripped] = watchResults[priorityStripped] or {}
                watchResults[priorityStripped][instance] = newValue
            end

            DebbieDebug.globj_print(instance, `Attribute {attrName} belongs to type {attrInfo.Scope} - Handing off to appropriate handler`)
            local success, failReason = AttributeEval.TypeHandlers[attrInfo.Scope](instance, attrInfo, newValue)
            if not success then
                warn(`\tType handler failed with {failReason}`)
            end
            
        end, AttributeEval.AttributeSort)

        evalAndSetProp(instance, "Name", evalState)
        
        if not instance:IsA("StringValue") then return end
        evalAndSetProp(instance, "Value", evalState)
    end, childSort, false)

    return watchResults
end

return AttributeEval