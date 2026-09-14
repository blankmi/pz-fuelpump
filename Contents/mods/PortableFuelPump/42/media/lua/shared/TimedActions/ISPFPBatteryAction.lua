require "TimedActions/ISBaseTimedAction"
require "PFP_Config"
require "PFP_State"
require "PFP_Net"

--- Inserts a battery into a pump slot or takes it back out.
---
--- Modelled on the vanilla ISDeviceBatteryAction: the battery item is destroyed on
--- insert and a fresh one is created on removal, so a battery has exactly one
--- authoritative home at any time - the inventory or a slot, never both.
--- All inventory changes happen in complete(), which runs on the server.

ISPFPBatteryAction = ISBaseTimedAction:derive("ISPFPBatteryAction")

local Config = PFP.Config
local State = PFP.State

ISPFPBatteryAction.INSERT = "insert"
ISPFPBatteryAction.REMOVE = "remove"

function ISPFPBatteryAction:new(character, pump, slotKey, mode, battery)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.pump = pump
    o.slotKey = slotKey
    o.mode = mode
    o.battery = battery
    o.maxTime = 60
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function ISPFPBatteryAction:isValid()
    if not State.isPump(self.pump) then return false end
    if not self.character:getInventory():contains(self.pump) then return false end
    if not State.slotField(self.slotKey) then return false end

    local state = State.get(self.pump)
    if not state then return false end

    if self.mode == ISPFPBatteryAction.INSERT then
        return self.battery ~= nil
            and self.character:getInventory():contains(self.battery)
            and State.getSlot(state, self.slotKey) == nil
    end
    return State.getSlot(state, self.slotKey) ~= nil
end

function ISPFPBatteryAction:start()
    self:setActionAnim("Loot")
end

function ISPFPBatteryAction:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function ISPFPBatteryAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISPFPBatteryAction:perform()
    -- Client side only; the inventory change happens in complete().
    ISBaseTimedAction.perform(self)
end

function ISPFPBatteryAction:complete()
    if isClient() then return true end

    local state, err = State.get(self.pump)
    if not state then
        PFP.Net.notify(self.character, err)
        return false
    end

    if self.mode == ISPFPBatteryAction.INSERT then
        return self:insertBattery(state)
    end
    return self:removeBattery(state)
end

--- Removes the battery item and stores its charge in the slot - one server pass.
function ISPFPBatteryAction:insertBattery(state)
    local inventory = self.character:getInventory()
    if not self.battery or not inventory:contains(self.battery) then
        PFP.Net.notify(self.character, "IGUI_PFP_Err_BadBattery")
        return false
    end

    local charge = self.battery:getCurrentUsesFloat()
    if not Config.isFinite(charge) then charge = 0 end

    local ok, slotErr = State.setSlot(state, self.slotKey, self.battery:getFullType(), charge)
    if not ok then
        PFP.Net.notify(self.character, slotErr)
        return false
    end

    inventory:Remove(self.battery)
    sendRemoveItemFromContainer(inventory, self.battery)
    State.updateWeight(self.pump, state)
    self.pump:syncItemFields()
    return true
end

--- Creates exactly one battery with the stored charge and empties the slot in the
--- same pass. A full inventory leaves the battery in the slot.
function ISPFPBatteryAction:removeBattery(state)
    local slot = State.getSlot(state, self.slotKey)
    if not slot then
        PFP.Net.notify(self.character, "IGUI_PFP_Err_SlotEmpty")
        return false
    end

    local battery = instanceItem(slot.batteryType)
    if not battery then
        PFP.Net.notify(self.character, "IGUI_PFP_Err_BadBattery")
        return false
    end

    local inventory = self.character:getInventory()
    if not inventory:hasRoomFor(self.character, battery) then
        PFP.Net.notify(self.character, "IGUI_PFP_Err_NoRoom")
        return false
    end

    -- Truncating loses at most one use and can never create charge, as in vanilla.
    battery:setCurrentUses(math.floor(Config.getBatteryMaxUses() * slot.charge))

    State.clearSlot(state, self.slotKey)
    State.updateWeight(self.pump, state)
    inventory:AddItem(battery)
    sendAddItemToContainer(inventory, battery)
    self.pump:syncItemFields()
    return true
end

_G[ISPFPBatteryAction.Type] = ISPFPBatteryAction
