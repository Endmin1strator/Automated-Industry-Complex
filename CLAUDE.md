# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Roblox auto-farm script ("Automated Industry Complex", aka AutoFarmV3) written in Luau. It has no build, lint or test tooling. Nothing can be run locally: the code only runs inside a Roblox client, so every change is "done but not tested in-game" until the user checks it (`TODO.md` uses `[x]` with that same meaning).

It runs in two ways (`Init.lua`):
- **Remote (executor):** `Init.lua` downloads every file in parallel from `raw.githubusercontent.com/Endmin1strator/Automated-Industry-Complex/refs/heads/main/` and `loadstring`s it. **Pushing to `main` ships the change to users.** Runtime also has a hardcoded fallback URL for `UI/Utils.lua`.
- **Local (Studio):** when `Init` is a ModuleScript, it `require`s sibling ModuleScripts in folders that mirror the repo layout.

## Module system

Every file except `UI/Utils.lua` returns a spec: `{ Name, Dependencies = {...}, IsFeature?, Start = function(Context) ... end }`. `Name` must match the file name.

- `MODULES` in `Init.lua` is the one list of files: it controls both the download and the start order. Dependencies start first. Start order also sets where each module's UI controls appear in the window.
- Whatever `Start` returns is stored as both `Context.Modules[Name]` and `Context[Name]`. A module returned with `IsFeature` goes into `Context.Features`, and `Core/Heartbeat.lua` calls its `:Update(dt)` every RunService.Heartbeat.
- After all modules have started, Init calls the optional `:BuildLateUI()` on every module (controls that must go below all the toggles), then `:Finalize()` (ProfileSettings restores the last profile here, once every control exists), then starts Heartbeat.
- `Core/Bootstrap.lua` is the composition root. It wires character respawn resets and other cross-module glue.
- `Features/AutoFarming.lua` `Feature:Update` is the main per-frame decision loop (retreat, Auto Block, waypoint route, then combat/patrol). Once the route is walked it first offers the frame to `AICFeature.SmithingStep` (AutoSmithing, also run with Auto Farm off) and then `AICFeature.MiningStep` (AutoMining); a true return means that job moved and fought this frame, and the farm's own combat is skipped.

## Shared runtime layers

`Core/Runtime.lua` creates the shared state and puts it on Context: `Services`, `Player`, `CONFIG`, `PLACE_CONFIG`, `Feature` (toggle state built from SaveConfig), `UI`/`UIRef`, and seven layer tables. Each layer is declared in Runtime and filled in by other modules:

| Layer | Filled in by |
|---|---|
| `AICConfig` | Runtime |
| `AICProfile` | ProfileManager |
| `AICCombatUtils` | Combat/CombatUtils |
| `AICCombat` | Combat/Targeting, Navigation, Combat (+ Components) |
| `AICFeature` | the Features/* modules |
| `AICUI` | UI/Components (+ some features) |
| `AICDebug` | Features/DebugVisualizer |

Rules from the code comments:
- A layer only calls *downward* in that list (Config → Profile → CombatUtils → Combat → Feature → UI → Debug).
- Mutable state goes on each layer's `.S` table (e.g. `AICCombat.S.ClosestTarget`), not in locals. Runtime.lua previously hit Luau's limit of 200 local registers per chunk and failed to compile. Keep new state on tables in large files.
- Do not rebuild PlaceConfig or the target-priority tables in other modules. ProfileManager and the zone modules already hold references to the tables Runtime made.

Much of the old monolith is still in Runtime.lua ("compatibility layer") and is being moved out feature by feature. Several small Features/* files (AutoHeal, AutoSkill, SafeCombat…) are stubs whose behavior lives in AutoFarming/Combat.

## Saved values: `Core/SaveConfig.lua`

This is the single schema for everything a profile saves. `Features` lists the toggles (`Name`, `Default`, `Key`) and `Settings` lists the settings (default, range/options, normalizers). Runtime, ProfileManager (save/load/export/reset) and Components (refresh) all read from it.

- An export `Key` must never change or be reused, or old exported profiles will load into the wrong toggle.

Adding a feature with a saved toggle (from README):
1. Create `Features/MyFeature.lua` returning the spec.
2. Add its path to `MODULES` in `Init.lua`.
3. Add `{ Name = "MyFeature", Default = false, Key = "<unused letter>" }` to `SaveConfig.Features`.
4. In `Start`, call `Context.AICUI.BindFeatureToggle("MyFeature", "My Feature", OnChanged)` and read `Context.Feature.MyFeature.Enabled`.

Waypoints, Farmzone and Deadzone are spatial modules and are not part of Profile Settings.

## UI

`UI/Utils.lua` (~5.9k lines) is the self-contained window/widget library (`Utils.new(title, opts)`, `AddTab`, `AddPriority`, loader progress…). It is loaded before any spec so the boot loader can show progress. `UI/Components.lua` binds feature toggles and shared controls to it.

## Release conventions

Every shipped change bumps the version:
- `TITLE` in `Init.lua` (`"AUTOMATED INDUSTRY COMPLEX vX.YY"`)
- the commit subject ends with `(vX.YY)`. Use conventional-commit prefixes (`feat:`/`fix:`) and a body that explains the behavior and names any new tuning constants.
- `TODO.md` (written in Thai) gets the request/bug under `## To Do` or `## To Fix` as `### [x] Area: title`, followed by a `> ทำแล้ว (vX.YY): ...` / `> แก้แล้ว (vX.YY): ...` note. Write these notes in Thai to match.

Tuning values are named UPPER_SNAKE constants near the top of the file that uses them (e.g. `RETREAT_FACE_HOLD`, `SWIM_FACE_MAX_PITCH`).

Note: README mentions a `Legacy/` folder, but it is not in the repo.
