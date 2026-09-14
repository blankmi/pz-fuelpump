# Portable Fuel Pump

Portable Fuel Pump is a Project Zomboid Build 42 mod that adds a craftable, battery-powered pump for transferring gasoline directly between two parked vehicles. It is intended for vehicle recovery, fleet maintenance, and moving fuel without repeated canister handling.

The pump is built as a self-contained tool: its two hoses are fitted during crafting, and it holds up to two removable batteries. Fuel transfer is performed as a timed action and stops when a vehicle moves, either tank can no longer be used, the player leaves the working area, or the pump runs out of charge.

> **Development status:** pre-release. The mod targets Build 42.20 and has not yet completed in-game or dedicated-server validation. It should be treated as work in progress until that testing is complete.

## Features

- Craft a small pump assembly, then build the portable pump through the Electrical crafting menu.
- Transfer fuel between nearby, stationary vehicles.
- Fit up to two batteries; the second is used automatically when the first is depleted.
- Pump condition degrades with use and can be repaired.
- Configure transfer speed, charge consumption, wear, hookup time, and operating distances through Sandbox Options.
- Server-authoritative fuel, battery, and condition updates for multiplayer use.

## Requirements

- Project Zomboid Build 42.20 or later.
- Two vehicles with usable fuel tanks parked within the configured distance of each other, with one vehicle having fuel available to transfer.
- A charged battery installed in the pump.

## Crafting

Crafting is available from the Electrical category and requires basic Mechanics and Electrical skill.

1. Create a **Small Pump Assembly** from engine parts, wire, screws, and a screwdriver.
2. Build the **Portable Fuel Pump** from the assembly, an alarm clock, rubber hose, wire, electronics scrap, screws, duct tape, and a screwdriver.

The hoses are consumed during construction and remain part of the finished pump.

## Using the pump

1. Install one or two batteries from the pump's inventory context menu.
2. Park the source and destination vehicles within range.
3. Open a vehicle context menu and select the fuel-transfer action.
4. Remain close to the pump while it operates.

The transfer is evaluated continuously rather than as one final transaction. Each step rechecks the vehicles, tanks, distance, charge, and pump condition, preventing a stale action from overwriting a concurrent fuel change.

## Sandbox options

The `PFP` Sandbox Options page exposes the following controls:

| Option | Default | Purpose |
| --- | ---: | --- |
| Pump rate | 0.2 L/s | Fuel transfer speed |
| Hookup time | 3 s | Time before pumping begins |
| Litres per battery | 50 L | Fuel moved by one full battery charge |
| Litres per condition point | 10 L | Fuel moved for each point of pump condition |
| Max tank distance | 2 m | Maximum distance between fuel tanks |
| Max player distance | 1.5 m | How close the operator must remain |

## Multiplayer and persistence

Fuel transfer state is applied on the server in multiplayer; single-player follows the equivalent local path. The pump's installed batteries and wear state are stored on the item itself. Active transfer sessions are intentionally not restored after a server restart.

## Installation

For local development, place `Contents/mods/PortableFuelPump` in your Project Zomboid `mods` directory, enable **Portable Fuel Pump** in the Mods menu, and start or load a Build 42.20+ world. Add the mod to both server and client mod lists when testing multiplayer.

## Development

The implementation is organised under `Contents/mods/PortableFuelPump`:

```
42/media/scripts/       Items and crafting recipes
42/media/lua/shared/    State, validation, transfer logic, and timed actions
42/media/lua/client/    Vehicle and inventory menu integration
42/media/lua/server/    Server session and command handling
common/media/textures/  Item icons
```

The transfer calculations are isolated from the game API and can be run as Lua unit tests:

```sh
lua tests/run_tests.lua
```

## License and feedback

Released under the [MIT License](LICENSE). Bug reports should include the game build, whether the issue occurred in single-player or multiplayer, and the relevant console or server log.
