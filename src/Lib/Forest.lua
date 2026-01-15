--[[
    Forest // Lua5.1 Tree Module
        Provides some basic operations for creating trees & branches
        Provides a method to derive a tree given an array of items and a function which returns any item's parent
        
        Includes breadth & depth first implementations of:
            Executing a function over every tree element
            Searching a tree for a value
            Searching a tree for the first value which - when passed into a user-provided function - returns true
    
    © Sprixitite, 2026
]]

local Forest = {}
Forest.__index = function(t, k)
    local method = Forest[k]
    local isValid = not (method == Forest.new_tree or method == Forest.new_branch or method == Forest.DepthFirst or method == Forest.BreadthFirst)
    if not isValid then return nil end
    return method
end

local function forestObjErr(fName, argNum, o)
    if not Forest.is_tree_or_branch(o) then
        error("Function Forest." .. fName .. " expected argument #" .. tostring(argNum) .. " to be a ForestTree or ForestBranch! Got " .. type(o) .. "!")
    end
end

local function forestTreeErr(fName, argNum, o)
    if not Forest.is_tree(o) then
        error("Function Forest." .. fName .. " expected argument #" .. tostring(argNum) .. " to be a ForestTree! Got " .. type(o) .. "!")
    end
end

local function forestBranchErr(fName, argNum, o)
    if not Forest.is_branch(o) then
        error("Function Forest." .. fName .. " expected argument #" .. tostring(argNum) .. " to be a ForestBranch! Got " .. type(o) .. "!")
    end
end

local _treeDB = setmetatable({}, {__mode='k'})
local function _registerTreeData(tbl)
    _treeDB[tbl] = true
end

function Forest.new_tree(data)
    local newTree = setmetatable({
        Data     = data,
        Parent   = false,
        Branches = {}
    }, Forest)
    _registerTreeData(newTree)
    
    return newTree
end

function Forest.new_branch(parent, data)
    local newBranch = Forest.new_tree(data)
    _registerTreeData(newBranch)
    
    Forest.add_branch(parent, newBranch)
    
    return newBranch
end

function Forest.add_branch(parent, branch)
    forestTreeErr("add_branch", 1, parent)
    forestObjErr("add_branch", 2, branch)
    
    branch.Parent = parent
    parent.Branches[#parent.Branches+1] = branch
end

function Forest.remove_branch(parent, branch)
    forestTreeErr("remove_branch", 1, parent)
    forestBranchErr("remove_branch", 2, branch)
    
    table.remove(
        parent.Branches,
        table.find(
            parent.Branches,
            branch
        )
    )
    branch.Parent = false
end

function Forest.to_tree(branch)
    forestBranchErr("to_tree", 1, branch)
    
    Forest.remove_branch(branch.Parent, branch)
    return branch
end

function Forest.to_branch(tree, of)
    forestTreeErr("to_branch", 1, tree)
    forestTreeErr("to_branch", 2, of)
    
    Forest.add_branch(of, tree)
    return tree
end

function Forest.derive_tree(flat, fGetParent)
    local flatDict = {}
    for _, v in ipairs(flat) do
        flatDict[v] = Forest.new_tree(v)
    end
    
    local treeHead = nil
    for _, v in ipairs(flat) do
        local vPar = fGetParent(v)
        local vBranch = flatDict[v]
        local vParBranch = flatDict[vPar]
        if vParBranch == nil and treeHead == nil then
            treeHead = vParBranch
        elseif vParBranch == nil then
            error("Forest.derive_tree: More than one valid candidate for tree root")
        else
            Forest.add_branch(vParBranch, vBranch)
        end
    end
    
    return treeHead
end

function Forest.is_tree(obj)
    if not Forest.is_tree_or_branch(obj) then return false end
    return obj.Parent == false
end

function Forest.is_branch(obj)
    if not Forest.is_tree_or_branch(obj) then return false end
    return obj.Parent ~= false
end

function Forest.is_tree_or_branch(obj)
    return _treeDB[obj] == true
end

Forest.BreadthFirst = {}

local function iter_breadth_first(branch, f, out)
    out.Data = f(branch, branch.Data)
    coroutine.yield()
    for _, subBranch in ipairs(branch.Branches) do
        iter_breadth_first(subBranch, f, Forest.new_branch(out, nil))
    end
end

function Forest.BreadthFirst.iter(tree, f)
    forestObjErr("BreadthFirst.iter", 1, tree)
    local outTree = Forest.new_tree(f(tree, tree.Data))

    local toResume = {}
    for _, branch in ipairs(tree.Branches) do
        toResume[#toResume+1] = coroutine.create(iter_breadth_first)
    end

    repeat
        local nextResume = {}
        for _, co in ipairs(toResume) do
            coroutine.resume(co, tree, f, outTree)
            if coroutine.status(co) ~= "dead" then
                nextResume[nextResume+1] = co
            end
        end
        toResume = nextResume
    until #nextResume < 1
    return outTree
end

local function funcsearch_breadth_first(tree, f)
    local found = f(tree.Data)
    if found then return tree end

    local layer = tree.Branches
    while #layer > 0 do
        local nextLayer = {}
        for _, v in ipairs(layer) do
            local found = f(v.Data)
            if found then return v end
            for _, n in ipairs(v.Branches) do
                nextLayer[#nextLayer+1] = n
            end
        end
        layer = nextLayer
    end

    return nil
end

function Forest.BreadthFirst.funcsearch(tree, f)
    forestObjErr("BreadthFirst.funcsearch", 1, tree)
    return funcsearch_breadth_first(tree, f)
end

function Forest.BreadthFirst.search(tree, v)
    forestObjErr("BreadthFirst.search", 1, tree)
    return funcsearch_breadth_first(tree, function(vcmp) return vcmp == v end)
end

Forest.DepthFirst = {}

local function iter_depth_first(tree, f, out)
    for _, branch in ipairs(tree.Branches) do
        iter_depth_first(branch, f, Forest.new_branch(out, nil))
    end

    out.Data = f(tree, tree.Data)
    return out
end

function Forest.DepthFirst.iter(tree, f)
    forestObjErr("DepthFirst.iter", 1, tree)
    return iter_depth_first(tree, f, Forest.new_tree(nil))
end

local function funcsearch_depth_first(tree, f)
    local found = f(tree.Data)
    if found then return tree end

    for _, branch in ipairs(tree.Branches) do
        local match = Forest.search_depth_first(branch, f)
        if match then return match end
    end

    return nil
end

function Forest.DepthFirst.funcsearch(tree, f)
    forestObjErr("DepthFirst.funcsearch", 1, tree)
    return funcsearch_depth_first(tree, f)
end

function Forest.DepthFirst.search(tree, v)
    forestObjErr("DepthFirst.search", 1, tree)
    return funcsearch_depth_first(tree, function(vcmp) return vcmp == v end)
end

return Forest