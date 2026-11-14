--[[
	Nimbus UI — saving configs in a DataStore (server side)

	Put this in a Script in ServerScriptService. It creates the RemoteEvent
	"NimbusConfig" in ReplicatedStorage. The client side is RemoteConfigStore.lua.

	In Studio, turn on "Enable Studio Access to API Services" (Game Settings >
	Security), or the DataStore calls fail.

	Rules this script follows:
	  * The client is never trusted. Every argument is type-checked and
	    size-limited before it is used.
	  * A config is only stored after it parses as JSON and passes validation.
	    The server stores its own re-encoded copy, not the client's string.
	  * Requests are rate-limited per player.
	  * The DataStore is read once when the player joins and written when the
	    player leaves (and a short while after a change), not on every request.
	  * If the player's data failed to load, nothing is saved, so a DataStore
	    outage cannot overwrite existing configs with an empty list.

	Configs hold menu settings only. Never read them on the server to decide
	anything about gameplay: a player can put any value in them.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORE_NAME = "NimbusConfigs_v1"
local MAX_CONFIGS = 10 -- configs per player
local MAX_NAME_LENGTH = 32
local MAX_JSON_LENGTH = 16000 -- characters in one config
local MAX_FLAGS = 300 -- settings in one config
local MAX_KEY_LENGTH = 64
local MAX_STRING_LENGTH = 200
local MAX_TABLE_ENTRIES = 64 -- e.g. the options of a multi dropdown
local MAX_DEPTH = 3
local BUCKET_SIZE = 6 -- requests a player may send in a burst
local REFILL_PER_SECOND = 1
local SAVE_DELAY = 15 -- seconds between a change and the DataStore write
local ACTIONS = { Save = true, Load = true, List = true, Delete = true }

local store = DataStoreService:GetDataStore(STORE_NAME)

local remote = Instance.new("RemoteEvent")
remote.Name = "NimbusConfig"
remote.Parent = ReplicatedStorage

-- [Player] = { loading, loaded, configs = { [name] = json }, dirty, saveScheduled,
--              saving, tokens, lastRefill }
local sessions = {}

------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------

local function isValidName(name)
	return typeof(name) == "string"
		and #name >= 1
		and #name <= MAX_NAME_LENGTH
		and string.match(name, "^[%w _%-]+$") ~= nil
end

local function isValidString(value, maxLength)
	return #value <= maxLength and utf8.len(value) ~= nil -- DataStores reject invalid UTF-8
end

local function isValidValue(value, depth)
	local kind = type(value)
	if kind == "boolean" then
		return true
	elseif kind == "number" then
		return value == value and math.abs(value) ~= math.huge -- no NaN, no infinity
	elseif kind == "string" then
		return isValidString(value, MAX_STRING_LENGTH)
	elseif kind == "table" then
		if depth >= MAX_DEPTH then
			return false
		end
		local count = 0
		for key, item in pairs(value) do
			count += 1
			if count > MAX_TABLE_ENTRIES then
				return false
			end
			local keyKind = type(key)
			if keyKind == "string" then
				if not isValidString(key, MAX_KEY_LENGTH) then
					return false
				end
			elseif keyKind ~= "number" then
				return false
			end
			if not isValidValue(item, depth + 1) then
				return false
			end
		end
		return true
	end
	return false
end

-- Returns a clean JSON string, or nil when the config is not acceptable.
local function sanitizeConfig(json)
	if typeof(json) ~= "string" or #json > MAX_JSON_LENGTH then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(data) ~= "table" then
		return nil
	end
	local count = 0
	for flag, value in pairs(data) do
		count += 1
		if count > MAX_FLAGS then
			return nil
		end
		if type(flag) ~= "string" or not isValidString(flag, MAX_KEY_LENGTH) then
			return nil
		end
		if not isValidValue(value, 0) then
			return nil
		end
	end
	local encoded, clean = pcall(HttpService.JSONEncode, HttpService, data)
	if not encoded or #clean > MAX_JSON_LENGTH then
		return nil
	end
	return clean
end

-- Checks data read from the DataStore before it is used.
local function cleanStoredConfigs(data)
	local configs = {}
	if type(data) ~= "table" or type(data.configs) ~= "table" then
		return configs
	end
	local count = 0
	for name, json in pairs(data.configs) do
		if count < MAX_CONFIGS and isValidName(name) and type(json) == "string" and #json <= MAX_JSON_LENGTH then
			configs[name] = json
			count += 1
		end
	end
	return configs
end

------------------------------------------------------------------------
-- DataStore access
------------------------------------------------------------------------

local function keyFor(player)
	return "user_" .. player.UserId
end

-- Calls fn up to `attempts` times, waiting longer after each failure.
local function retry(attempts, fn)
	local result
	for attempt = 1, attempts do
		local ok
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < attempts then
			task.wait(2 ^ attempt)
		end
	end
	return false, result
end

local function loadSession(player)
	local session = {
		loading = true,
		loaded = false,
		configs = {},
		dirty = false,
		saveScheduled = false,
		saving = false,
		tokens = BUCKET_SIZE,
		lastRefill = os.clock(),
	}
	sessions[player] = session

	local ok, data = retry(3, function()
		return store:GetAsync(keyFor(player))
	end)
	session.loading = false
	if not ok then
		warn("[NimbusConfig] could not load configs for " .. player.Name .. ": " .. tostring(data))
		return -- stays unloaded, so nothing is saved for this player
	end
	session.configs = cleanStoredConfigs(data)
	session.loaded = true
end

local function saveSession(player, session)
	while session.saving do
		task.wait() -- let a save that is in progress finish first
	end
	if not session.loaded or not session.dirty then
		return
	end
	session.saving = true
	session.dirty = false
	local snapshot = table.clone(session.configs)
	local ok, err = retry(3, function()
		store:UpdateAsync(keyFor(player), function()
			return { version = 1, configs = snapshot }
		end)
	end)
	session.saving = false
	if not ok then
		session.dirty = true -- try again on the next change or when the player leaves
		warn("[NimbusConfig] could not save configs for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Writes to the DataStore a short while after a change. Several changes in
-- that time become one write.
local function scheduleSave(player, session)
	session.dirty = true
	if session.saveScheduled then
		return
	end
	session.saveScheduled = true
	task.delay(SAVE_DELAY, function()
		session.saveScheduled = false
		if sessions[player] == session then
			saveSession(player, session)
		end
	end)
end

------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------

local function takeToken(session)
	local now = os.clock()
	session.tokens = math.min(BUCKET_SIZE, session.tokens + (now - session.lastRefill) * REFILL_PER_SECOND)
	session.lastRefill = now
	if session.tokens < 1 then
		return false
	end
	session.tokens -= 1
	return true
end

local function countConfigs(configs)
	local count = 0
	for _ in pairs(configs) do
		count += 1
	end
	return count
end

-- Returns ok, result. `result` is the data on success or a short reason on failure.
local function handle(session, action, name, json)
	if not session.loaded then
		return false, "not loaded"
	end

	if action == "List" then
		local names = {}
		for configName in pairs(session.configs) do
			table.insert(names, configName)
		end
		table.sort(names)
		return true, names
	end

	if not isValidName(name) then
		return false, "bad name"
	end

	if action == "Load" then
		local saved = session.configs[name]
		if saved == nil then
			return false, "not found"
		end
		return true, saved
	elseif action == "Delete" then
		if session.configs[name] == nil then
			return false, "not found"
		end
		session.configs[name] = nil
		return true
	elseif action == "Save" then
		local clean = sanitizeConfig(json)
		if clean == nil then
			return false, "bad config"
		end
		if session.configs[name] == nil and countConfigs(session.configs) >= MAX_CONFIGS then
			return false, "too many configs"
		end
		session.configs[name] = clean
		return true
	end
	return false, "bad action"
end

remote.OnServerEvent:Connect(function(player, requestId, action, name, json)
	-- The request id only goes back to the same client, but check it anyway.
	if typeof(requestId) ~= "number" or requestId ~= requestId then
		return
	end
	local session = sessions[player]
	if session == nil then
		return
	end
	if typeof(action) ~= "string" or not ACTIONS[action] then
		remote:FireClient(player, requestId, false, "bad action")
		return
	end
	if not takeToken(session) then
		remote:FireClient(player, requestId, false, "too many requests")
		return
	end
	while session.loading do
		task.wait() -- the player's configs are still being read
	end
	if sessions[player] ~= session then
		return -- the player left while we waited
	end

	local ok, result = handle(session, action, name, json)
	if ok and (action == "Save" or action == "Delete") then
		scheduleSave(player, session)
	end
	remote:FireClient(player, requestId, ok, result)
end)

------------------------------------------------------------------------
-- Player lifetime
------------------------------------------------------------------------

Players.PlayerAdded:Connect(loadSession)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadSession, player)
end

Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]
	if session then
		saveSession(player, session)
		sessions[player] = nil
	end
end)

-- Save everyone when the server shuts down.
game:BindToClose(function()
	local waiting = 0
	for player, session in pairs(sessions) do
		waiting += 1
		task.spawn(function()
			saveSession(player, session)
			waiting -= 1
		end)
	end
	while waiting > 0 do
		task.wait()
	end
end)
