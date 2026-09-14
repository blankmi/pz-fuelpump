require "PFP_Config"

--- Persistent pump state: the two battery slots and the sub-point wear remainder.
--- The state lives in the item's ModData and is replicated to the owner with
--- item:syncItemFields(). The pump's health stays the vanilla condition; there is
--- deliberately no second condition value in ModData.

PFP = PFP or {}
PFP.State = PFP.State or {}

local Config = PFP.Config
local State = PFP.State

State.SCHEMA_VERSION = 1
State.KEY = "PFP"

--- Battery types accepted by a slot. A stored type outside this list blocks the pump.
State.BATTERY_ALLOWLIST = { [Config.BATTERY_TYPE] = true }

--- @return boolean true if the item is a portable fuel pump
function State.isPump(item)
    return item ~= nil and item.getFullType and item:getFullType() == Config.PUMP_TYPE
end

local function clamp01(value)
    if not Config.isFinite(value) then return 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function sanitiseSlot(slot)
    if type(slot) ~= "table" then return nil end
    if not State.BATTERY_ALLOWLIST[slot.batteryType] then return nil end
    return { batteryType = slot.batteryType, charge = clamp01(slot.charge) }
end

--- Builds a fresh, empty state record.
function State.newState()
    return {
        schemaVersion = State.SCHEMA_VERSION,
        identity = nil,
        revision = 0,
        slotA = nil,
        slotB = nil,
        wearRemainder = 0,
    }
end

--- Migrates a stored record to the current schema. Repeatable and versioned.
--- Returns nil for a record from a newer, unknown schema - callers must then
--- block the pump instead of resetting it.
local function migrate(stored)
    local version = stored.schemaVersion
    if not Config.isFinite(version) then
        version = State.SCHEMA_VERSION
    end
    if version > State.SCHEMA_VERSION then
        return nil
    end
    -- No migrations yet; future steps go here, one `if version < n` block each.
    stored.schemaVersion = State.SCHEMA_VERSION
    return stored
end

--- Returns the validated state of a pump, creating it on first access.
--- @param item InventoryItem
--- @return table|nil state, string|nil errorKey
function State.get(item)
    if not State.isPump(item) then
        return nil, "IGUI_PFP_Err_NotAPump"
    end

    local modData = item:getModData()
    local stored = modData[State.KEY]
    if type(stored) ~= "table" then
        stored = State.newState()
        modData[State.KEY] = stored
        return stored, nil
    end

    stored = migrate(stored)
    if not stored then
        return nil, "IGUI_PFP_Err_UnknownSchema"
    end

    stored.slotA = sanitiseSlot(stored.slotA)
    stored.slotB = sanitiseSlot(stored.slotB)
    if not Config.isFinite(stored.wearRemainder) or stored.wearRemainder < 0 or stored.wearRemainder >= 1 then
        stored.wearRemainder = 0
    end
    if not Config.isFinite(stored.revision) or stored.revision < 0 then
        stored.revision = 0
    end
    modData[State.KEY] = stored
    return stored, nil
end

--- Assigns the server side identity once. Clients must never set it.
function State.initialise(item)
    local state = State.get(item)
    if not state then return nil end
    if not state.identity then
        state.identity = tostring(item:getID()) .. "-" .. tostring(getTimestampMs and getTimestampMs() or 0)
    end
    return state
end

local SLOT_FIELDS = { A = "slotA", B = "slotB" }

--- @return string|nil the ModData field name for a slot key
function State.slotField(slotKey)
    return SLOT_FIELDS[slotKey]
end

--- @return table|nil the battery record in that slot, or nil when the slot is empty
function State.getSlot(state, slotKey)
    local field = SLOT_FIELDS[slotKey]
    if not field or not state then return nil end
    return state[field]
end

--- Puts a battery record into a slot. Refuses to overwrite an occupied slot.
--- @return boolean ok, string|nil errorKey
function State.setSlot(state, slotKey, batteryType, charge)
    local field = SLOT_FIELDS[slotKey]
    if not field then return false, "IGUI_PFP_Err_BadSlot" end
    if state[field] then return false, "IGUI_PFP_Err_SlotOccupied" end
    if not State.BATTERY_ALLOWLIST[batteryType] then return false, "IGUI_PFP_Err_BadBattery" end

    state[field] = { batteryType = batteryType, charge = clamp01(charge) }
    state.revision = state.revision + 1
    return true, nil
end

--- Empties a slot and returns the record that was in it.
--- @return table|nil removed, string|nil errorKey
function State.clearSlot(state, slotKey)
    local field = SLOT_FIELDS[slotKey]
    if not field then return nil, "IGUI_PFP_Err_BadSlot" end
    local slot = state[field]
    if not slot then return nil, "IGUI_PFP_Err_SlotEmpty" end

    state[field] = nil
    state.revision = state.revision + 1
    return slot, nil
end

--- @return number charge of a slot in [0,1], 0 for an empty slot
function State.charge(state, slotKey)
    local slot = State.getSlot(state, slotKey)
    return slot and slot.charge or 0
end

--- @return number combined normalised charge of both slots
function State.totalCharge(state)
    return State.charge(state, "A") + State.charge(state, "B")
end

--- Applies the drain of one transfer step. Slot A is emptied before slot B.
--- @param drains table map of slot key to normalised charge to remove
function State.applyDrain(state, drains)
    for _, slotKey in ipairs(Config.SLOT_ORDER) do
        local amount = drains[slotKey]
        if amount and amount > 0 then
            local slot = State.getSlot(state, slotKey)
            if slot then
                slot.charge = clamp01(slot.charge - amount)
            end
        end
    end
    state.revision = state.revision + 1
end

--- Reflects the mass of the inserted batteries in the item weight. Batteries are
--- no longer separate items while they sit in a slot, so without this their weight
--- would silently disappear from the inventory.
function State.updateWeight(item, state)
    if not item.setCustomWeight or not item.setActualWeight then return end

    local script = item:getScriptItem()
    local baseWeight = script and script:getActualWeight() or 3.5

    local batteryWeight = 0
    for _, slotKey in ipairs(Config.SLOT_ORDER) do
        local slot = State.getSlot(state, slotKey)
        if slot then
            local batteryScript = getScriptManager():getItem(slot.batteryType)
            batteryWeight = batteryWeight + (batteryScript and batteryScript:getActualWeight() or 0.1)
        end
    end

    item:setCustomWeight(true)
    item:setActualWeight(baseWeight + batteryWeight)
end

--- @return number estimated remaining range in litres, capped by condition
function State.estimateRangeLitres(item, state)
    local litresPerBattery = Config.get("LitresPerBattery")
    local fromCharge = State.totalCharge(state) * litresPerBattery
    local fromCondition = (item:getCondition() - state.wearRemainder) * Config.get("LitresPerConditionPoint")
    return math.max(0, math.min(fromCharge, fromCondition))
end

--- Checks whether the pump may be used at all.
--- @return boolean ok, string|nil errorKey
function State.isOperable(item)
    local state, err = State.get(item)
    if not state then return false, err end
    if item:getCondition() <= 0 then return false, "IGUI_PFP_Err_Broken" end
    if State.totalCharge(state) <= Config.EPSILON then return false, "IGUI_PFP_Err_NoPower" end
    return true, nil
end
