--[[
	This module is provided for convenience of consumers of the serializer API
	providing a reference implementation for correctly retrieving and validating a reference to the API table
]]

local coreGui = game:GetService("CoreGui")

type SerializerToken = string
type SerializerHook = (...any) -> nil
type SerializerHookType = "APIExtensionLoaded"|"APIExtensionUnloaded"|"PreSerialize"|"SerializerUnloaded"
type SerializerAPIExtension = { [string] : (...any) -> ...any }

export type SerializerAPI = {
	-- Generic
	GetAPIVersion 		: () -> number,
	GetCodeVersion 		: () -> number,
	GetAttributesMap 	: () -> { [string] : { [number] : any } },
	GetAttributeTypes 	: () -> { [string] : number },

	-- HookTypes
	GetHookTypes 		: () -> { [number] : string },
	IsHookTypeValid 	: (hookType: string, warnCaller: string?) -> boolean,

	-- Hooks
	AddHook 			: (hookType: SerializerHookType, registrant: string, hook: SerializerHook) -> SerializerToken,
	RemoveHook 			: (hookType: SerializerHookType, token: SerializerToken) -> nil,

	-- APIExtensions
	AddAPIExtension 	: (name: string, author: string, contents: SerializerAPIExtension) -> SerializerToken,
	GetAPIExtension		: (name: string, author: string) -> SerializerAPIExtension,
	RemoveAPIExtension	: (token: SerializerToken) -> nil
}

type AnyTbl = { [string] : any }

local APIConsumer = {}
local pluginSingleton = nil
local pluginUnloadCallback = nil

APIConsumer.ValidateArgTypes = function(fname: string, ...)
	local args = {...}
	for _, argSettings in ipairs(args) do
		local argName = argSettings[1]
		local argValue = argSettings[2]
		local argType = type(argValue)
		local argExpectedType = argSettings[3]
		if argType ~= argExpectedType then
			warn(`Invalid argument {argName} passed to API function {fname} - expected type {argExpectedType} but got {argType}!`)
			return false
		end
	end
	return true
end

-- Yields until timeOut is elapsed or API is found
APIConsumer.WaitForAPI = function(timeOut: number?) : SerializerAPI?
	timeOut = timeOut or 999_999_999_999

	local presenceIndicator = coreGui:WaitForChild("InfilEngine_SerializerAPIAvailable", timeOut)
	if not presenceIndicator then return end

	local apiTbl = shared.InfilEngine_SerializerAPI
	if not (tostring(apiTbl) == presenceIndicator.Value) then return end

	return apiTbl
end

APIConsumer.DoAPILoop = function<StateT>(
	srcname: string,
	loadedClbck: (api: SerializerAPI, state:StateT) -> nil,
	unloadedClbck: (api: SerializerAPI, state: StateT) -> nil, 
	state: StateT?
) : SerializerAPI
	state = state or {}

	if not APIConsumer.ValidateArgTypes(
		"DoAPILoop", 
		{"srcname", srcname, "string"},
		{"loadedClbck", loadedClbck, "function"},
		{"unloadedClbck", unloadedClbck, "function"},
		{"state", state, "table"}
		) then return end

	local api = APIConsumer.WaitForAPI()
	if api == nil then return APIConsumer.DoAPILoop(srcname, loadedClbck, unloadedClbck, state) end

	loadedClbck(api, state)
	api.AddHook("SerializerUnloaded", `APIConsumerFramework_{srcname}`, function()
		if pluginUnloadCallback then pluginUnloadCallback:Disconnect() pluginUnloadCallback = nil end
		unloadedClbck(api, state)
		APIConsumer.DoAPILoop(srcname, loadedClbck, unloadedClbck, state)
	end)

	pluginUnloadCallback = pluginSingleton.Unloading:Connect(function()
		pluginUnloadCallback:Disconnect()
		pluginUnloadCallback = nil
		unloadedClbck(api, state)
	end)
end

local function initAPIConsumer(callerPlugin)
	if false then return APIConsumer end -- Fixes type inference, don't ask
	if typeof(callerPlugin) ~= "Instance" then return nil end
	if callerPlugin.ClassName ~= "Plugin" then return nil end
	pluginSingleton = callerPlugin
	return APIConsumer
end

return initAPIConsumer