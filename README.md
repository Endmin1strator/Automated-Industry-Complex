# AutoFarmV3 refactor

This revision explicitly separates the feature modules requested:

- AutoFarming.lua
- AutoBlock.lua
- AutoCraft.lua
- AutoPatrol.lua
- ReturnToFarmZone.lua
- IgnoreFarmZone.lua
- AutoHeal.lua
- AutoRefill.lua
- AntiAFK.lua
- EnemyPriority.lua
- AutoSkill.lua
- AutoFind.lua
- SafeCombat.lua
- ResetOnBoostOut.lua
- ResetStats.lua
- DebugVisualizer.lua
- Waypoints.lua
- Farmzone.lua
- Deadzone.lua

Waypoints, Farmzone and Deadzone are spatial sections/modules and are not part of Profile Settings.

The supplied source contains a Crafting UI/TODO but no actual crafting routine, so AutoCraft is a real module with the UI/state hook and deliberately does not invent crafting behavior.

`Legacy/` contains the original reviewed files for comparison. `Core/Runtime.lua` is retained as a compatibility layer while the large legacy implementation is migrated feature-by-feature without silently inventing behavior.
"# Automated-Industry-Complex" 
