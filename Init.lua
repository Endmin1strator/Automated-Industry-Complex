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

    "Combat/Combat.lua",
    "Combat/CombatUtils.lua",
    "Combat/Targeting.lua",
    "Combat/Navigation.lua",

    "UI/Components.lua",
}

local function collect(Container, Prefix, Output)
    for _, Child in ipairs(Container:GetChildren()) do
        if Child:IsA("Folder") then
            collect(Child, Prefix .. Child.Name .. "/", Output)
        elseif Child:IsA("ModuleScript") and Child ~= script then
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

for Name in pairs(Specs) do
    start(Name)
end

Context.Heartbeat:Start(Context.Features)

return Context
