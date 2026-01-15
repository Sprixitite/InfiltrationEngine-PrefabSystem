local Forest = require("./Lib/Forest")
local Glut = require("./Lib/GLUt")

local InstanceManager = {}
InstanceManager.BREAK = newproxy(false)

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

    local execResult
    if multiRet then
        execResult = { exec(root, ...) }
    else
        execResult = exec(root, ...)
    end
    results.Result = execResult

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
            local result = exec(inst, attrName, attrValue)
            if result == InstanceManager.BREAK then break end
            results[attrName] = result
        else
            local result = { exec(inst, attrName, attrValue) }
            if result[1] == InstanceManager.BREAK then break end
            results[attrName] = result
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

function InstanceManager.PointInPartBounds(part, point)
    point = part.CFrame:PointToObjectSpace(point):Abs() * 0.5
    return (point.X <= part.Size.X) and (point.Y <= part.Size.Y) and (point.Z <= part.Size.Z)
end

function InstanceManager.HierarchyToTree(inst)
    local descendants = inst:GetDescendants()
    descendants[#descendants+1] = inst
    return Forest.derive_tree(descendants, function(i) return i.Parent end)
end

function InstanceManager.PathTraverse(inst, path)
    path = Glut.str_trim(path, '/')
    local pathElems = Glut.str_split(path, '/')
    
    local c = inst
    for _, pathElem in ipairs(pathElems) do
        c = c:FindFirstChild(pathElem)
        if c == nil then return nil end
    end
    
    return c
end

return InstanceManager