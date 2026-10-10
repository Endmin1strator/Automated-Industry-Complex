# AGENTS.md

Guidance for coding agents working anywhere in this repository.

## Start here

- Read [TODO.md](TODO.md) before changing behavior. It is the Thai history of requests, fixes, and regressions. `[x]` means implemented, **not verified in-game**; `[ ]` means pending.
- Read the relevant implementation and its callers, then [CLAUDE.md](CLAUDE.md) and [README.md](README.md) for supporting context. Earlier TODO entries can be superseded by later fixes under `To Fix`; reconcile them with the current code.
- Inspect `git status --short` and the relevant diff first. Preserve existing edits and untracked reference files. Reading TODO does not authorize implementing its other tasks.
- Communicate with this user in Thai. Keep TODO notes in Thai; follow the surrounding English style for code comments and identifiers.
- Keep changes focused on the requested behavior. Do not turn a small fix into a broad migration of the runtime.

## Project and execution

Automated Industry Complex (AIC / AutoFarmV3) is a Roblox client automation script written in Luau. It covers farming, combat, routes and zones, mining, smithing, party following, server tools, data browsers, and quest tools.

- [Init.lua](Init.lua) is the entry point. In executor mode it downloads `UI/Utils.lua` and the `MODULES` list in parallel, compiles with `loadstring`, and starts modules after their dependencies.
- The remote source defaults to `Endmin1strator/Automated-Industry-Complex`, branch `main`. **Pushing runtime changes to `main` distributes them to remote users.** Local edits are not exercised by an executor that still fetches `main`.
- In ModuleScript mode, Init requires descendant ModuleScripts arranged under Init in folders matching the repository. Executor-only capabilities may still be unavailable in Studio.
- [Core/Runtime.lua](Core/Runtime.lua) also has a fallback URL for `UI/Utils.lua` pointing at `main`. Account for this when testing another branch or changing remote loading.
- There is no checked-in build, dependency manager, test suite, or lint configuration. Running the game requires Roblox and the relevant game objects. Ordinary Lua is not a substitute for Luau syntax or Roblox APIs.
- README refers to `Legacy/`, which is absent. Do not assume those files exist.

## Module lifecycle

Except for the standalone `UI/Utils.lua` library, modules return a spec:

```lua
return {
    Name = "MyFeature",
    Dependencies = {"Runtime", "SaveConfig", "Components"},
    IsFeature = true,
    Start = function(Context)
        local Module = {}
        function Module:Update(dt)
            -- Optional Heartbeat work.
        end
        return Module
    end,
}
```

- Match `Name` to the file basename. Add new runtime files to `MODULES` in Init; this controls remote inclusion and preferred start order. Dependencies start first, so list the services/modules required during `Start` and avoid cycles.
- The returned object is exposed as both `Context.Modules[Name]` and `Context[Name]`.
- A spec or returned object with `IsFeature = true` joins `Context.Features`; [Core/Heartbeat.lua](Core/Heartbeat.lua) calls each object's `:Update(dt)` in order.
- After all `Start` calls, Init invokes `:BuildLateUI()`, then `:Finalize()`, then starts Heartbeat. [Features/ProfileSettings.lua](Features/ProfileSettings.lua) restores the last profile during Finalize, after the controls exist.
- [Core/Bootstrap.lua](Core/Bootstrap.lua) wires character respawn resets and cross-module setup. Add reset handling for new character-specific state where appropriate.
- AutoSmithing creates its Crafting controls in BuildLateUI because SmithingBrowser/SmithingDetail already depend on it. Preserve that separation to avoid a dependency cycle.
- Some small feature modules intentionally have empty Update methods. AutoHeal's behavior lives in AutoFarming; AutoSkill and SafeCombat bind toggles consumed by the combat code. Trace the actual owner before adding another execution loop.

## Shared state and ownership

Runtime creates `Services`, `Player`, `CONFIG`, the active `PLACE_CONFIG`, `Feature` toggle state, `UI`, `UIRef`, and these shared layers:

| Layer | Main owner |
| --- | --- |
| `AICConfig` | Core/Runtime.lua |
| `AICProfile` | Core/ProfileManager.lua |
| `AICCombatUtils` | Combat/CombatUtils.lua |
| `AICCombat` | Combat/Targeting.lua, Navigation.lua, Combat.lua |
| `AICFeature` | Features modules |
| `AICUI` | UI/Components.lua and feature UI builders |
| `AICDebug` | Features/DebugVisualizer.lua |

- Keep mutable shared state on the relevant `.S` table, or an existing module-owned state table. Large chunks have previously exceeded Luau's 200-local-register limit; avoid adding many independent locals to them.
- Respect the layer boundaries described in Runtime and the explicit module dependencies. Keep cross-module setup in Bootstrap or lifecycle hooks instead of introducing circular startup requirements.
- Resolve the active place through `Runtime:GetPlaceConfig()`. Runtime establishes shared config references before dependent modules start; do not recreate the active place/default/priority tables in Bootstrap or unrelated modules. Let ProfileManager own profile application.
- Preserve the priority component's shared table relationship with `CONFIG.TARGET_ENTITY_PRIORITY` when refreshing or loading it.

## Farming, combat, and movement

[Features/AutoFarming.lua](Features/AutoFarming.lua) is the main action coordinator. Its early exits and handoffs decide who may move or attack during a frame.

- Party hold pauses farming. With Auto Farm off, smithing may still run independently.
- Block Nearby Players is a separate global safety feature, active with Auto Block and Auto Farm off. Its step runs independently and can hold farming before normal actions; it yields to a server operation or party follow already in progress. Party must not start a reset while nearby blocking owns the frame.
- With farming active, deadzone escape and emergency skill/health retreat precede Auto Block and route work. Waypoint movement/waits precede normal combat and patrol; AutoFind can bypass the route.
- After route movement, side jobs get the frame: smithing first unless mining is committed, then mining. A successful handoff skips normal farming combat. Return to Farm Zone, Mob Gather, target combat, and patrol follow in the relevant branches.
- AutoMining requires Auto Farm. Mining and smithing use [Features/WalkController.lua](Features/WalkController.lua); combat chase uses `AICCombat.ChaseMoveTo` in [Combat/Navigation.lua](Combat/Navigation.lua). Keep their different movement policies intact.
- Mining locks WalkSpeed during claim/mining and restores it on completion, interruption, and teardown. Do not let another module overwrite that lock or interrupt a committed mine/craft.
- Keep yielding operations such as path calculation, HTTP requests, and remote invocation out of per-frame work; use asynchronous state transitions with timeouts and protection against overlapping/stale results.
- Respect farm/mine boundaries, deadzones, water rules, and the active paired farm zone in target selection and movement. Player/duel targets have distinct rules from mobs; do not replace them with a blanket mob check.
- When diagnosing idle movement, trace the `FARM STATE` label in Status and the branch producing it before changing pathfinding or patrol logic.

## Persistence and compatibility

[Core/SaveConfig.lua](Core/SaveConfig.lua) is the schema for saved toggles and settings. Runtime defaults, ProfileManager, and shared UI refresh read it.

| Storage | Purpose |
| --- | --- |
| `AutoFarmProfiles/<PlaceId>.json` | Profiles and last-used selection for that place |
| `AutoFarmProfiles/Global.json` | Global feature toggles and `GlobalSettings` |
| `AutoFarmProfiles/PinnedItems.json` | Shared pin contents, visibility, and position |
| `AutoFarmProfiles/MobDrops.json` | Cached live mob drops and AwardParams |
| `AutoFarmProfiles/QuestDump.txt` | Diagnostic dump from Copy Quest Info |

- `Features` declares toggle names, defaults, and optional compact export keys. **Never change or reuse an existing export key**, including one belonging to a global feature. `ResetOnBoostOut` remains the saved name for AutoRefill / Refill Booster.
- `Settings` declares defaults, limits, options, normalizers, and optional `Scope = "Place"`. Put new saved values in the schema instead of duplicating save/load/refresh lists elsewhere.
- `Global = true` features and `GlobalSettings` are excluded from profile save/load/export. Current global toggles include DangerGroupHop, AutoStartGame, WhitelistSkipsSafety, FpsBoost, AutoMinimize, and BlockNearbyPlayers. Nearby block distance, Block Whitelist, danger IDs/whitelist, font, text scale, theme, and minimized state are also global. Global numeric sliders use `AICUI.AddGlobalSettingSlider`, which writes the global store.
- `PINNED_STATE` uses its dedicated file and older migration path. It is not stored through GlobalSettings.
- Preserve [Core/ProfileManager.lua](Core/ProfileManager.lua)'s migrations and default fallback behavior. Block Whitelist migration merges profiles of the initially opened PlaceId; it does not scan every place. WhitelistSkipsSafety migrates from that place's last-used profile.
- Spatial data is serialized through the place config. Keep `WAYPOINTS`, `WAYPOINT_WAITS`, `WAYPOINT_JUMPS`, and `WAYPOINT_ZONES` aligned during reorder/removal. Remap waypoint zone references when farm zones change. Keep saved vectors rounded to two decimals with the existing helpers.
- Use existing profile/global/pinned save functions and debounce helpers. Teardown flushes pending profile/pin saves and closes storage, preventing an old run from saving over a new one.

To add a saved feature: create its spec, add the path in Init, declare its toggle in SaveConfig, and bind it with `Context.AICUI.BindFeatureToggle`. Use `AICUI.AddSettingSlider` for supported numeric profile settings so profile loading refreshes the slider. Add the control description as well.

## UI conventions

- [UI/Utils.lua](UI/Utils.lua) owns windows and widgets. [UI/Components.lua](UI/Components.lua) binds schema values and shared controls; [UI/Descriptions.lua](UI/Descriptions.lua) maps control labels to descriptions.
- Main-window X, minimize, and Auto Minimize share the corner reopen button and global `UI_MINIMIZED` state. Reopening restores the full window at its previous size/position; preserve the visibility token that cancels stale hide callbacks.
- Floating windows use [UI/Floating.lua](UI/Floating.lua). Mob/Asset browsers share [UI/BrowserShell.lua](UI/BrowserShell.lua) and [UI/DetailKit.lua](UI/DetailKit.lua). Reuse these before making another widget/window system.
- Programmatic refresh must use `Set(value, false)` where supported to suppress callbacks. Triggering saves during refresh previously caused endless profile/dropdown rebuilding.
- For dynamic dropdowns, compare option signatures and defer rebuilding while open. Use `AICUI.RefreshDropdown` where suitable, or `AICUI.ReplaceDropdown` to retain the old LayoutOrder and destroy the old component correctly.
- Preserve dropdown connection cleanup, selection scrolling, UI scale handling, and mouse/touch behavior. Outside-click handling uses GUI input events; raw mouse coordinates versus AbsolutePosition previously made the last option unclickable.
- Popup surfaces must consume clicks so they do not activate controls underneath. Font/text scale must apply to new controls and floating/debug roots, preserve weights, and scale from the original text size rather than repeatedly rounded sizes.
- Use [Core/GuiClick.lua](Core/GuiClick.lua) for shared executor click methods where applicable; preserve each game control's required signals and completion checks.

## Lifecycle and re-execution

Init keeps the active run in `getgenv().AICSession`. `Context.Lifetime.Destroy()` marks it inactive, runs cleanup callbacks in reverse registration order, and disconnects tracked connections before another run proceeds.

- Use `Context.Connect(Signal, Callback)` for long-lived player/workspace/input/remote signals.
- Module-managed watchers that are rebound manually can use plain `:Connect`, but register an `OnEnd` cleanup and use `Context.Lifetime.Disconnect` for them. UI-owned connections must be destroyed with their controls.
- Persistent loops must check `Context.Lifetime.Alive`; asynchronous results must not resume actions after teardown or after the operation they belong to has changed.
- Register external instances, render-step bindings, movement locks, and changed game properties for cleanup. Restore WalkSpeed, AutoRotate, orientation constraints, and FPS Boost changes as applicable.
- Preserve the guard against starting alongside an older run that cannot be stopped; those sessions require a rejoin.

## Behavior to preserve from TODO

These are current behavior constraints, not a request to implement the original TODO descriptions again:

- **Party:** while the leader is present, continue farming even with strangers. Follow only when the leader leaves: reset, hold, send the game's teleport chat command, retry up to three times, then cool down. Party handles intruders except during failed-follow cooldown.
- **Waypoint Loop:** take over at the first paired waypoint; stay within the first/last paired range. Select worthwhile zones by walking distance along the route, visible targets, remembered empty zones, and RespawnTimers. When targets are dead, wait for the soonest respawn instead of repeatedly sweeping the whole route. Streaming limits what the client can see.
- **Auto Block:** never prompt a Block Whitelist player. Wait for a settled block before hopping, with the timeout escape added in the v3.22 working tree. With WhitelistSkipsSafety off, an already-blocked whitelist player can still cause a hop after Block Delay.
- **Nearby blocking:** uses the Block Whitelist regardless of WhitelistSkipsSafety. Trigger on a streamed character's 3D distance (default 1,000 studs); cancel pending blocking if they leave range/the server, become whitelisted, or the toggle is disabled. Its automatic confirmation does not change the older Auto Confirm Block toggle. Preserve settled-block checks, bounded retries, and stale-task cancellation.
- **Danger groups:** Danger Whitelist is separate; Block Whitelist also exempts players when WhitelistSkipsSafety is on. Hop attempts recover once no active danger threats remain. Do not confuse a vanished threat with a successful teleport or repeatedly return to the same server.
- **Combat:** Safe Combat off uses close positioning; skill avoidance and low-health retreat remain separate. Retreat At HP% = 0 disables health retreat. Preserve duel handling, swimming input applied after Roblox controls, target body clearance, and movement while a path is being solved.
- Combat approaches use `DoCombatJump` for obstacle/gap checks, cooldown, and a budget reset by horizontal progress. Explicit waypoint and mining/smithing jumps keep `DoJump`. Facing repairs stale attachment/alignment handles through `AICFeature.EnsureFaceOrientation`; destroy the pair before clearing it during respawn.
- **Quest Helper:** ESP searches QuestItems using normalized names and optionally shows all items. Automatic extraction of active quest targets remains unresolved; use QuestDump evidence before inventing a quest schema.
- **Mob data:** missing live drops/attributes can mean incomplete streaming. Do not overwrite known persistent data with empty observations. Data/model details must be confirmed against the game or provided references.

## Verification and delivery

- For documentation-only changes, verify referenced paths, formatting, and the diff. Do not bump the runtime version solely for documentation.
- For runtime changes, check module inclusion/dependencies, schema/export compatibility, profile/global refresh, reset/teardown paths, and relevant TODO regressions.
- If `luau-compile` is available, compile the affected files (all loaded files when changing startup/module structure). `luau-analyze` may need Roblox/executor definitions; distinguish missing environment definitions from real problems. TODO records prior use of these tools, but no tool binaries are checked in or were found on PATH during this review.
- Report static checks separately from actual Roblox testing. Never claim in-game success based on code inspection or compilation. Give a focused in-game verification scenario for the changed behavior.
- Shipped runtime changes follow the existing version convention: update `TITLE` in Init, add a Thai TODO implementation/fix note with the same version, and use a conventional commit subject ending in `(vX.YY)` when a commit is requested. Read the current working version before choosing the next one.
- The initial review found `TITLE` at v3.22 with existing uncommitted v3.22 runtime/TODO changes, while HEAD was v3.21. Treat this as review context and re-check Git rather than assuming the snapshot remains current.
