require "PFP_Config"
require "PFP_State"
require "PFP_Compatibility"
require "PFP_Validate"
require "TimedActions/ISPFPTransferFuel"

--- Vehicle menu integration.
---
--- ISVehicleMenu.FillPartMenu builds both the context menu and the radial menu, so
--- wrapping that one function covers both. The original is always called first,
--- which keeps the mod additive and compatible with other vehicle mods.

PFP = PFP or {}
PFP.VehicleMenu = PFP.VehicleMenu or {}

local Config = PFP.Config
local Compat = PFP.Compat
local State = PFP.State
local Menu = PFP.VehicleMenu

--- Same reach vanilla uses for its own fuel entries.
local MAX_VEHICLE_DISTANCE = 4

--- "Until full or empty" is expressed as a non-positive limit.
local LIMIT_UNTIL_DONE = -1

--- Finds a usable pump in the player's main inventory.
--- @return InventoryItem|nil
function Menu.findPump(playerObj)
    local items = playerObj:getInventory():getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if State.isPump(item) and State.isOperable(item) then
            return item
        end
    end
    return nil
end

--- Queues walking to the tank access point and then the transfer itself.
function Menu.startTransfer(playerObj, pump, srcPart, dstPart, limitLitres)
    local vehicle = srcPart:getVehicle()
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, srcPart:getArea()))
    ISTimedActionQueue.add(ISPFPTransferFuel:new(playerObj, pump, srcPart, dstPart, limitLitres))
end

--- @return string label describing a target vehicle, its distance and tank level
local function targetLabel(target)
    local amount = Compat.tankAmount(target.part)
    local capacity = Compat.tankCapacity(target.part)
    return getText("ContextMenu_PFP_Target",
        target.vehicle:getScript():getName(),
        string.format("%.1f", target.distance),
        string.format("%.0f/%.0f", amount, capacity))
end

local function addAmountMenu(context, parentOption, playerObj, pump, srcPart, target)
    local amountMenu = context:getNew(context)
    context:addSubMenu(parentOption, amountMenu)

    amountMenu:addOption(getText("ContextMenu_PFP_UntilDone"),
        playerObj, Menu.startTransfer, pump, srcPart, target.part, LIMIT_UNTIL_DONE)

    for _, litres in ipairs(Config.LIMIT_PRESETS) do
        amountMenu:addOption(getText("ContextMenu_PFP_Litres", tostring(litres)),
            playerObj, Menu.startTransfer, pump, srcPart, target.part, litres)
    end
end

--- @return table targets that still have room in their tank
--- @return number how many vehicles were in range at all, full ones included
local function usableTargets(srcPart)
    local targets = {}
    local candidates = Compat.findTransferTargets(srcPart)
    for _, target in ipairs(candidates) do
        if Compat.tankCapacity(target.part) - Compat.tankAmount(target.part) > Config.EPSILON then
            table.insert(targets, target)
        end
    end
    return targets, #candidates
end

--- Adds the mod's entries to an already filled part menu.
function Menu.addEntries(playerIndex, context, slice, vehicle)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or playerObj:getVehicle() then return end
    if not vehicle or vehicle:isEngineStarted() then return end
    if playerObj:DistToProper(vehicle) >= MAX_VEHICLE_DISTANCE then return end

    local pump = Menu.findPump(playerObj)
    if not pump then return end

    local srcPart = Compat.findFuelTank(vehicle)
    if not srcPart or Compat.tankAmount(srcPart) <= Config.EPSILON then return end

    -- With no target the entry is shown greyed out rather than hidden. The tank
    -- distance is measured between the two tank access points, not the vehicle
    -- centres, so it is easy to misjudge - and an entry that simply never appears
    -- reads as a broken mod.
    local targets, candidates = usableTargets(srcPart)
    if #targets == 0 then
        if context then
            local label = candidates > 0
                and getText("ContextMenu_PFP_TransferNoRoom")
                or getText("ContextMenu_PFP_TransferTooFar",
                    string.format("%.1f", Config.get("MaxTankDistance")))
            context:addOption(label).notAvailable = true
        end
        return
    end

    if context then
        local option = context:addOption(getText("ContextMenu_PFP_Transfer"))
        local targetMenu = context:getNew(context)
        context:addSubMenu(option, targetMenu)

        for _, target in ipairs(targets) do
            local targetOption = targetMenu:addOption(targetLabel(target))
            addAmountMenu(context, targetOption, playerObj, pump, srcPart, target)
        end
    end

    if slice then
        -- The radial menu has no room for a selection, so it takes the nearest
        -- target and transfers until the source is empty or the target is full.
        local nearest = targets[1]
        slice:addSlice(getText("ContextMenu_PFP_TransferNearest"), pump:getTexture(), function()
            Menu.startTransfer(playerObj, pump, srcPart, nearest.part, LIMIT_UNTIL_DONE)
        end)
    end
end

local originalFillPartMenu = ISVehicleMenu.FillPartMenu

function ISVehicleMenu.FillPartMenu(playerIndex, context, slice, vehicle)
    local result = originalFillPartMenu(playerIndex, context, slice, vehicle)
    PFP.VehicleMenu.addEntries(playerIndex, context, slice, vehicle)
    return result
end
