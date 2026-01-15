local InstanceMan = require("./InstanceManager")

local PrefabTarget = {}

function PrefabTarget.ToMissionTarget(prefabTarget, mission)
    return mission:FindFirstChild(prefabTarget.Name)
end

function PrefabTarget.UnpackToMission(prefabTarget, mission)
    local unpackingTo = PrefabTarget.ToMissionTarget(prefabTarget, mission)

    for _, c in ipairs(prefabTarget:GetChildren()) do
        c:Clone().Parent = unpackingTo
    end

    local folders = {}
    for _, c in ipairs(unpackingTo:GetChildren()) do
        if not c:IsA("Folder") then continue end
        folders[c.Name] = folders[c.Name] or {}
        local fName = folders[c.Name]
        fName[#fName+1] = c
    end

    for _, needMerge in pairs(folders) do
        InstanceMan.MergeFolders(unpack(needMerge))
    end
end

return PrefabTarget