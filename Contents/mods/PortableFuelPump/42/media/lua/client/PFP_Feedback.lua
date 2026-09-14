require "PFP_Config"

--- Shows the results PFP.Net produces as halo text above the affected player.
---
--- Two paths lead here. In single player and on a multiplayer client the timed
--- action calls PFP.Net.notify directly and it reaches Feedback.show. On a server
--- the notify is sent as a "result" command and arrives in onServerCommand.
--- Without this module PFP.Net.notify silently dropped every message, so a failed
--- battery insert or transfer looked like nothing had happened at all.

PFP = PFP or {}
PFP.Feedback = PFP.Feedback or {}

local Config = PFP.Config
local Feedback = PFP.Feedback

--- Error and stop reasons read as failures, everything else as confirmation.
--- @return boolean
local function isFailure(key)
    return string.find(key, "_Err_", 1, true) ~= nil
        or string.find(key, "_Stop_", 1, true) ~= nil
end

--- @param character IsoPlayer|nil the player to show it above, defaults to the local one
--- @param key string translation key
--- @param params table|nil array of substitution values for getText
function Feedback.show(character, key, params)
    if type(key) ~= "string" then return end

    local playerObj = character or getSpecificPlayer(0)
    if not playerObj then return end

    local text
    if type(params) == "table" and #params > 0 then
        text = getText(key, unpack(params))
    else
        text = getText(key)
    end

    if isFailure(key) then
        HaloTextHelper.addBadText(playerObj, text)
    else
        HaloTextHelper.addGoodText(playerObj, text)
    end
end

--- The server addresses each result to one player, so it always belongs to us.
function Feedback.onServerCommand(module, command, args)
    if module ~= Config.MODULE or command ~= "result" then return end
    if type(args) ~= "table" then return end

    Feedback.show(nil, args.key, args.params)
end

Events.OnServerCommand.Add(Feedback.onServerCommand)
