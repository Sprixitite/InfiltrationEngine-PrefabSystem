local glut = require("../Lib/GLUt")
local exprFuncs = require("./LuaExprFuncs")
local APIConsumer = require("../Lib/APIConsumer")

local ShebangFuncs = {}

local tableCheck = function(o)
    return type(o) == "table"
end

local soundLengthCache = {}
local soundVolumeCache = {}

local function loadSound(id) : Sound?
	if type(id) == "number" then
		id = tostring(math.round(id))
	end
	if type(id) ~= "string" then return nil end

	local sound = Instance.new("Sound")
	sound.Archivable = false
	sound.SoundId = `rbxassetid://{id}`
	sound.Parent = game:GetService("CoreGui")

	local loaded = sound.IsLoaded
	local startYield = tick()
	while (not loaded) and (tick() < (startYield + 5)) do
		APIConsumer.WaitOnEvent(sound.Loaded)
		loaded = sound.IsLoaded
	end

	if not loaded then
		warn(`Sound loading for {id} timed out, are you sure you have the right ID?`)
		return nil
	end
	
	return sound
end

local soundLib
soundLib = {
	length = function(id)
		if soundLengthCache[id] ~= nil then
			return soundLengthCache[id]
		end
		
		local sound = loadSound(id)
		if sound == nil then return -1 end

		local length = sound.TimeLength
		sound:Destroy()

		if length <= 0 then
			warn(`Sound loaded but did not have TimeLength correctly set? Roblox bug?`)
			return -1
		end
		soundLengthCache[id] = length
		return length
	end,
	volumeAvg = function(id, samples)
		if soundVolumeCache[id] ~= nil then
			return soundVolumeCache[id]
		end
		
		local length = soundLib.length(id)
		if length == -1 then
			return -1
		end
		
		local sound = loadSound(id)
		if sound == nil then return -1 end
		
		local totalVolume = 0
		sound.Parent = workspace
		sound.PlaybackSpeed = length / samples
		sound.Volume = 0.5
		sound.RollOffMinDistance = math.huge
		sound.RollOffMaxDistance = math.huge
		game:GetService("SoundService"):PlayLocalSound(sound)
		for i=1, samples do
			APIConsumer.Wait()
			totalVolume = totalVolume + sound.PlaybackLoudness
		end
		sound.Volume = 0
		sound:Destroy()
		
		local avgVolume = totalVolume / samples
		if avgVolume == 0 then
			warn("Sound had average volume of 0? Bug?")
			return -1
		end
		
		soundVolumeCache[id] = avgVolume
		return avgVolume
	end,
}

ShebangFuncs.CreateShebangFenv = function(evalState)
    if not (tableCheck(evalState.InstanceState) and tableCheck(evalState.StaticState) and tableCheck(evalState.GlobalState)) then
        warn("Invalid EvalState given! Is as follows:")
        print(evalState)
        print(getmetatable(evalState))
    end
    
    local tableLib = glut.tbl_clone(table)
    local stringLib = glut.tbl_clone(string)

    stringLib.split = glut.str_split
    tableLib.getkeys = glut.tbl_getkeys

    local luaExprFuncs = setmetatable(
        {},
        {
            __index = function(tbl, k)
                return function(targs)
                    return exprFuncs[k](evalState, targs)
                end
            end,
        }
	)

    local fenvBase = {
        exprFuncs     = luaExprFuncs,
        luaExprFuncs  = luaExprFuncs,
        global        = evalState.GlobalState,
        globals       = evalState.GlobalState,
        globalState   = evalState.GlobalState,
        state         = evalState.InstanceState,
        static        = evalState.StaticState,
        staticState   = evalState.StaticState,
        glut          = glut,
        math          = math,
        table         = tableLib,
        string        = stringLib,
        CFrame        = CFrame,
        Color3        = Color3,
        Vector2       = Vector2,
        Vector3       = Vector3,
        tostring      = tostring,
        tonumber      = tonumber,
        pairs         = pairs,
        ipairs        = ipairs,
        next          = next,
		print         = print,
		warn          = warn,
		error         = error,
        unpack        = unpack,
        select        = select,
        type          = type,
		typeof        = typeof,
		task          = { wait = task.wait },
        setAttributes = function(t) for k, v in pairs(t) do evalState.PrefabElement:SetAttribute(k, v) end return true end,
        prefabInst    = evalState.PrefabRoot,
		prefabElem    = evalState.PrefabElement,
		sound = soundLib,
		stateScript = {
			lines = function(...)
				local n = select('#', ...)
				local lines = {...}
				for i=n, 1, -1 do
					if lines[i] == nil then table.remove(lines, i) end
				end
				return table.concat(lines, '\n')
			end,
			setAttributeArray = function(arrname, arr)
				evalState.PrefabElement:SetAttribute(`{arrname}_Size`, #arr)
				for i, elem in ipairs(arr) do
					local elemName = `{arrname}_{i}`
					for k, v in pairs(elem) do
						local elemValName = `{elemName}_{k}`
						evalState.PrefabElement:SetAttribute(elemValName, v)
					end
				end
			end,
			indexAttributeArray = function(arrname, elem, indexVar, setVar)
				return `*SET {setVar} #{arrname}_\{{indexVar}}_{elem}`
			end,
		}
	}
	
	local fakeGame = {}
	fenvBase.game = setmetatable(fakeGame, { __index = function() return fakeGame end })
	
	fenvBase.env = fenvBase
	fenvBase.require = function(str_or_tbl)
		if str_or_tbl == fenvBase or str_or_tbl == fakeGame then
			return fenvBase
		elseif type(str_or_tbl) == "string" then
			return exprFuncs.runScript(evalState, {str_or_tbl})
		end
		error(`ShebangFunc : Attempt made to require from "{str_or_tbl}" : Expect string`)
	end

    -- state can't overshadow builtin libraries
    setmetatable(
        fenvBase,
        { __index = evalState.InstanceState }
    )
    return fenvBase
end

function ShebangFuncs.InitDevEnv()
	if workspace:GetAttribute("PrefabSystem_NoScriptEnv") == true then return end 
	
	local anyTbl = {}
	setmetatable(anyTbl, { __index = function() return anyTbl end })
	
	local libTbl = {}
	local fakeEnv = ShebangFuncs.CreateShebangFenv(anyTbl)
	
	local fakeTypeof = function(v)
		if v == fakeEnv then return "cyclic" end
		if getmetatable(v) == libTbl then
			return "libTbl"
		end
		if v == anyTbl then return "anyTbl" end
		return typeof(v)
	end
	
	local selfFenv = getfenv(0) -- Yes we are really in this deep I KNOW WHAT I'M DOING
	
	local tableWriter = require("../Lib/TableWriter")
	tableWriter.configure{
		type = fakeTypeof,
		warn = warn,
		userdata_value_writers = {
			anyTbl = function() return "0 :: any" end,
			libTbl = function(t) return `\{} :: typeof({t.TypeName})` end,
			cyclic = function() return "self" end,
			["function"] = function(f)
				local key
				for k, v in pairs(selfFenv) do if v == f then key = k break end end
				if key then
					return `0 :: typeof({key})`
				end
				local argCount, variadic = debug.info(f, "a")
				local argStr = ""
				if variadic then
					argStr = "..."
				else
					local argNames = {}
					for i=1, argCount do
						argNames[#argNames+1] = `arg{i}: any`
					end
					argStr = table.concat(argNames, ',')
				end
				return `function({argStr}) : ...any end`
			end
		}
	}
	
	for k, v in pairs(fakeEnv) do
		if selfFenv[k] == nil then continue end
		fakeEnv[k] = setmetatable(
			{ TypeName = k },
			libTbl
		)
	end
	
	local existingDevMod = game.ReplicatedStorage:FindFirstChild("PrefabScriptEnvironment")
	if existingDevMod then
		existingDevMod:Destroy()
	end
	
	local devMod = Instance.new("ModuleScript")
	devMod.Archivable = false
	devMod.Source = "local self\nself = " .. tableWriter.write_tbl(fakeEnv) .. "\nreturn self"
	devMod.Name = "PrefabScriptEnvironment"
	devMod.Parent = game.ReplicatedStorage
end

ShebangFuncs.InitDevEnv()

return ShebangFuncs
