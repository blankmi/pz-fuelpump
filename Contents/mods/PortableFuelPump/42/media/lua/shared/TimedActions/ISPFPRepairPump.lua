require "TimedActions/ISBaseTimedAction"
require "PFP_Config"
require "PFP_State"
require "PFP_Net"

--- Repairs a pump by a fixed number of condition points.
---
--- Deliberately not a craftRecipe: a repair recipe would have to list the pump as
--- both input and output, and any mismatch there duplicates the item. A timed
--- action keeps the single pump instance - and with it its battery slots and wear
--- remainder - untouched, and consumes the parts in one authoritative pass.

ISPFPRepairPump = ISBaseTimedAction:derive("ISPFPRepairPump")

local State = PFP.State

ISPFPRepairPump.CONDITION_GAIN = 20
ISPFPRepairPump.SCRAP_TYPE = "Base.ElectronicsScrap"
ISPFPRepairPump.SCRAP_COUNT = 2
ISPFPRepairPump.TAPE_TYPE = "Base.DuctTape"
ISPFPRepairPump.TAPE_USES = 1
ISPFPRepairPump.SKILL_LEVEL = 2

function ISPFPRepairPump:new(character, pump)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.pump = pump
    o.maxTime = 300
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

--- @return table|nil scrap items, InventoryItem|nil tape
function ISPFPRepairPump.findParts(character)
    local inventory = character:getInventory()

    local scrap = {}
    local candidates = inventory:getAllTypeRecurse(ISPFPRepairPump.SCRAP_TYPE)
    for index = 0, candidates:size() - 1 do
        if #scrap < ISPFPRepairPump.SCRAP_COUNT then
            table.insert(scrap, candidates:get(index))
        end
    end
    if #scrap < ISPFPRepairPump.SCRAP_COUNT then return nil, nil end

    local tape = inventory:getFirstTypeRecurse(ISPFPRepairPump.TAPE_TYPE)
    if not tape then return nil, nil end

    return scrap, tape
end

--- @return boolean ok, string|nil errorKey
function ISPFPRepairPump.canRepair(character, pump)
    if not State.isPump(pump) then return false, "IGUI_PFP_Err_NotAPump" end
    if pump:getCondition() >= pump:getConditionMax() then return false, "IGUI_PFP_Err_NotDamaged" end
    if character:getPerkLevel(Perks.Electricity) < ISPFPRepairPump.SKILL_LEVEL then
        return false, "IGUI_PFP_Err_SkillTooLow"
    end
    if not character:getInventory():getFirstTagRecurse(PFP.ItemTag.SCREWDRIVER) then
        return false, "IGUI_PFP_Err_NoScrewdriver"
    end

    local scrap = ISPFPRepairPump.findParts(character)
    if not scrap then return false, "IGUI_PFP_Err_MissingParts" end
    return true, nil
end

function ISPFPRepairPump:isValid()
    if not self.character:getInventory():contains(self.pump) then return false end
    return (ISPFPRepairPump.canRepair(self.character, self.pump))
end

function ISPFPRepairPump:start()
    self:setActionAnim("Craft")
end

function ISPFPRepairPump:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function ISPFPRepairPump:perform()
    ISBaseTimedAction.perform(self)
end

function ISPFPRepairPump:complete()
    if isClient() then return true end

    local ok, err = ISPFPRepairPump.canRepair(self.character, self.pump)
    if not ok then
        PFP.Net.notify(self.character, err)
        return false
    end

    local scrap, tape = ISPFPRepairPump.findParts(self.character)
    if not scrap then
        PFP.Net.notify(self.character, "IGUI_PFP_Err_MissingParts")
        return false
    end

    local inventory = self.character:getInventory()
    for _, item in ipairs(scrap) do
        inventory:Remove(item)
        sendRemoveItemFromContainer(inventory, item)
    end
    tape:setCurrentUses(tape:getCurrentUses() - ISPFPRepairPump.TAPE_USES)
    if tape:getCurrentUses() <= 0 then
        inventory:Remove(tape)
        sendRemoveItemFromContainer(inventory, tape)
    else
        tape:syncItemFields()
    end

    -- The wear remainder is intentionally kept: repairing does not refund partial wear.
    local repaired = math.min(self.pump:getConditionMax(),
        self.pump:getCondition() + ISPFPRepairPump.CONDITION_GAIN)
    self.pump:setCondition(repaired)
    self.pump:syncItemFields()

    self.character:getXp():AddXP(Perks.Electricity, 10)
    PFP.Net.notify(self.character, "IGUI_PFP_Msg_Repaired", { tostring(repaired) })
    return true
end

_G[ISPFPRepairPump.Type] = ISPFPRepairPump
