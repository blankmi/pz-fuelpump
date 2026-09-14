require "PFP_Config"
require "PFP_State"
require "PFP_Validate"
require "PFP_Net"

--- Narrow entry point for client requests.
---
--- The player is taken from the authenticated connection, never from the payload.
--- References arrive as ids only and are resolved freshly here; no tank level,
--- charge, delta or duration sent by a client is ever trusted.

PFP = PFP or {}
PFP.Server = PFP.Server or {}

local Config = PFP.Config
local Server = PFP.Server

--- Minimum gap between two accepted requests of one player, in milliseconds.
local MIN_REQUEST_INTERVAL_MS = 250

--- username -> last accepted request timestamp
local lastRequestMs = {}

local function isRateLimited(player)
    local key = player:getUsername() or tostring(player:getOnlineID())
    local now = getTimestampMs()
    local previous = lastRequestMs[key]
    if previous and (now - previous) < MIN_REQUEST_INTERVAL_MS then
        return true
    end
    lastRequestMs[key] = now
    return false
end

--- Answers a client's request for the authoritative pump state, e.g. after a
--- relog when the cached tooltip may be stale.
local function onQueryPump(player, args)
    local pump = PFP.Validate.resolvePump(player, args and args.pumpId)
    if not pump then
        PFP.Net.notify(player, "IGUI_PFP_Err_NotAPump")
        return
    end
    PFP.State.get(pump)
    pump:syncItemFields()
end

local HANDLERS = {
    queryPump = onQueryPump,
}

function Server.onClientCommand(module, command, player, args)
    if module ~= Config.MODULE then return end

    local handler = HANDLERS[command]
    if not handler or not player then return end
    if isRateLimited(player) then return end

    handler(player, args)
end

--- Frees the rate limit bookkeeping of players who left, so it stays bounded.
local function pruneRateLimits()
    local players = getOnlinePlayers()
    if not players then return end

    local online = {}
    for index = 0, players:size() - 1 do
        local player = players:get(index)
        if player then online[player:getUsername() or tostring(player:getOnlineID())] = true end
    end
    for key in pairs(lastRequestMs) do
        if not online[key] then lastRequestMs[key] = nil end
    end
end

Events.OnClientCommand.Add(Server.onClientCommand)
Events.EveryTenMinutes.Add(pruneRateLimits)
