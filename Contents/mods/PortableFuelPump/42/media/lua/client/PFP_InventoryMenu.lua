require "PFP_Config"
require "PFP_State"
require "TimedActions/ISPFPBatteryAction"
require "TimedActions/ISPFPRepairPump"

--- Inventory context menu: battery handling, repair and the state tooltip.

PFP = PFP or {}
PFP.InventoryMenu = PFP.InventoryMenu or {}

local Config = PFP.Config
local State = PFP.State
local Menu = PFP.InventoryMenu

--- @return number percent charge of a battery item, rounded
local function chargePercent(charge)
    return math.floor(charge * 100 + 0.5)
end

--- Multi-line description of the pump for the tooltip.
--- @return string
function Menu.describe(item)
    local state, err = State.get(item)
    if not state then return getText(err or "IGUI_PFP_Err_UnknownSchema") end

    local lines = {}
    table.insert(lines, getText("Tooltip_PFP_Condition", tostring(item:getCondition()), tostring(item:getConditionMax())))

    for _, slotKey in ipairs(Config.SLOT_ORDER) do
        local slot = State.getSlot(state, slotKey)
        if slot then
            local suffix = ""
            if slotKey == "A" or State.charge(state, "A") <= Config.EPSILON then
                suffix = " " .. getText("Tooltip_PFP_Active")
            end
            table.insert(lines, getText("Tooltip_PFP_Battery", slotKey, tostring(chargePercent(slot.charge))) .. suffix)
        else
            table.insert(lines, getText("Tooltip_PFP_BatteryEmpty", slotKey))
        end
    end

    table.insert(lines, getText("Tooltip_PFP_Range",
        string.format("%.0f", State.estimateRangeLitres(item, state))))
    table.insert(lines, getText("Tooltip_PFP_Hoses"))

    return table.concat(lines, " <LINE> ")
end

local function addTooltip(option, item)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(item:getDisplayName())
    tooltip.description = Menu.describe(item)
    option.toolTip = tooltip
end

local function queue(playerObj, action)
    ISTimedActionQueue.add(action)
end

local function onInsertBattery(playerObj, pump, slotKey, battery)
    queue(playerObj, ISPFPBatteryAction:new(playerObj, pump, slotKey, ISPFPBatteryAction.INSERT, battery))
end

local function onRemoveBattery(playerObj, pump, slotKey)
    queue(playerObj, ISPFPBatteryAction:new(playerObj, pump, slotKey, ISPFPBatteryAction.REMOVE, nil))
end

local function onRepair(playerObj, pump)
    queue(playerObj, ISPFPRepairPump:new(playerObj, pump))
end

--- @return table array of battery items in the player's inventory
local function findBatteries(playerObj)
    local batteries = {}
    local found = playerObj:getInventory():getAllTypeRecurse(Config.BATTERY_TYPE)
    for index = 0, found:size() - 1 do
        table.insert(batteries, found:get(index))
    end
    return batteries
end

local function buildSlotOptions(context, subMenu, playerObj, pump, state, batteries)
    for _, slotKey in ipairs(Config.SLOT_ORDER) do
        local slot = State.getSlot(state, slotKey)

        if slot then
            subMenu:addOption(getText("ContextMenu_PFP_RemoveBattery", slotKey),
                playerObj, onRemoveBattery, pump, slotKey)
        elseif #batteries > 0 then
            local insertOption = subMenu:addOption(getText("ContextMenu_PFP_InsertBattery", slotKey))
            local batteryMenu = context:getNew(context)
            context:addSubMenu(insertOption, batteryMenu)

            for _, battery in ipairs(batteries) do
                local percent = chargePercent(battery:getCurrentUsesFloat())
                batteryMenu:addOption(getText("ContextMenu_PFP_BatteryChoice", tostring(percent)),
                    playerObj, onInsertBattery, pump, slotKey, battery)
            end
        else
            local option = subMenu:addOption(getText("ContextMenu_PFP_InsertBattery", slotKey))
            option.notAvailable = true
        end
    end
end

function Menu.onFillInventoryObjectContextMenu(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local seen = {}
    for _, entry in ipairs(items) do
        local item = entry
        if not instanceof(entry, "InventoryItem") then item = entry.items[1] end

        if State.isPump(item) and not seen[item:getID()] then
            seen[item:getID()] = true

            local state = State.get(item)
            local option = context:addOption(getText("ContextMenu_PFP_Pump"))
            addTooltip(option, item)

            if state then
                local subMenu = context:getNew(context)
                context:addSubMenu(option, subMenu)

                buildSlotOptions(context, subMenu, playerObj, item, state, findBatteries(playerObj))

                local canRepair = ISPFPRepairPump.canRepair(playerObj, item)
                local repairOption = subMenu:addOption(getText("ContextMenu_PFP_Repair"),
                    playerObj, onRepair, item)
                repairOption.notAvailable = not canRepair
            else
                option.notAvailable = true
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(Menu.onFillInventoryObjectContextMenu)
