local glut = require("../Lib/GLUt")
local InstanceMan = require("../InstanceManager")
local attrEval = require("../AttributeEval/Main")
local DebbieDebug = require("../Lib/DebbieDebug")

local warnLogger = require("../Lib/Slogger").init{
    postInit = table.freeze,
    logFunc = warn
}

local warn = warnLogger.new("PrefabSystem", "SFuncEval")

local SFUNC_PATTERN = "^%$({[^\n\r]+})$"
local SFuncEval = {}

SFuncEval.Fenv = require("./Fenv")
SFuncEval.Funcs = require("./Funcs")

local function sFuncToTable(name, attrVal)
    local warn = warn.specialize("SFuncToTable", `{name}`)
    local success, count, args = glut.str_runlua("return " .. attrVal:match(SFUNC_PATTERN), SFuncEval.Fenv.new(SFuncEval.Funcs))

    if not success then
        warn(count)
        return false, nil
    end

    local warn = warn.specialize("Internal Error")
    if count < 1 then
        warn("No args returned?")
        return false, nil
    elseif count > 1 then
        warn("Multiple args returned?")
    end

    local sfuncArgs = {}
    for i=3, #args[1] do
        sfuncArgs[#sfuncArgs+1] = args[1][i]
        args[1][i] = nil
    end
    args[1][3] = sfuncArgs

    return true, args[1]
end

function SFuncEval.SFuncToFunction(attrName, attrVal)
    local warn = warn.specialize("Eval", `"{attrName}" @ {attrVal}`)

    if not SFuncEval.IsSFunc(attrVal) then
        warn("Value is not a valid SFunc")
        return nil
    end

    local success, tbl = sFuncToTable(attrName, attrVal)
    if not success then return nil end

    return function(prefab, prefabElement)
        local success, value = pcall(tbl[2], prefab, prefabElement, unpack(tbl[3]))
        if success and typeof(value) ~= tbl[1] then return false, "Type mismatch - expected " .. tbl[1] .. " but got " .. typeof(value) end
        return success, value
    end
end

function SFuncEval.DeriveSFuncTree(treeRoot)
    local warn = warn.specialize("DeriveSFuncTree")

    local tree = InstanceMan.DeepExecute(treeRoot, InstanceMan.AttributeExecute, nil, false, function(inst, attrName, attrVal)
        if type(attrVal) ~= "string" then return end
        if SFuncEval.IsSFunc(attrVal) then
            return SFuncEval.SFuncToFunction(attrName, attrVal)
        end
    end)

    local fixTreeNames
    fixTreeNames = function(branch)
        branch.SFuncs = branch.Result or {}
        branch.Result = nil
        local newChildren = {}
        for k, v in pairs(branch.Children) do
            if newChildren[k.Name] ~= nil then
                warn(`Found duplicate SFunc branch instance {k} - remove duplicate names`)
                continue
            end

            newChildren[k.Name] = v
            fixTreeNames(v)
        end
        branch.Children = newChildren
    end
    fixTreeNames(tree)

    return tree
end

function SFuncEval.RunSFuncTree(tree, prefab, evalRoot)
    local warn = warn.specialize("RunSFuncTree")
    DebbieDebug.print(`Running SFunc tree for Prefab {prefab} on instance {evalRoot}`)

    for childName, branch in pairs(tree.Children) do
        local evalChild = evalRoot:FindFirstChild(childName)
        if evalChild == nil then
            warn(`Expected EvalTree complement {evalRoot}.{childName}, but no such instance exists`, "Skipping SFunc branch")
            continue
        end
        SFuncEval.RunSFuncTree(branch, prefab, evalChild)
    end

    for attrName, sFunc in pairs(tree.SFuncs) do
        if evalRoot:GetAttribute(attrName) ~= nil then
            DebbieDebug.print(`SFunc-Controlled attribute "{attrName}" is already-set, skipping evaluation`)
            continue
        end

        local success, result = sFunc(prefab, evalRoot)

        evalRoot:SetAttribute(attrName, nil)
        if not success then
            warn(`Evaluation of SFunc {attrName} failed`, result, "Attribute will be skipped")
            continue
        end

        local attrInfo = attrEval.NameInfo.GetInfo(attrName)
        DebbieDebug.print(`Evaluation of SFunc {evalRoot}.{attrName} succeeded`, result, `Will be assigned to {attrInfo.Target}`)
        evalRoot:SetAttribute(attrInfo.Target, result)
    end
end

function SFuncEval.IsSFunc(attrVal)
    return attrVal:match(SFUNC_PATTERN) ~= nil
end

return SFuncEval