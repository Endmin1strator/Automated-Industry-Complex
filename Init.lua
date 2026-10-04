-- AutoFarm bootstrap.
-- Every module returns {Name, Dependencies, Start(Context)}.

local TITLE = "AUTOMATED INDUSTRY COMPLEX v2.74"
local UTILS_PATH = "UI/Utils.lua"

--// A failed download is retried this many times before giving up.
local FETCH_RETRIES = 2

local BRANCH = "main"
local BASE =
    "https://raw.githubusercontent.com/Endmin1strator/Automated-Industry-Complex/refs/heads/"
    .. BRANCH
    .. "/"

local ROOT =
    (typeof(script) == "Instance" and script:IsA("ModuleScript"))
    and script
    or nil

--// Every module, in start order. This is the only list to touch when a
--// module is added: it is both what gets downloaded and the order modules
--// start in (dependencies still start first), so the controls each module
--// adds always appear in the same place in the window. A saved toggle also
--// needs its line in Core/SaveConfig.lua.
local MODULES = {
    "Core/SaveConfig.lua",
    "Core/GuiClick.lua",
    "Core/Runtime.lua",
    "Core/ProfileManager.lua",
    "UI/Components.lua",

    "Combat/CombatUtils.lua",
    "Features/EnemyPriority.lua",
    "Combat/Targeting.lua",
    "Combat/Navigation.lua",
    "Combat/Combat.lua",

    "Features/AutoFarming.lua",
    "Features/AutoBlock.lua",
    "Features/AutoBlockConfirm.lua",
    "Features/SafeCombat.lua",
    "Features/AutoSkill.lua",
    "Features/AutoFind.lua",
    "Features/IgnoreFarmZone.lua",
    "Features/AutoPatrol.lua",
    "Features/ReturnToFarmZone.lua",
    "Features/AutoRefill.lua",
    "Features/SafeBoosterReset.lua",
    "Features/ResetStats.lua",
    "Features/DebugVisualizer.lua",
    "Features/AutoHeal.lua",
    "Features/AntiAFK.lua",
    "Features/Minezone.lua",
    "Features/WalkController.lua",
    "Features/AutoMining.lua",
    "Features/AutoMiningUI.lua",
    "Features/SmithingRecipes.lua",
    "Features/SmithingMinigame.lua",
    "Features/AutoSmithing.lua",
    "Features/SmithingBrowser.lua",
    "Features/AutoSmithingUI.lua",
    "Features/PartySystem.lua",
    "Features/ProfileSettings.lua",
    "Features/Waypoints.lua",
    "Features/Farmzone.lua",
    "Features/Deadzone.lua",
    "Features/RespawnTimers.lua",
    "Features/WaypointLoop.lua",

    "Core/Bootstrap.lua",
    "Core/Heartbeat.lua",
}

--// Module name from its path: "Features/AutoFarming.lua" -> "AutoFarming".
--// Every module's Name matches its file name.
local START_ORDER = {}

for _, Path in ipairs(MODULES) do
    table.insert(START_ORDER, string.match(Path, "([^/]+)%.lua$"))
end

--// Modules that are not specs. UI/Utils is the UI library that Runtime
--// loads itself.
local NON_SPEC_MODULES = {
    ["UI/Utils.lua"] = true,
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

local Context = {
    Modules = {},
    Features = {},
}

--// The window is built first so its boot loader can report real progress:
--// fetching takes the first half of the bar, starting modules the rest.
local UI = nil
local FETCH_SHARE = 0.5

local function report(Fraction, Text)
    if UI then
        UI:SetLoadingProgress(Fraction, Text)
    end
end

local function fail(Message)
    --// Only the first line fits on the loader; the full text is raised.
    if UI then
        UI:SetLoadingProgress(nil, "LOAD FAILED  //  " .. string.match(Message, "^[^\n]*"), true)
    end

    error(Message, 0)
end

local function checkSpec(Spec, Path)
    if type(Spec) ~= "table" or type(Spec.Start) ~= "function" then
        fail("Invalid module: " .. Path)
    end

    return Spec
end

local function fetchOnce(Path)
    local Ok, Body = pcall(function()
        return game:HttpGet(BASE .. Path, true)
    end)

    if Ok and type(Body) == "string" and Body ~= "" and not string.find(Body, "^404: Not Found") then
        return Body
    end

    return nil
end

--// Starts every download at once. HttpGet yields, so fetching in parallel
--// costs about one round trip instead of one per file.
local function fetchParallel(Paths)
    local Bodies = {}
    local Pending = #Paths

    for _, Path in ipairs(Paths) do
        task.spawn(function()
            for _ = 0, FETCH_RETRIES do
                Bodies[Path] = fetchOnce(Path)

                if Bodies[Path] then
                    break
                end
            end

            Pending -= 1
        end)
    end

    return Bodies, function()
        return Pending
    end
end

local function createWindow(Utils)
    UI = Utils.new(TITLE, { ManualLoading = true })
    Context.UI = UI
end

local function loadLocal()
    local Sources = {}
    local Specs = {}

    local UIFolder = ROOT:FindFirstChild("UI")
    local UtilsModule = UIFolder and UIFolder:FindFirstChild("Utils")

    if UtilsModule and UtilsModule:IsA("ModuleScript") then
        createWindow(require(UtilsModule))
    end

    collect(ROOT, "", Sources)

    for Path, ModuleScript in pairs(Sources) do
        local Spec = checkSpec(require(ModuleScript), Path)
        Specs[Spec.Name] = Spec
    end

    return Specs
end

local function loadRemote()
    local Paths = table.clone(MODULES)
    table.insert(Paths, 1, UTILS_PATH)

    local Bodies, GetPending = fetchParallel(Paths)
    local Total = #Paths

    --// Show the window as soon as Utils arrives; the modules keep
    --// downloading behind the loader.
    local UtilsBody = Bodies[UTILS_PATH]

    while not UtilsBody and GetPending() > 0 do
        task.wait()
        UtilsBody = Bodies[UTILS_PATH]
    end

    if not UtilsBody then
        fail("Failed to fetch " .. UTILS_PATH)
    end

    local UtilsChunk = loadstring(UtilsBody, "@" .. UTILS_PATH)

    if not UtilsChunk then
        fail("Failed to compile " .. UTILS_PATH)
    end

    createWindow(UtilsChunk())

    while GetPending() > 0 do
        local Done = Total - GetPending()
        report(Done / Total * FETCH_SHARE, string.format("FETCHING MODULES  //  %d / %d", Done, Total))
        task.wait()
    end

    report(FETCH_SHARE, "COMPILING MODULES")

    local Specs = {}

    for _, Path in ipairs(MODULES) do
        local Body = Bodies[Path]

        if not Body then
            fail("Failed to fetch " .. Path)
        end

        local Chunk, CompileError = loadstring(Body, "@" .. Path)

        if not Chunk then
            fail("Failed to compile " .. Path .. ": " .. tostring(CompileError))
        end

        local Spec = checkSpec(Chunk(), Path)
        Specs[Spec.Name] = Spec
    end

    return Specs
end

local Specs = ROOT and loadLocal() or loadRemote()
local SpecCount = 0

for _ in pairs(Specs) do
    SpecCount += 1
end

local Started = {}
local StartedCount = 0

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

    report(
        FETCH_SHARE + StartedCount / math.max(1, SpecCount) * (1 - FETCH_SHARE),
        "STARTING  //  " .. Name
    )

    local Ok, Module = xpcall(Spec.Start, debug.traceback, Context)

    if not Ok then
        fail(Name .. " failed to start\n" .. tostring(Module))
    end

    Context.Modules[Name] = Module
    Context[Name] = Module
    Started[Name] = true
    StartedCount += 1

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

if Context.UI then
    Context.UI:FinishLoading()
end

return Context
