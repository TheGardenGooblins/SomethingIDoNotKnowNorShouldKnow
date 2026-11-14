--[[
	Nimbus UI — saving configs in a DataStore (client side)

	Put this in a ModuleScript named "RemoteConfigStore" in ReplicatedStorage.
	It returns a function that makes a config store. The store sends every
	request to the server through the RemoteEvent "NimbusConfig". The server
	side is ConfigStore.server.lua.

	Use it like this in your LocalScript:

		local createRemoteConfigStore = require(ReplicatedStorage.RemoteConfigStore)

		local UI = Library.new({ Title = "My Game" })
		UI:SetConfigStore(createRemoteConfigStore())

		section:ConfigManager() -- the dropdown now lists the configs in the DataStore

	After that, UI:SaveConfig, UI:LoadConfig, UI:ListConfigs and UI:DeleteConfig
	use the DataStore too. They wait for the server's answer, so call them from
	a callback or inside task.spawn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REQUEST_TIMEOUT = 10 -- seconds to wait for the server

local function createRemoteConfigStore()
	local remote = ReplicatedStorage:WaitForChild("NimbusConfig")
	local waiting = {} -- [request id] = thread that waits for the answer
	local lastId = 0

	local function finish(id, ok, result)
		local thread = waiting[id]
		if thread then
			waiting[id] = nil
			task.spawn(thread, ok, result)
		end
	end

	remote.OnClientEvent:Connect(function(id, ok, result)
		if type(id) == "number" then
			finish(id, ok == true, result)
		end
	end)

	-- Sends one request and waits for the answer. Returns ok, result.
	local function request(action, name, json)
		lastId += 1
		local id = lastId
		waiting[id] = coroutine.running()
		remote:FireServer(id, action, name, json)
		task.delay(REQUEST_TIMEOUT, finish, id, false, "timeout")
		return coroutine.yield()
	end

	return {
		Save = function(name, json)
			local ok = request("Save", name, json)
			return ok
		end,
		Load = function(name)
			local ok, json = request("Load", name)
			if ok and type(json) == "string" then
				return json
			end
			return nil
		end,
		List = function()
			local ok, names = request("List")
			if ok and type(names) == "table" then
				return names
			end
			return {}
		end,
		Delete = function(name)
			local ok = request("Delete", name)
			return ok
		end,
	}
end

return createRemoteConfigStore
