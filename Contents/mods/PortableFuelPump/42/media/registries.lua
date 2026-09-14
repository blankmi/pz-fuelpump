-- Registers the mod's own item tags. registries.lua is loaded before item scripts
-- and before any other Lua file, so tags used in PFP_Items.txt must be declared here.

PFP = PFP or {}
PFP.ItemTag = PFP.ItemTag or {}

PFP.ItemTag.FUEL_PUMP = ItemTag.register("pfp:fuelpump")
PFP.ItemTag.PUMP_ASSEMBLY = ItemTag.register("pfp:pumpassembly")

-- Base game tags the mod looks up at runtime.
PFP.ItemTag.SCREWDRIVER = ItemTag.SCREWDRIVER or ItemTag.register("base:screwdriver")
