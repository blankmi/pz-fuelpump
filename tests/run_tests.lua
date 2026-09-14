--- Unit tests for the pure transfer arithmetic (design.md 11.1).
--- Run with any Lua 5.1+ interpreter from the repository root:
---     lua tests/run_tests.lua

package.path = "Contents/mods/PortableFuelPump/42/media/lua/shared/?.lua;" .. package.path
require "PFP_TransferMath"

local Math_ = PFP.TransferMath

local failures, checks = 0, 0

local function check(condition, message)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL: " .. message)
    end
end

local function nearly(actual, expected, message, tolerance)
    check(math.abs(actual - expected) <= (tolerance or 1e-9),
        string.format("%s (got %.9f, expected %.9f)", message, actual, expected))
end

--- A valid baseline state that individual tests override.
local function input(overrides)
    local base = {
        sourceAmount = 40,
        targetAmount = 10,
        targetCapacity = 50,
        rate = 0.2,
        dt = 1,
        remainingLimit = 100000,
        chargeA = 1,
        chargeB = 1,
        litresPerBattery = 50,
        condition = 100,
        wearRemainder = 0,
        litresPerConditionPoint = 10,
    }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
end

-- Rate is the binding limit in the ordinary case.
local step = assert(Math_.computeStep(input()))
nearly(step.volume, 0.2, "rate bound volume")
check(step.limitedBy == "rate", "ordinary step is rate bound")
nearly(step.drainA, 0.2 / 50, "drain comes from slot A first")
nearly(step.drainB, 0, "slot B untouched while A has charge")
nearly(step.conditionLoss, 0, "no whole condition point after 0.2 L")
nearly(step.wearRemainder, 0.02, "wear is accumulated as a fraction")

-- Each of the six bounds can be the binding one.
step = assert(Math_.computeStep(input({ sourceAmount = 0.05 })))
nearly(step.volume, 0.05, "source bound volume")
check(step.limitedBy == "source", "source is reported as the bound")

step = assert(Math_.computeStep(input({ targetAmount = 49.9 })))
nearly(step.volume, 0.1, "target headroom bound volume")
check(step.limitedBy == "target", "target is reported as the bound")

step = assert(Math_.computeStep(input({ remainingLimit = 0.03 })))
nearly(step.volume, 0.03, "limit bound volume")
check(step.limitedBy == "limit", "limit is reported as the bound")

step = assert(Math_.computeStep(input({ chargeA = 0.001, chargeB = 0 })))
nearly(step.volume, 0.05, "battery bound volume")
check(step.limitedBy == "battery", "battery is reported as the bound")

step = assert(Math_.computeStep(input({ condition = 0.01, wearRemainder = 0 })))
nearly(step.volume, 0.1, "wear bound volume")
check(step.limitedBy == "wear", "wear is reported as the bound")

-- Slot A is drained before B, and a step may span both slots.
step = assert(Math_.computeStep(input({ chargeA = 0.002, chargeB = 1, rate = 1, dt = 1 })))
nearly(step.volume, 1, "a step may draw from both slots")
nearly(step.drainA, 0.002, "slot A is emptied first")
nearly(step.drainB, 1 / 50 - 0.002, "the remainder comes from slot B")

-- No transfer means no energy and no wear.
step = assert(Math_.computeStep(input({ sourceAmount = 0 })))
nearly(step.volume, 0, "an empty source moves nothing")
nearly(step.drainA, 0, "no drain without transfer")
nearly(step.drainB, 0, "no drain without transfer")
nearly(step.conditionLoss, 0, "no wear without transfer")
nearly(step.wearRemainder, 0, "wear remainder unchanged without transfer")

-- Whole condition points are taken off, the fraction is carried over.
step = assert(Math_.computeStep(input({ rate = 25, dt = 1, wearRemainder = 0.5 })))
nearly(step.volume, 25, "25 L in one step")
nearly(step.conditionLoss, 3, "0.5 + 2.5 points means 3 whole points")
nearly(step.wearRemainder, 0, "the carried fraction is consumed exactly", 1e-9)

-- Many small steps cost the same as one big step.
local function accumulate(steps, totalVolume)
    local state = input({ rate = totalVolume / steps, dt = 1, wearRemainder = 0, chargeA = 1, chargeB = 1,
                          sourceAmount = 1000, targetCapacity = 10000, targetAmount = 0 })
    local drained, conditionLost = 0, 0
    for _ = 1, steps do
        local result = assert(Math_.computeStep(state))
        drained = drained + result.drainA + result.drainB
        conditionLost = conditionLost + result.conditionLoss
        state.chargeA = state.chargeA - result.drainA
        state.chargeB = state.chargeB - result.drainB
        state.sourceAmount = state.sourceAmount - result.volume
        state.targetAmount = state.targetAmount + result.volume
        state.condition = state.condition - result.conditionLoss
        state.wearRemainder = result.wearRemainder
    end
    return drained, conditionLost
end

local drainedMany, conditionMany = accumulate(100, 20)
local drainedFew, conditionFew = accumulate(2, 20)
nearly(drainedMany, drainedFew, "same volume costs the same charge in any step size", 1e-9)
check(conditionMany == conditionFew, "same volume costs the same condition in any step size")

-- The worked example from design.md 6.1.
local example = input({ chargeA = 0.23, chargeB = 0.81, rate = 20, dt = 1,
                        sourceAmount = 100, targetAmount = 0, targetCapacity = 100 })
step = assert(Math_.computeStep(example))
nearly(step.volume, 20, "example transfers 20 L")
nearly(example.chargeA - step.drainA, 0, "battery A ends up empty")
nearly(example.chargeB - step.drainB, 0.64, "battery B keeps 64 percent")
nearly(step.conditionLoss, 2, "condition drops by 2 points")

-- Invalid input is rejected before anything is computed.
local rejected = {
    { sourceAmount = 0 / 0 },
    { sourceAmount = math.huge },
    { targetAmount = -1 },
    { chargeA = 1.5 },
    { wearRemainder = 1 },
    { litresPerBattery = 0 },
    { litresPerConditionPoint = 0 },
    { targetAmount = 60, targetCapacity = 50 },
    { dt = -1 },
}
for index, overrides in ipairs(rejected) do
    local result, err = Math_.computeStep(input(overrides))
    check(result == nil and err ~= nil, "invalid input " .. index .. " is rejected")
end
check(Math_.computeStep("not a table") == nil, "a non-table input is rejected")

-- Exhaustion reasons are specific.
check(Math_.exhaustionReason(input({ sourceAmount = 0 })) == "IGUI_PFP_Stop_SourceEmpty", "empty source reason")
check(Math_.exhaustionReason(input({ targetAmount = 50 })) == "IGUI_PFP_Stop_TargetFull", "full target reason")
check(Math_.exhaustionReason(input({ remainingLimit = 0 })) == "IGUI_PFP_Stop_LimitReached", "limit reason")
check(Math_.exhaustionReason(input({ chargeA = 0, chargeB = 0 })) == "IGUI_PFP_Stop_BatteriesEmpty", "flat battery reason")
check(Math_.exhaustionReason(input({ condition = 0 })) == "IGUI_PFP_Stop_PumpWornOut", "worn out reason")
check(Math_.exhaustionReason(input()) == nil, "a healthy state has no exhaustion reason")

-- plannedVolume never exceeds any single budget.
nearly(Math_.plannedVolume(input({ sourceAmount = 7 })), 7, "plan is bound by the source")
nearly(Math_.plannedVolume(input({ chargeA = 0.1, chargeB = 0 })), 5, "plan is bound by the battery")
nearly(Math_.plannedVolume(input({ remainingLimit = 3 })), 3, "plan is bound by the limit")
nearly(Math_.plannedVolume(input({ sourceAmount = -1 })), 0, "an invalid plan is zero")

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
