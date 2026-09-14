require "TimedActions/ISBaseTimedAction"
require "PFP_Config"
require "PFP_State"
require "PFP_Compatibility"
require "PFP_TransferMath"
require "PFP_Validate"
require "PFP_Net"

--- Vehicle to vehicle fuel transfer.
---
--- The action lives in shared/ and is registered globally because the server
--- rebuilds it from the arguments of new(); the parameter names therefore have to
--- match the field names. All mutation happens in the authoritative path:
--- emulated animation events on a server, the client side update() tick in single
--- player. perform() never touches an object.

ISPFPTransferFuel = ISBaseTimedAction:derive("ISPFPTransferFuel")

local Config = PFP.Config
local Compat = PFP.Compat
local Math_ = PFP.TransferMath
local State = PFP.State
local Validate = PFP.Validate

--- Stand-in for "until the source is empty or the target is full".
local UNLIMITED_LITRES = 100000

function ISPFPTransferFuel:new(character, pump, srcPart, dstPart, limitLitres)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.pump = pump
    o.srcPart = srcPart
    o.dstPart = dstPart
    o.limitLitres = limitLitres

    o.srcVehicle = srcPart:getVehicle()
    o.dstVehicle = dstPart:getVehicle()
    o.transferred = 0
    o.pumpedSeconds = 0
    o.stopReason = nil
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = o:getDuration()
    return o
end

--- @return number litres that may still be moved in this session
function ISPFPTransferFuel:remainingLimit()
    local limit = self.limitLitres
    if not Config.isFinite(limit) or limit <= 0 then
        limit = UNLIMITED_LITRES
    end
    return math.max(0, limit - self.transferred)
end

--- Duration in cycles (50 = 1 second). Computed authoritatively on the server.
function ISPFPTransferFuel:getDuration()
    local input = Validate.buildStepInput(self.pump, self.srcPart, self.dstPart, self:remainingLimit(), 0)
    local planned = Math_.plannedVolume(input)
    local seconds = Config.get("HookupSeconds") + planned / Config.get("PumpRate")
    return math.max(1, math.floor(seconds * Config.CYCLES_PER_SECOND))
end

function ISPFPTransferFuel:isValid()
    if self.stopReason then return false end
    local ok = Validate.transfer(self.character, self.pump, self.srcPart, self.dstPart, self:remainingLimit())
    return ok
end

function ISPFPTransferFuel:waitToStart()
    self.character:faceThisObject(self.srcVehicle)
    return self.character:shouldBeTurning()
end

function ISPFPTransferFuel:start()
    self:setActionAnim("TakeGasFromVehicle")
    self.sound = self.character:getEmitter():playSound("CanisterAddFuelSiphon")
    self:acquireReservations()
end

--- Starts the emulated server side tick. Only called on a dedicated/hosted server.
function ISPFPTransferFuel:serverStart()
    self:acquireReservations()
    emulateAnimEvent(self.netAction, Config.SERVER_STEP_MS, "pump", nil)
end

function ISPFPTransferFuel:animEvent(event, parameter)
    if event == "pump" and isServer() then
        self:tick()
    end
end

function ISPFPTransferFuel:update()
    self.character:faceThisObject(self.srcVehicle)
    self.character:setMetabolicTarget(Metabolics.LightDomestic)

    if isClient() then return end
    if isServer() then return end
    -- Single player: no netAction, so the client tick is the authoritative path.
    self:tick()
end

function ISPFPTransferFuel:stop()
    self:cleanUp()
    -- In single player there is no serverStop(); finish() is a no-op on a client.
    self:finish()
    ISBaseTimedAction.stop(self)
end

function ISPFPTransferFuel:perform()
    -- Client side only; mutation happens in the authoritative steps.
    self:cleanUp()
    ISBaseTimedAction.perform(self)
end

--- Runs on the server when the action is cut short.
function ISPFPTransferFuel:serverStop()
    self:finish()
end

--- Runs on the server (in single player after perform). Books no extra fuel.
function ISPFPTransferFuel:complete()
    self:finish()
    return true
end

--- Elapsed action time in seconds, derived from the action's own progress.
---
--- Deliberately not the wall clock: a timed action advances with game time, so on
--- fast forward it finishes in a fraction of the real seconds its duration asks
--- for. Metering the volume by real time then books only that fraction and the
--- action completes with the source still full - which is what it used to do.
function ISPFPTransferFuel:elapsedSeconds()
    local progress = self.netAction and self.netAction:getProgress() or self:getJobDelta()
    return progress * (self.maxTime / Config.CYCLES_PER_SECOND)
end

--- One authoritative slice: book the pumping time that has passed since the last
--- tick, bounded, then transfer that much.
function ISPFPTransferFuel:tick()
    if self.stopReason then return end

    local pumpingNow = self:elapsedSeconds() - Config.get("HookupSeconds")
    if pumpingNow <= 0 then return end

    local booked = self.pumpedSeconds or 0
    local dt = pumpingNow - booked
    if dt <= 0 then return end

    -- A single step stays bounded so a stalled server cannot book one huge
    -- unvalidated transfer, but the surplus is carried to the next tick rather
    -- than dropped - discarded time would vanish out of the transfer.
    if dt > Config.MAX_STEP_SECONDS then dt = Config.MAX_STEP_SECONDS end
    self.pumpedSeconds = booked + dt

    self:transferStep(dt)
end

--- Reads the current state, validates it, computes a bounded delta and writes
--- tanks, battery charge and condition in one uninterrupted server side pass.
function ISPFPTransferFuel:transferStep(dt)
    local ok, err = Validate.transfer(self.character, self.pump, self.srcPart, self.dstPart, self:remainingLimit())
    if not ok then
        self:abort(err)
        return
    end

    local input = Validate.buildStepInput(self.pump, self.srcPart, self.dstPart, self:remainingLimit(), dt)
    local reason = Math_.exhaustionReason(input)
    if reason then
        self:abort(reason)
        return
    end

    local step, mathErr = Math_.computeStep(input)
    if not step then
        self:abort(mathErr)
        return
    end
    if step.volume <= Math_.EPSILON then return end

    local state = State.get(self.pump)
    if not state then
        self:abort("IGUI_PFP_Err_UnknownSchema")
        return
    end

    Compat.setTankAmount(self.srcPart, input.sourceAmount - step.volume)
    Compat.setTankAmount(self.dstPart, input.targetAmount + step.volume)

    State.applyDrain(state, { A = step.drainA, B = step.drainB })
    state.wearRemainder = step.wearRemainder
    if step.conditionLoss > 0 then
        self.pump:setCondition(math.max(0, self.pump:getCondition() - step.conditionLoss))
    end
    self.pump:syncItemFields()

    self.transferred = self.transferred + step.volume
end

--- Ends the session with a specific reason and tells the player why.
function ISPFPTransferFuel:abort(errorKey)
    self.stopReason = errorKey or "IGUI_PFP_Stop_Unknown"
    PFP.Net.notify(self.character, self.stopReason)

    if self.netAction then
        self.netAction:forceComplete()
    end
end

function ISPFPTransferFuel:acquireReservations()
    if isClient() or not PFP.Sessions then return end
    PFP.Sessions.acquire(self.character, self.pump, self.srcVehicle, self.dstVehicle)
end

function ISPFPTransferFuel:releaseReservations()
    if isClient() or not PFP.Sessions then return end
    PFP.Sessions.release(self.character)
end

--- Client side clean-up: sound and animation only.
function ISPFPTransferFuel:cleanUp()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
        self.sound = nil
    end
end

--- Authoritative clean-up. Replicates the confirmed state once more and frees the
--- reservations; it deliberately transfers nothing.
function ISPFPTransferFuel:finish()
    if self.finished then return end
    self.finished = true

    self:releaseReservations()
    if isClient() then return end

    self.srcVehicle:transmitPartModData(self.srcPart)
    self.dstVehicle:transmitPartModData(self.dstPart)
    self.pump:syncItemFields()

    if not self.stopReason and self.transferred > 0 then
        PFP.Net.notify(self.character, "IGUI_PFP_Stop_Done",
            { string.format("%.1f", self.transferred) })
    end
end

_G[ISPFPTransferFuel.Type] = ISPFPTransferFuel
