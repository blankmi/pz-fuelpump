require "PFP_Config"

--- Feedback channel. Results are always sent to the one affected player, never
--- broadcast. In single player the client handler is invoked directly.

PFP = PFP or {}
PFP.Net = PFP.Net or {}

--- @param character IsoPlayer the player to inform
--- @param key string translation key, e.g. "IGUI_PFP_Stop_TargetFull"
--- @param params table|nil array of substitution values for getText
function PFP.Net.notify(character, key, params)
    if not character or not key then return end

    if isServer() then
        sendServerCommand(character, PFP.Config.MODULE, "result", { key = key, params = params })
    elseif PFP.Feedback then
        PFP.Feedback.show(character, key, params)
    end
end
