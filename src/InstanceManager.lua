local InstanceManager = {}

function InstanceManager.MergeFolders(...)
    local folders = { ... }
    if #folders == 1 then return folders[1] end
    local mergeInto = folders[1]
    
    for i=2, #folders do
        local folder = folders[i]
        local childFolders = {}
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Folder") then
                childFolders[#childFolders] = child
                continue
            end
            child.Parent = mergeInto
        end
        InstanceManager.MergeFolders(unpack(childFolders))
        folder:Destroy()
    end
    
    return mergeInto
end

local defaultSort = function(i1, i2) return i1.Name < i2.Name end

type ExecResult = { Result: { any }, Children: { [Instance] : ExecResult }? }
-- Execute a function recursively on an instance and its children
function InstanceManager.DeepExecute(root: Instance, exec: (Instance) -> ...any?, sortFn: (Instance, Instance) -> boolean, multiRet: boolean, ...) : ExecResult
    local results = {
        Result = nil,
        Children = {}
    }
    
    if multiRet then
        results.Result = { exec(root, ...) }
    else
        results.Result = exec(root, ...)
    end
    
    local children = root:GetChildren()
    table.sort(children, sortFn or defaultSort)
    
    for _, child in ipairs(children) do
        results.Children[child] = InstanceManager.DeepExecute(child, exec, sortFn, multiRet, ...)
    end
    
    return results
end

function InstanceManager.AttributeExecute(inst: Instance, exec: (Instance, string, any) -> ...any?, sortFn: (string, string) -> boolean, multiRet: boolean) : { [string] : { any } }
    local results = {}
    local attributes = inst:GetAttributes()
    local attributeArr = {}
    for k, _ in pairs(attributes) do
        attributeArr[#attributeArr+1] = k
    end
    
    table.sort(attributeArr, sortFn)
    for _, attrName in ipairs(attributeArr) do
        local attrValue = inst:GetAttribute(attrName)
        if not multiRet then
            results[attrName] = exec(inst, attrName, attrValue)
        else
            results[attrName] = { exec(inst, attrName, attrValue) }
        end
    end
    
    return results
end

function InstanceManager.HasAttribute(inst, needle, isPattern)
    for attrName, attrVal in pairs(inst:GetAttributes()) do
        local isHit = false
        if isPattern then
            isHit = string.match(attrName, needle)
        else
            isHit = attrName == needle
        end
        if isHit then return true, attrName, attrVal end
    end
    return false, nil, nil
end

return InstanceManager