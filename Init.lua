-- AutoFarm bootstrap.
-- Every module returns {Name, Dependencies, Start(Context)}.

local BRANCH = "main"
local BASE =
    "https://raw.githubusercontent.com/Endmin1strator/Automated-Industry-Complex/refs/heads/"
    .. BRANCH
    .. "/"

local ROOT =
    (typeof(script) == "Instance" and script:IsA("ModuleScript"))
    and script
    or nil

local REMOTE_MODULES = {
    "Core/Runtime.lua",
    "Core/SaveConfig.lua",
    "Core/ProfileManager.lua",
    "Core/Heartbeat.lua",
    "Core/Bootstrap.lua",

    "Features/AutoFarming.lua",
    "Features/AutoBlock.lua",
    "Features/AutoCraft.lua",
    "Features/AutoPatrol.lua",
    "Features/ReturnToFarmZone.lua",
    "Features/IgnoreFarmZone.lua",
    "Features/AutoHeal.lua",
    "Features/AutoRefill.lua",
    "Features/AntiAFK.lua",
    "Features/EnemyPriority.lua",
    "Features/AutoSkill.lua",
    "Features/AutoFind.lua",
    "Features/SafeCombat.lua",
    "Features/ResetOnBoostOut.lua",
    "Features/ResetStats.lua",
    "Features/DebugVisualizer.lua",
    "Features/Waypoints.lua",
    "Features/Farmzone.lua",
    "Features/Deadzone.lua",
    "Features/ProfileSettings.lua",
    "Features/PartySystem.lua",
    "Features/WaypointLoop.lua",

    "Combat/Combat.lua",
    "Combat/CombatUtils.lua",
    "Combat/Targeting.lua",
    "Combat/Navigation.lua",

    "UI/Components.lua",
}

--// Modules that are not specs. UI/Utils is the UI library that Runtime
--// loads itself.
local NON_SPEC_MODULES = {
    ["UI/Utils.lua"] = true,
}

--// Start order. Dependencies still start first, but modules are otherwise
--// started in this order instead of pairs() order, so the controls each
--// module adds always appear in the same place in the window.
local START_ORDER = {
    "Runtime",
    "SaveConfig",
    "ProfileManager",
    "Components",
    "CombatUtils",
    "EnemyPriority",
    "Targeting",
    "Navigation",
    "Combat",
    "AutoFarming",
    "AutoBlock",
    "SafeCombat",
    "AutoSkill",
    "AutoFind",
    "IgnoreFarmZone",
    "AutoPatrol",
    "ReturnToFarmZone",
    "ResetOnBoostOut",
    "ResetStats",
    "DebugVisualizer",
    "AutoHeal",
    "AutoRefill",
    "AntiAFK",
    "AutoCraft",
    "PartySystem",
    "ProfileSettings",
    "Waypoints",
    "Farmzone",
    "Deadzone",
    "WaypointLoop",
    "Bootstrap",
    "Heartbeat",
}

local function collect(Container, Prefix, Output)
    for _, Child in ipairs(Container:GetChildren()) do
        if Child:IsA("Folder") then
            collect(Child, Prefix .. Child.Name .. "/", Output)
        elseif Child:IsA("ModuleScript")
            and Child ~= script
            and not NON_SPEC_MODULES[Prefix .. Child.Name .. ".lua"]
        then
            Output[Prefix .. Child.Name .. ".lua"] = Child
        end
    end
end

local function loadAll()
    local Sources = {}
    local Specs = {}

    if ROOT then
        collect(ROOT, "", Sources)

        for Path, ModuleScript in pairs(Sources) do
            local Spec = require(ModuleScript)

            assert(
                type(Spec) == "table" and type(Spec.Start) == "function",
                "Invalid module: " .. Path
            )

            Specs[Spec.Name] = Spec
        end

        return Specs
    end

    for _, Path in ipairs(REMOTE_MODULES) do
        local Body = assert(
            game:HttpGet(BASE .. Path, true),
            "Failed to fetch " .. Path
        )

        local Chunk = assert(loadstring(Body, "@" .. Path))
        local Spec = Chunk()

        assert(
            type(Spec) == "table" and type(Spec.Start) == "function",
            "Invalid module: " .. Path
        )

        Specs[Spec.Name] = Spec
    end

    return Specs
end

local Specs = loadAll()
local Context = {
    Modules = {},
    Features = {},
}

local Started = {}

local function start(Name)
    if Started[Name] then
        return Context.Modules[Name]
    end

    local Spec = assert(
        Specs[Name],
        "Missing dependency: " .. tostring(Name)
    )

    for _, Dependency in ipairs(Spec.Dependencies or {}) do
        start(Dependency)
    end

    local Module = Spec.Start(Context)

    Context.Modules[Name] = Module
    Context[Name] = Module
    Started[Name] = true

    if Spec.IsFeature or (type(Module) == "table" and Module.IsFeature) then
        table.insert(Context.Features, Module)
    end

    return Module
end

for _, Name in ipairs(START_ORDER) do
    if Specs[Name] then
        start(Name)
    end
end

--// Anything not listed above, in a stable order.
local Remaining = {}
for Name in pairs(Specs) do
    if not Started[Name] then
        table.insert(Remaining, Name)
    end
end
table.sort(Remaining)
for _, Name in ipairs(Remaining) do
    start(Name)
end

--// Controls that AFV2 places after every feature toggle (the health sliders
--// and the Debug Visualizer toggle). Built here so they land below the
--// toggles instead of wherever their module happened to start.
for _, Name in ipairs(START_ORDER) do
    local Module = Context.Modules[Name]

    if type(Module) == "table" and type(Module.BuildLateUI) == "function" then
        Module:BuildLateUI()
    end
end

--// Runs once every control exists. ProfileSettings restores the last used
--// profile here, which touches controls owned by several other modules.
for _, Name in ipairs(START_ORDER) do
    local Module = Context.Modules[Name]

    if type(Module) == "table" and type(Module.Finalize) == "function" then
        Module:Finalize()
    end
end

Context.Heartbeat:Start(Context.Features)

return Context
