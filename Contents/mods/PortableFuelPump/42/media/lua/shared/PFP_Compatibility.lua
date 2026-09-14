require "PFP_Config"

--- Thin adapter around the vehicle API. Everything the mod knows about tanks,
--- access areas and vehicle state goes through here, so support for vehicle mods
--- is a question of these checks passing rather than of hard coded part ids.

PFP = PFP or {}
PFP.Compat = PFP.Compat or {}

local Config = PFP.Config
local Compat = PFP.Compat

--- Vanilla detects a fuel tank by its container content type, not by the part id.
--- @return boolean
function Compat.isFuelTank(part)
    if not part then return false end
    if not part:isContainer() then return false end
    if part:getContainerContentType() ~= Config.GASOLINE_CONTENT_TYPE then return false end
    return part:getArea() ~= nil
end

--- Finds the gasoline tank of a vehicle.
--- @return VehiclePart|nil
function Compat.findFuelTank(vehicle)
    if not vehicle then return nil end

    local byId = vehicle:getPartById("GasTank")
    if Compat.isFuelTank(byId) then return byId end

    for index = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(index)
        if Compat.isFuelTank(part) then return part end
    end
    return nil
end

--- @return number current tank content in litres
function Compat.tankAmount(part)
    local amount = part:getContainerContentAmount()
    if not Config.isFinite(amount) or amount < 0 then return 0 end
    return amount
end

--- @return number tank capacity in litres, 0 when no tank item is installed
function Compat.tankCapacity(part)
    local capacity = part:getContainerCapacity()
    if not Config.isFinite(capacity) or capacity < 0 then return 0 end
    return capacity
end

--- Writes a tank level and replicates it. Only effective on the server and in
--- single player; on a client setContainerContentAmount is overwritten by the
--- next vehicle update.
function Compat.setTankAmount(part, litres)
    local vehicle = part:getVehicle()
    part:setContainerContentAmount(litres)
    vehicle:transmitPartModData(part)
end

--- World position of a tank's access area.
--- @return number|nil x, number|nil y
function Compat.areaCenter(vehicle, part)
    local center = vehicle:getAreaCenter(part:getArea())
    if not center then return nil, nil end
    return center:getX(), center:getY()
end

--- @return number|nil z level of the vehicle
local function vehicleZ(vehicle)
    local square = vehicle:getSquare()
    return square and square:getZ() or nil
end

--- Checks that a vehicle is parked, intact and not being towed.
--- @return boolean ok, string|nil errorKey
function Compat.isVehicleStill(vehicle)
    if not vehicle or vehicle:isRemovedFromWorld() then
        return false, "IGUI_PFP_Stop_VehicleGone"
    end
    if vehicle:isEngineRunning() or vehicle:isEngineStarted() then
        return false, "IGUI_PFP_Stop_EngineRunning"
    end
    if math.abs(vehicle:getCurrentSpeedKmHour()) > 0.1 then
        return false, "IGUI_PFP_Stop_VehicleMoved"
    end
    if vehicle:getVehicleTowing() or vehicle:getVehicleTowedBy() then
        return false, "IGUI_PFP_Stop_VehicleTowed"
    end
    return true, nil
end

--- Distance and level check between the two tank access points.
--- @return boolean ok, string|nil errorKey
function Compat.areTanksInRange(srcPart, dstPart)
    local srcVehicle, dstVehicle = srcPart:getVehicle(), dstPart:getVehicle()

    local sx, sy = Compat.areaCenter(srcVehicle, srcPart)
    local dx, dy = Compat.areaCenter(dstVehicle, dstPart)
    if not sx or not dx then return false, "IGUI_PFP_Stop_NoTankAccess" end

    if vehicleZ(srcVehicle) ~= vehicleZ(dstVehicle) then
        return false, "IGUI_PFP_Stop_DifferentLevel"
    end

    local distance = math.sqrt((sx - dx) * (sx - dx) + (sy - dy) * (sy - dy))
    if distance > Config.get("MaxTankDistance") then
        return false, "IGUI_PFP_Stop_TooFarApart"
    end
    return true, nil
end

--- Checks that the player stands at the source tank, outside the vehicle.
--- Mirrors the vanilla GasTank access rule and adds a distance bound.
--- @return boolean ok, string|nil errorKey
function Compat.canPlayerReachTank(character, part)
    local vehicle = part:getVehicle()
    if character:getVehicle() then return false, "IGUI_PFP_Stop_PlayerInVehicle" end

    local area = part:getArea()
    if vehicle:isInArea(area, character) then return true, nil end

    local distance = vehicle:getAreaDist(area, character)
    if Config.isFinite(distance) and distance <= Config.get("MaxPlayerDistance") then
        return true, nil
    end
    return false, "IGUI_PFP_Stop_PlayerTooFar"
end

--- Collects vehicles near the source whose tank can take fuel.
--- @return table list of { vehicle = BaseVehicle, part = VehiclePart, distance = number }
function Compat.findTransferTargets(srcPart)
    local srcVehicle = srcPart:getVehicle()
    local sx, sy = Compat.areaCenter(srcVehicle, srcPart)
    local results = {}
    if not sx then return results end

    local maxDistance = Config.get("MaxTankDistance")
    -- B42 changed IsoCell.getVehicles() to return a java.util.Set, which has no
    -- indexed access - it has to be walked with its iterator.
    local vehicles = getCell():getVehicles()
    local iterator = vehicles and vehicles:iterator()
    while iterator and iterator:hasNext() do
        local vehicle = iterator:next()
        if vehicle and vehicle ~= srcVehicle then
            local part = Compat.findFuelTank(vehicle)
            if part and Compat.tankCapacity(part) > 0 then
                local dx, dy = Compat.areaCenter(vehicle, part)
                if dx and vehicleZ(vehicle) == vehicleZ(srcVehicle) then
                    local distance = math.sqrt((sx - dx) * (sx - dx) + (sy - dy) * (sy - dy))
                    if distance <= maxDistance then
                        table.insert(results, { vehicle = vehicle, part = part, distance = distance })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.distance < b.distance end)
    return results
end
