--- Pure transfer arithmetic. No engine calls, no side effects - everything this
--- module needs is passed in, so it can be unit tested outside the game
--- (see tests/run_tests.lua).

PFP = PFP or {}
PFP.TransferMath = PFP.TransferMath or {}

local Math = PFP.TransferMath

Math.EPSILON = 1e-6

local function isFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

--- Fields that must be finite, non-negative numbers.
local REQUIRED = {
    "sourceAmount", "targetAmount", "targetCapacity", "rate", "dt", "remainingLimit",
    "chargeA", "chargeB", "litresPerBattery", "condition", "wearRemainder",
    "litresPerConditionPoint",
}

--- Validates a step input. Rejects NaN, infinity, negative values and charges
--- outside [0,1] before anything is mutated.
--- @return boolean ok, string|nil errorKey
function Math.validate(input)
    if type(input) ~= "table" then return false, "IGUI_PFP_Err_BadInput" end

    for _, field in ipairs(REQUIRED) do
        local value = input[field]
        if not isFinite(value) or value < 0 then
            return false, "IGUI_PFP_Err_BadInput"
        end
    end
    if input.chargeA > 1 or input.chargeB > 1 then return false, "IGUI_PFP_Err_BadInput" end
    if input.wearRemainder >= 1 then return false, "IGUI_PFP_Err_BadInput" end
    if input.litresPerBattery <= 0 or input.litresPerConditionPoint <= 0 then
        return false, "IGUI_PFP_Err_BadInput"
    end
    if input.targetAmount > input.targetCapacity + Math.EPSILON then
        return false, "IGUI_PFP_Err_BadInput"
    end
    return true, nil
end

--- The reason why no further fuel can be moved, or nil while the transfer may go on.
--- Checked before a step, so an exhausted resource ends the session with a
--- specific message instead of an endless zero-volume loop.
--- @return string|nil translation key
function Math.exhaustionReason(input)
    if input.sourceAmount <= Math.EPSILON then return "IGUI_PFP_Stop_SourceEmpty" end
    if input.targetCapacity - input.targetAmount <= Math.EPSILON then return "IGUI_PFP_Stop_TargetFull" end
    if input.remainingLimit <= Math.EPSILON then return "IGUI_PFP_Stop_LimitReached" end
    if input.chargeA + input.chargeB <= Math.EPSILON then return "IGUI_PFP_Stop_BatteriesEmpty" end
    if (input.condition - input.wearRemainder) * input.litresPerConditionPoint <= Math.EPSILON then
        return "IGUI_PFP_Stop_PumpWornOut"
    end
    return nil
end

--- Computes one bounded transfer step.
---
--- dV = max(0, min(rate * dt, source, capacity - target, limit, batteryBudget, wearBudget))
---
--- Battery drain is taken from slot A first, the remainder from slot B. Wear is
--- accumulated in fractions and only whole points are taken off the condition.
--- @return table|nil result, string|nil errorKey
function Math.computeStep(input)
    local ok, err = Math.validate(input)
    if not ok then return nil, err end

    local litresPerBattery = input.litresPerBattery
    local batteryBudget = (input.chargeA + input.chargeB) * litresPerBattery
    local wearBudget = (input.condition - input.wearRemainder) * input.litresPerConditionPoint
    local headroom = input.targetCapacity - input.targetAmount

    local volume = input.rate * input.dt
    local limitedBy = "rate"

    local function bound(candidate, reason)
        if candidate < volume then
            volume = candidate
            limitedBy = reason
        end
    end

    bound(input.sourceAmount, "source")
    bound(headroom, "target")
    bound(input.remainingLimit, "limit")
    bound(batteryBudget, "battery")
    bound(wearBudget, "wear")

    if volume <= Math.EPSILON then
        volume = 0
        -- Energy and wear are only ever spent on fuel that actually moved.
        return {
            volume = 0,
            drainA = 0,
            drainB = 0,
            conditionLoss = 0,
            wearRemainder = input.wearRemainder,
            limitedBy = limitedBy,
        }, nil
    end

    local energyNeeded = volume / litresPerBattery
    local drainA = math.min(input.chargeA, energyNeeded)
    local drainB = math.min(input.chargeB, energyNeeded - drainA)

    local totalWear = input.wearRemainder + volume / input.litresPerConditionPoint
    local conditionLoss = math.floor(totalWear)

    return {
        volume = volume,
        drainA = drainA,
        drainB = drainB,
        conditionLoss = conditionLoss,
        wearRemainder = totalWear - conditionLoss,
        limitedBy = limitedBy,
    }, nil
end

--- Plans the whole transfer up front. Used for the action duration and for the
--- range shown in the UI; it is an estimate, never a promise.
--- @return number litres that could be moved under the current state
function Math.plannedVolume(input)
    local ok = Math.validate(input)
    if not ok then return 0 end

    local batteryBudget = (input.chargeA + input.chargeB) * input.litresPerBattery
    local wearBudget = (input.condition - input.wearRemainder) * input.litresPerConditionPoint
    local headroom = input.targetCapacity - input.targetAmount

    local volume = input.sourceAmount
    volume = math.min(volume, headroom, input.remainingLimit, batteryBudget, wearBudget)
    if volume < 0 or volume ~= volume then return 0 end
    return volume
end
