local warnLogger = require("./Lib/Slogger").init{
    postInit = table.freeze,
    logFunc = warn
}

local warn = warnLogger.new("PrefabSystem", "PrefabScope")
local prefabTarget = require("./PrefabTarget")

local PrefabScope = {}
PrefabScope.ValidScopes = {
    STATIC   = { "Static"   },
    INSTANCE = { "Instance" },
    REMOTE   = { "Remote", "Extern", "Area" },
    DATA     = { "Data", "PrefabData" }
}

function PrefabScope.GetScope(prefab: Folder, scopeName: string)
    return prefab:FindFirstChild(scopeName)
        or prefab:FindFirstChild(scopeName:upper())
        or prefab:FindFirstChild(scopeName:lower())
end

function PrefabScope.GetScopeOfType(prefab, scopeType)
    scopeType = string.upper(scopeType)
    for _, scopeName in ipairs(PrefabScope.ValidScopes[scopeType]) do

        local folder = PrefabScope.GetScope(prefab, scopeName)
        if folder then return folder end
    end
end

function PrefabScope.GetAllScopes(prefab)
    local warn = warn.specialize("GetAllScopes")

    local scopes = {}
    for _, folder in ipairs(prefab:GetChildren()) do
        if folder.Name:lower():match("_?disabled?$") ~= nil then continue end
        local folderScope = PrefabScope.GetScopeType(folder.Name)
        if scopes[folderScope] ~= nil then
            warn(`Double-definition of scope "{folder}"`)
        end
        scopes[folderScope] = folder
    end

    return scopes
end

function PrefabScope.GetScopeType(scopeName)
    for k, validScopeNames in pairs(PrefabScope.ValidScopes) do
        for _, validName in ipairs(validScopeNames) do
            if scopeName == validName or scopeName == validName:lower() or scopeName == validName:upper() then
                return k
            end
        end
    end
    return nil
end

function PrefabScope.UnpackToMission(prefabScope, mission)
    for _, target in ipairs(prefabScope:GetChildren()) do
        if not target:IsA("Folder") then continue end
        prefabTarget.UnpackToMission(target, mission)
    end
end

function PrefabScope.GetSettingsInstance(prefabScope, instName)
    local inst = prefabScope:FindFirstChild(instName)
    if inst then
        return true, inst
    else
        return false, `Expected Group Setting "{instName}" in Group "{prefabScope.Name}", but no such Instance exists`
    end
end

function PrefabScope.GetAllSettingsInstances(prefabScope, excludeList)
    excludeList = excludeList or {}
    local excludeDict = {}

    for _, name in ipairs(excludeList) do excludeDict[name] = true end

    local found = {}
    for _, child in ipairs(prefabScope:GetChildren()) do
        if child:IsA("Folder") then continue end
        if excludeDict[child.Name] then continue end
        found[#found+1] = child
    end
    return found
end

function PrefabScope.GetData(scope)
    local targets = {}
    local scopeSettings = {}
    for _, child in ipairs(scope:GetChildren()) do
        if child:IsA("Folder") then
            targets[child.Name] = child
        else
            scopeSettings[child.Name] = child
        end
    end
    
    return {
        ScopeFolder = scope,
        Targets = targets,
        Settings = scopeSettings
    }
end

return PrefabScope