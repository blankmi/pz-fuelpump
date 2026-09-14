print("[PFP] shared/PFP_Config.lua loaded")
--- Validated configuration for the Portable Fuel Pump.
--- Sandbox values are read lazily and clamped, so a broken or hostile sandbox file
--- can never push the transfer math into unbounded or negative territory.

PFP = PFP or {}
PFP.Config = PFP.Config or {}

local Config = PFP.Config

Config.MODULE = "PFP"
Config.PUMP_TYPE = "PFP.PortableFuelPump"
Config.BATTERY_TYPE = "Base.Battery"
Config.GASOLINE_CONTENT_TYPE = "Gasoline"

--- Slot keys in their fixed drain order: A is emptied before B.
Config.SLOT_ORDER = { "A", "B" }

--- Timed action cycles per real second (engine constant, B42).
Config.CYCLES_PER_SECOND = 50

--- Period of the emulated server side animation event, in milliseconds.
Config.SERVER_STEP_MS = 500

--- Upper bound for a single authoritative step, in seconds. Caps catch-up after a
--- stall so that a laggy server can never book one huge unvalidated transfer.
Config.MAX_STEP_SECONDS = 1.0

--- Amounts below this are treated as zero (litres, or normalised charge).
Config.EPSILON = 1e-6

--- Selectable fixed transfer limits offered in the vehicle menu, in litres.
Config.LIMIT_PRESETS = { 5, 10, 20 }

--- Defaults, overridden by sandbox-options.txt. { default, min, max }
local DEFAULTS = {
    PumpRate = { 0.2, 0.05, 5.0 },
    HookupSeconds = { 3.0, 0.0, 60.0 },
    LitresPerBattery = { 50.0, 1.0, 1000.0 },
    LitresPerConditionPoint = { 10.0, 0.5, 1000.0 },
    MaxTankDistance = { 2.0, 0.5, 10.0 },
    MaxPlayerDistance = { 1.5, 0.5, 10.0 },
}

--- Returns true for a number that is neither nil, NaN nor infinite.
function PFP.Config.isFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

--- Reads a sandbox option and clamps it into its documented range.
--- @param name string key in DEFAULTS and in SandboxVars.PFP
--- @return number
function PFP.Config.get(name)
    local spec = DEFAULTS[name]
    if not spec then
        error("PFP.Config.get: unknown option " .. tostring(name))
    end

    local value = SandboxVars and SandboxVars.PFP and SandboxVars.PFP[name]
    if not PFP.Config.isFinite(value) then
        return spec[1]
    end
    return math.max(spec[2], math.min(spec[3], value))
end

--- Maximum uses of a full battery, read from the item script with a safe fallback.
--- @return number
function PFP.Config.getBatteryMaxUses()
    local script = getScriptManager and getScriptManager():getItem(Config.BATTERY_TYPE)
    if script then
        local delta = script:getUseDelta()
        if PFP.Config.isFinite(delta) and delta > 0 then
            return math.floor(1 / delta)
        end
    end
    return 142
end
