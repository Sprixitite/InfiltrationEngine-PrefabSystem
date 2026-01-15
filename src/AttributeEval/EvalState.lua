local Prefab = require("../Prefab")

local ShebangFuncs = require("./ShebangFuncs")
local LuaExprFuncs = require("./LuaExprFuncs")

local EvalContext = {}
EvalContext.__index = EvalContext

type EvalState = { [string] : any }

export type EvalContext = {
    AttrName: string?,
    
    PrefabData: {
        MainFolder: Folder,
        ScopeData: {
            ScopeFolder: Folder,
            Targets: { [string] : Folder },
            ScopeSettings: { Instance }
        }
    },
    
    PrefabElement: Instance,
    
    StaticState   : EvalState,
    GlobalState   : EvalState,
    RemoteState   : EvalState,
    InstanceState : EvalState,
    
    ShebangFenv : EvalState,
    
    attrSpecialize : (EvalContext, string) -> EvalContext
    
}

export type EvalStates = {
    Instance    : EvalState,
    Global      : EvalState,
    Remote      : EvalState,
    Static      : EvalState,
}

local function attrSpecialize(self, attrName)
    self.AttrName = attrName
    return self
end

function EvalContext.newBasis(prefab: Folder, prefabElement: Instance, evalVars: EvalStates) : EvalContext
    local newEvalCtx = {
        AttrName = nil,
        
        PrefabData = Prefab.GetData(prefab),
        PrefabElement = prefabElement,
        
        StaticState   = evalVars.Static,
        GlobalState   = evalVars.Global,
        RemoteState   = evalVars.Remote,
        InstanceState = evalVars.Instance,
        
        attrSpecialize = attrSpecialize,
        
        ShebangFenv = nil
    }
    newEvalCtx.ShebangFenv = ShebangFuncs.CreateShebangFenv(newEvalCtx)
    
    return newEvalCtx
end

return EvalContext