local InstanceMan = require("./InstanceManager")

local PrefabScope = require("./PrefabScope")
local PrefabTarget = require("./PrefabTarget")

local Prefab = {}

function Prefab.Instantiate(prefab, instance)
    
end

function Prefab.InstantiateStatic(prefab)
    
end

function Prefab.InstantiateRemote(prefab)
    
end

function Prefab.GetData(prefab)
    local scopeData = { INSTANCE = nil, STATIC = nil, REMOTE = nil }
    
    for scopeName, scopeFolder in pairs(PrefabScope.GetAllScopes(prefab)) do
        scopeData[scopeName] = PrefabScope.GetData(scopeFolder)
    end
    
    return {
        MainFolder = prefab,
        ScopeData  = scopeData,
    }
end

return Prefab