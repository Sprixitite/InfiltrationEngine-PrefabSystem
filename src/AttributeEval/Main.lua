local GLUt = require("../Lib/GLUt")
local LuaExpr = require("../Lib/LuaExpr")
local SprixEnum = require("../Lib/EnumEngineer")
local DebbieDebug = require("../Lib/DebbieDebug")
local ObjectTag = require("../Lib/ObjectTag")
local Tags = require("./Tags")

local EvalContext = require("./EvalState")

local EvalResult = SprixEnum.new("AttributeEvalResult", {
    NO_EVAL_NEEDED = 0,
    EVAL_SUCCEEDED = 1,
    EVAL_SUCCEEDED_ARGWARN = 2,
    EVAL_FAILED    = 3,
}, {
    is_success  = function(self) return self.Value < 3  end,
    did_eval    = function(self) return self.Value ~= 0 end,
    args_good   = function(self) return self.Value < 2 end
})

local InstanceMan = require("../InstanceManager")
local ShebangFuncs = require("./ShebangFuncs")
local LuaExprFuncs = require("./LuaExprFuncs")

local warnLogger = require("../Lib/Slogger").init{
    postInit = table.freeze,
    logFunc = warn
}

local robloxWarn = warn
local warn = warnLogger.new("PrefabSystem", "AttributeEval")

local AttributeEval = {}
AttributeEval.NameInfo = require("./AttrNameInfo")
AttributeEval.TypeHandlers = require("./AttrTypeHandlers")
AttributeEval._DEBUG = true

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

function AttributeEval.EvaluateAttributeValue(attrName, attrVal, attrEvalCtx: EvalContext.EvalContext)
    local warn = warn.specialize("EvaluateAttributeValue", attrName)

    
    local isExpr, isLuaExpr, shebangContents = AttributeEval.AttributeIsExpression(attrVal)
    if not isExpr then
        return EvalResult.NO_EVAL_NEEDED, isLuaExpr
    end
    
    local isShebang = not isLuaExpr
    
    local fenv
    if isLuaExpr then
        fenv = LuaExprFuncs.CreateExprFenv(attrEvalCtx)
    else
        fenv = attrEvalCtx.ShebangFenv
    end
    
    local status, value, errmsg
    if isLuaExpr then
        status, value, errmsg = LuaExpr.Eval(attrVal, fenv, nil, attrName)
        
        local statusSuccess = status:is_success()
        local statusArgsGood = status:args_good()
        
        local retStat = nil
        if statusSuccess and statusArgsGood then
            retStat = EvalResult.EVAL_SUCCEEDED
        elseif statusSuccess then
            retStat = EvalResult.EVAL_SUCCEEDED_ARGWARN
        elseif not statusSuccess and not statusArgsGood then
            retStat = EvalResult.EVAL_FAILED
        else
            error("LuaExpr returned unsupported status code")
        end
        
        return retStat, value, errmsg
    elseif isShebang then
        local warn = warn.specialize("ShebangScript")
        
        local status, count, retVals = GLUt.str_runlua(shebangContents, fenv, attrName)
        if not status then
            return EvalResult.EVAL_FAILED, nil, count
        end

        local status = EvalResult.EVAL_SUCCEEDED
        local statusWarn = nil
        if count > 1 then
            statusWarn = "Multiple returns are not supported, will use first returned value"
            status = EvalResult.EVAL_SUCCEEDED_ARGWARN
        elseif count < 1 then
            statusWarn = "No value returned, return something to silence"
            status = EvalResult.EVAL_SUCCEEDED_ARGWARN
        end

        return status, retVals[1], statusWarn
    end

    error("Critical error in attribute evaluation - this error should be unreachable")
end

function AttributeEval.EvaluateAttribute(element, attrName, evaluationState)
    return AttributeEval.EvaluateAttributeValueOn(element, attrName, element:GetAttribute(attrName), evaluationState)
end

function AttributeEval.EvaluateAttributeValueOn(element, attrName, attrVal, evalContext: EvalContext.EvalContext)
    return AttributeEval.EvaluateAttributeValue(attrName, attrVal, evalContext)
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

local function programmableRecurse(prefab, inst, evalStates, watchForSet, pevalName)
    local programmableOutput = {}
    
    local hasEvalLimit, _, evalLimit = InstanceMan.HasAttribute(inst, "peval%.Limit$", true)
    local hasRecurse, _, mayRecurse = InstanceMan.HasAttribute(inst, "peval%.AllowRecurse$", true)
    
    if not hasRecurse or type(mayRecurse) ~= "boolean" then
        mayRecurse = false
    end
    
    if not hasEvalLimit or type(evalLimit) ~= "number" then
        evalLimit = 2000
    end

    local i = 0
    repeat
        i = i + 1
        local instClone = inst:Clone()
        instClone.Parent = inst.Parent

        local cloneEvalResults = AttributeEval.EvaluateAllRecurse(prefab, instClone, evalStates, watchForSet, mayRecurse)

        local pDone = instClone:GetAttribute(pevalName)
        instClone:SetAttribute(pevalName, nil)
        if type(pDone) ~= "boolean" then
            warn(`{inst.Parent}.{inst}`, `Malformed peval.Done expression - expected boolean, got {type(pDone)} "{pDone}" - exiting recurse eval.`)
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

    local c1Value = c1:IsA("ValueBase")
    local c2Value = c2:IsA("ValueBase")
    if c1Value == c2Value then return false end
    if c1Value then return true end
    if c2Value then return false end
    return c1.Name < c2.Name
end

local function attrValForDisplay(attrVal)
    local displayAttrVal = tostring(attrVal):gsub("\n", " ")
    if #displayAttrVal > 32 then
        displayAttrVal = displayAttrVal:sub(1, 26)
        displayAttrVal = displayAttrVal .. " (...)"
    end
    return displayAttrVal
end

function AttributeEval.EvaluateAllRecurse(
    prefab         : Folder,
    root           : Instance,
    evalStates     : { Instance: {}, Static: {}, Global: {} },
    watchForSet    : { string },
    allowRecurse   : boolean
)
    allowRecurse = GLUt.default(allowRecurse, true)
    watchForSet = GLUt.default(watchForSet, {})

    local watchDict = {}
    for _, v in ipairs(watchForSet) do
        watchDict[v] = true
    end

    local watchResults = {}
    local evalResults = InstanceMan.DeepExecute(root, function(instance)
        DebbieDebug.globj_print(instance, `Evaluating attributes:`)
        local instanceEvalCtxBase = EvalContext.newBasis(prefab, instance, evalStates)
        
        local deprecProgrammable, depProgName = InstanceMan.HasAttribute(instance, "ignore%.ProgrammableDone$", true)
        if deprecProgrammable then
            warn(`{instance.Parent.Parent}.{instance.Parent}.{instance} is using the deprecated ignore.ProgrammableDone attribute! Switch to peval.Done to silence`)
            instance:SetAttribute("peval.Done", instance:GetAttribute(depProgName))
            instance:SetAttribute(depProgName, nil)
        end

        local pevalPresent, pevalName, pevalVal = InstanceMan.HasAttribute(instance, "peval%.Done$", true)
        if allowRecurse and pevalPresent and type(pevalVal) == "string" then
            return programmableRecurse(prefab, instance, evalStates, watchForSet, pevalName)
        end

        InstanceMan.AttributeExecute(instance, function(instance, attrName, attrValue)
            if ObjectTag.tag_has(instance, Tags.EVAL_DONE) then
                DebbieDebug.warn(`{instance} is done evaluating, breaking...`)
                return InstanceMan.BREAK
            end
            
            local attrEvalCtx = instanceEvalCtxBase:attrSpecialize(attrName)
            
            local attrInfo = AttributeEval.NameInfo.GetInfo(attrName)
            if not attrInfo.ScopeInfo.ShouldEval then return end

            if attrInfo.ScopeInfo.Deprecated ~= nil then
                warn(`{instance.Parent.Parent}.{instance.Parent}.{instance}:{attrName} : Attribute type {attrInfo.Scope} is deprecated : {attrInfo.ScopeInfo.Deprecated}`)
            end

            local attrType = type(attrValue)
            local attrIsStandard = not attrInfo.ScopeInfo.IsSpecial
            local attrIsExpr
            if attrType == "string" then
                attrIsExpr = AttributeEval.AttributeIsExpression(attrValue)
            else
                attrIsExpr = false
            end
            
            if not attrIsExpr and attrIsStandard then
                DebbieDebug.globj_print(instance, `\tAttribute {attrName} [{attrValForDisplay(attrValue)}] does not require evaluation, skipping...`)
                return nil
            end
            
            local status, newValue, warnMsg
            if attrIsExpr then
                DebbieDebug.globj_print(instance, `Attribute {attrName} [{attrValForDisplay(attrValue)}] is undergoing evaluation...`)
                status, newValue, warnMsg = AttributeEval.EvaluateAttribute(instance, attrName, attrEvalCtx)
            else
                status, newValue, warnMsg = EvalResult.NO_EVAL_NEEDED, attrValue, nil
            end

            if not status:is_success() then
                warn(`Attribute evaluation of {instance.Parent}.{instance}#{attrName} failed, attribute will be discarded. Warn message is as follows:`)
                robloxWarn({warnMsg})
                instance:SetAttribute(attrName, nil)
                return nil
            end
            
            if (not status:args_good()) and attrInfo.ScopeInfo.CaresForArgs then
                warn(`Attribute evaluation of {instance.Parent}.{instance}#{attrName} succeeded, but returns were invalid. Will use first value of many, discarding if none were given`)
                robloxWarn(warnMsg)
            end

            local priorityStripped = attrInfo:NameNoPriority()
            if watchDict[priorityStripped] then
                watchResults[priorityStripped] = watchResults[priorityStripped] or {}
                watchResults[priorityStripped][instance] = newValue
            end

            DebbieDebug.globj_print(instance, `Attribute {attrName} belongs to type {attrInfo.Scope} - Handing off to appropriate handler`)
            local success, failReason = AttributeEval.TypeHandlers[attrInfo.Scope](instance, attrInfo, newValue, attrEvalCtx)
            if not success then
                warn(`\tType handler failed with {failReason}`)
            end
            
        end, AttributeEval.AttributeSort)
        
        if ObjectTag.tag_has(instance, Tags.EVAL_DONE) then
            DebbieDebug.warn(`{instance} is done evaluating, skipping...`)
            return
        end

        evalAndSetProp(instance, "Name", instanceEvalCtxBase:attrSpecialize("Name"))
        
        if not instance:IsA("StringValue") then return end
        evalAndSetProp(instance, "Value", instanceEvalCtxBase:attrSpecialize("Value"))
    end, childSort, false)

    return watchResults
end

return AttributeEval