require "PFP_Config"
require "PFP_State"
require "PFP_Compatibility"
require "PFP_TransferMath"

--- Shared precondition checks. The client calls them for immediate feedback, the
--- server calls them again before every authoritative step - client results are
--- never trusted.

PFP = PFP or {}
PFP.Validate = PFP.Validate or {}

local Config = PFP.Config
local Compat = PFP.Compat
local State = PFP.State
local Validate = PFP.Validate

--- Resolves the pump in the character's main inventory by item id.
--- @return InventoryItem|nil
function Validate.resolvePump(character, itemId)
    if not character then return nil end
    local item = character:getInventory():getItemWithID(itemId)
    if State.isPump(item) then return item end
    return nil
end

--- @return boolean ok, string|nil errorKey
function Validate.character(character)
    if not character or character:isDead() then return false, "IGUI_PFP_Stop_PlayerGone" end
    if character:getVehicle() then return false, "IGUI_PFP_Stop_PlayerInVehicle" end
    return true, nil
end

--- The pump must be the right item, held by this character, intact and powered.
--- @return boolean ok, string|nil errorKey
function Validate.pump(character, pump)
    if not State.isPump(pump) then return false, "IGUI_PFP_Err_NotAPump" end
    if not character:getInventory():contains(pump) then return false, "IGUI_PFP_Stop_PumpGone" end
    return State.isOperable(pump)
end

--- Both tanks must belong to different, parked, reachable vehicles.
--- @return boolean ok, string|nil errorKey
function Validate.tanks(character, srcPart, dstPart)
    if not Compat.isFuelTank(srcPart) or not Compat.isFuelTank(dstPart) then
        return false, "IGUI_PFP_Stop_NoTankAccess"
    end

    local srcVehicle, dstVehicle = srcPart:getVehicle(), dstPart:getVehicle()
    if not srcVehicle or not dstVehicle or srcVehicle == dstVehicle then
        return false, "IGUI_PFP_Stop_SameVehicle"
    end

    local ok, err = Compat.isVehicleStill(srcVehicle)
    if not ok then return false, err end
    ok, err = Compat.isVehicleStill(dstVehicle)
    if not ok then return false, err end

    ok, err = Compat.areTanksInRange(srcPart, dstPart)
    if not ok then return false, err end

    return Compat.canPlayerReachTank(character, srcPart)
end

--- Full precondition check for starting or continuing a transfer.
--- @return boolean ok, string|nil errorKey
function Validate.transfer(character, pump, srcPart, dstPart, remainingLimit)
    local ok, err = Validate.character(character)
    if not ok then return false, err end

    ok, err = Validate.pump(character, pump)
    if not ok then return false, err end

    ok, err = Validate.tanks(character, srcPart, dstPart)
    if not ok then return false, err end

    if not Config.isFinite(remainingLimit) or remainingLimit <= Config.EPSILON then
        return false, "IGUI_PFP_Stop_LimitReached"
    end

    local reason = PFP.TransferMath.exhaustionReason(Validate.buildStepInput(pump, srcPart, dstPart, remainingLimit, 0))
    if reason then return false, reason end

    return true, nil
end

--- Reads the current authoritative values into a transfer math input. Always read
--- fresh, immediately before a mutation - never reuse values from an earlier step.
--- @return table
function Validate.buildStepInput(pump, srcPart, dstPart, remainingLimit, dt)
    local state = State.get(pump)
    return {
        sourceAmount = Compat.tankAmount(srcPart),
        targetAmount = Compat.tankAmount(dstPart),
        targetCapacity = Compat.tankCapacity(dstPart),
        rate = Config.get("PumpRate"),
        dt = dt,
        remainingLimit = remainingLimit,
        chargeA = State.charge(state, "A"),
        chargeB = State.charge(state, "B"),
        litresPerBattery = Config.get("LitresPerBattery"),
        condition = pump:getCondition(),
        wearRemainder = state.wearRemainder,
        litresPerConditionPoint = Config.get("LitresPerConditionPoint"),
    }
end
