-- AutoSmithing crafts at a smithing table. It works on its own, apart from
-- Auto Mining: whenever a recipe in the Recipe Priority list can be crafted
-- and its target is not reached, it walks to the table and crafts it.
--
--   * Recipes go in priority order. One is skipped while SmithingSkill is
--     below its CraftingSkill, while the materials (minus the reserves) do
--     not cover a craft, or once the inventory holds its Target.
--   * The table is the one set with "Set Smithing Table", else the nearest.
--   * Within USE_DISTANCE it calls CraftingStart, then SmithingMinigame
--     plays the strikes. A craft ends when the minigame shows its result
--     and closes; the next one waits for the inventory to update.
--   * MAX_FAILURES failed crafts in a row pause that recipe FAILURE_PAUSE.
--   * A craft order (CRAFT in the Recipe Browser: N of one recipe) goes
--     before the priority list, and runs with the Auto Smithing toggle off.
--     It ends once N are crafted, or when it cannot go on (out of
--     materials, skill too low, paused after failures) or is cancelled.
--
-- With Auto Farm on, AutoFarming offers it the frame once the waypoint
-- route is walked, ahead of Auto Mining. With Auto Farm off it runs alone.
-- The Crafting tab controls live in AutoSmithingUI.
return {
    Name = "AutoSmithing",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "CombatUtils", "Navigation", "Combat", "DebugVisualizer", "WalkController", "SmithingRecipes", "SmithingMinigame"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local Replicated = Context.Services.Replicated
        local CONFIG = Context.CONFIG
        local FeatureState = Context.Feature
        local AICCombatUtils = Context.AICCombatUtils
        local AICCombat = Context.AICCombat
        local AICFeature = Context.AICFeature
        local AICDebug = Context.AICDebug
        local UIRef = Context.UIRef
        local NotifyAction = Context.NotifyAction
        local DEBUG_COLORS = Context.DEBUG_COLORS
        local Movement = Context.WalkController
        local Recipes = Context.SmithingRecipes
        local Minigame = Context.SmithingMinigame

        local TABLE_NAME = "Smithing"
        --// CraftingStart is accepted from this close (the proof of concept
        --// allowed 10).
        local USE_DISTANCE = 8
        --// Stand this far from the table's ProxBase surface.
        local APPROACH_STANDOFF = 2
        --// The saved table is the one standing within this of the saved spot.
        local TABLE_MATCH_DISTANCE = 10
        local SELECT_INTERVAL = 0.5
        local WALK_TIMEOUT = 30
        local UNREACHABLE_SECONDS = 30
        local START_TIMEOUT = 10
        --// The minigame must open within this after CraftingStart answers.
        local GAME_APPEAR_TIMEOUT = 5
        local GAME_TIMEOUT = 30
        --// After the result shows, wait this long at most for it to close.
        local END_TIMEOUT = 5
        --// And this long at most for the inventory to change.
        local SETTLE_TIMEOUT = 3
        local MAX_FAILURES = 3
        local FAILURE_PAUSE = 60
        local STATUS_INTERVAL = 0.25
        local BILLBOARD_INTERVAL = 0.5
        local BILLBOARD_RANGE = 150

        local Feature = {
            Name = "AutoSmithing",
            IsFeature = true,
            S = {
                --// "Idle", "Walking", "Starting", "Minigame", "Finishing"
                --// or "Settling".
                State = "Idle",
                Token = 0,
                Recipe = nil,
                Table = nil,
                ApproachPoint = nil,
                WalkStart = 0,
                StateStart = 0,
                GameSeen = false,
                Result = nil,
                InventoryBefore = nil,
                LastSelect = 0,
                --// Why it is idle, for the status line.
                IdleReason = "",
                Unreachable = {},
                Failures = {},
                PausedUntil = {},
                Crafted = 0,
                Failed = 0,
                LastStatus = 0,
                LastBillboards = 0,
                BillboardsShown = false,
                Ended = false,
                EndedConnection = nil,
                --// { Name, Count, Done } while a craft order runs.
                Order = nil,
            },
        }

        local S = Feature.S

        local function IsCommitted()
            return S.State == "Starting"
                or S.State == "Minigame"
                or S.State == "Finishing"
                or S.State == "Settling"
        end

        local function EndJob()
            S.Token += 1
            S.State = "Idle"
            S.Recipe = nil
            S.Table = nil
            S.ApproachPoint = nil
            S.Result = nil
            S.GameSeen = false
            Minigame:Stop()
            Movement:Reset()
        end

        local function IsPaused(Name)
            return (S.PausedUntil[Name] or 0) > os.clock()
        end

        --// Ends the craft order, saying why when Reason is given.
        local function EndOrder(Reason)
            local Order = S.Order

            if not Order then
                return
            end

            S.Order = nil
            S.LastSelect = 0

            if Reason then
                NotifyAction("CRAFT ORDER", string.format("%s  %d/%d  //  %s", Order.Name, Order.Done, Order.Count, Reason), 5)
            end
        end

        --// Counts a finished craft. Failures in a row pause the recipe.
        local function RecordResult(Succeeded, now)
            local Name = S.Recipe
            local Order = S.Order
            local ForOrder = Order ~= nil and Order.Name == Name

            --// Choose the next craft on the very next frame, so Auto
            --// Mining does not get a moment in between crafts.
            S.LastSelect = 0

            if Succeeded then
                S.Crafted += 1
                S.Failures[Name] = 0

                if ForOrder then
                    Order.Done += 1

                    if Order.Done >= Order.Count then
                        EndOrder("DONE")
                    end
                end

                return
            end

            S.Failed += 1
            S.Failures[Name] = (S.Failures[Name] or 0) + 1

            if S.Failures[Name] >= MAX_FAILURES then
                S.Failures[Name] = 0
                S.PausedUntil[Name] = now + FAILURE_PAUSE
                NotifyAction("AUTO SMITHING", string.format("%s failed %d times; paused %ds", Name, MAX_FAILURES, FAILURE_PAUSE), 5)

                if ForOrder then
                    EndOrder("FAILED " .. MAX_FAILURES .. " TIMES")
                end
            end
        end

        local function Fail(now, Reason)
            S.IdleReason = Reason
            RecordResult(false, now)
            EndJob()
        end

        ------------------------------------------------------------------------
        --// Tables
        ------------------------------------------------------------------------

        local function GetTableParts(Table)
            local ProxBase = Table:FindFirstChild("ProxBase")
            local Id = Table:FindFirstChild("Id")

            if not Table:IsA("Model") or Table.Name ~= TABLE_NAME
                or not ProxBase or not ProxBase:IsA("BasePart")
                or not Id
            then
                return nil
            end

            return ProxBase, Id
        end

        local function IsTableUsable(Table, ProxBase, now)
            return (S.Unreachable[Table] or 0) <= now
                and (FeatureState.IgnoreFarmZone.Enabled or not AICCombatUtils.IsInsideFarmDeadzone(ProxBase.Position))
        end

        --// Every table that exists right now.
        local function GetTables()
            local Folder = workspace:FindFirstChild("Interactions")
            local Tables = {}

            for _, Child in ipairs(Folder and Folder:GetChildren() or {}) do
                if GetTableParts(Child) then
                    table.insert(Tables, Child)
                end
            end

            return Tables
        end

        --// The table at the saved spot, or the nearest usable one when none
        --// is saved. Nil with a reason when there is no table to use.
        local function ResolveTable(now, RootPart)
            local Saved = Runtime:GetPlaceConfig().SMITH_TABLE
            local Origin = Saved or RootPart.Position
            local Best, BestDistance = nil, math.huge

            for _, Table in ipairs(GetTables()) do
                local ProxBase = GetTableParts(Table)
                local Distance = (ProxBase.Position - Origin).Magnitude

                if Distance < BestDistance and IsTableUsable(Table, ProxBase, now) then
                    Best, BestDistance = Table, Distance
                end
            end

            if Saved and BestDistance > TABLE_MATCH_DISTANCE then
                return nil, "SAVED TABLE NOT FOUND"
            end

            return Best, Best == nil and "NO SMITHING TABLE" or nil
        end

        --// The table nearest to the character, for "Set Smithing Table".
        function Feature:GetNearestTable()
            local _, _, RootPart = Runtime:GetCharacter()

            if not RootPart then
                return nil, math.huge
            end

            local Best, BestDistance = nil, math.huge

            for _, Table in ipairs(GetTables()) do
                local Distance = (GetTableParts(Table).Position - RootPart.Position).Magnitude

                if Distance < BestDistance then
                    Best, BestDistance = Table, Distance
                end
            end

            return Best, BestDistance
        end

        function Feature:GetTablePosition(Table)
            return GetTableParts(Table).Position
        end

        ------------------------------------------------------------------------
        --// Crafting
        ------------------------------------------------------------------------

        local function GetRemote(Name)
            return Replicated:FindFirstChild(Name) or Replicated:FindFirstChild(Name, true)
        end

        --// CraftingEnded, when the game fires it to the client, ends the
        --// minigame wait as well; the GUI result is the main signal.
        local function WatchEnded()
            if S.EndedConnection then
                return
            end

            local Remote = GetRemote("CraftingEnded")

            if Remote and Remote:IsA("RemoteEvent") then
                S.EndedConnection = Remote.OnClientEvent:Connect(function()
                    S.Ended = true
                end)
            end
        end

        local function BeginCraft(now)
            local Remote = GetRemote("CraftingStart")
            local _, Id = GetTableParts(S.Table)

            if not Remote or not Remote:IsA("RemoteFunction") then
                S.IdleReason = "CraftingStart NOT FOUND"
                EndJob()
                return
            end

            WatchEnded()

            S.State = "Starting"
            S.StateStart = now
            S.Ended = false
            S.InventoryBefore = Recipes:GetInventoryText()

            --// Playing from now on: the game may open the minigame before
            --// CraftingStart answers. It only strikes once the GUI is there.
            Minigame:Start()

            local Token = S.Token
            local RecipeName = S.Recipe
            local TableId = Id.Value

            --// InvokeServer yields, which a heartbeat must never do.
            task.spawn(function()
                local Ok, Result = pcall(function()
                    return Remote:InvokeServer(RecipeName, TableId)
                end)

                --// Superseded, or the minigame already opened and is now
                --// what decides the craft.
                if Token ~= S.Token or S.State ~= "Starting" then
                    return
                end

                if not Ok or Result == false then
                    warn("[AutoSmithing] CraftingStart refused:", RecipeName, Ok and Result or "")
                    Fail(os.clock(), "START REFUSED")
                    return
                end

                S.State = "Minigame"
                S.StateStart = os.clock()
                S.GameSeen = false
            end)
        end

        --// Moves a committed craft along. Nothing here moves the character.
        local function Advance(now)
            local Main = Minigame:Find()

            if S.State == "Starting" then
                if Main then
                    S.State = "Minigame"
                    S.StateStart = now
                    S.GameSeen = true
                elseif now - S.StateStart > START_TIMEOUT then
                    Fail(now, "NO ANSWER FROM CraftingStart")
                end
            elseif S.State == "Minigame" then
                if Main then
                    S.GameSeen = true
                    S.Result = Minigame:GetResult(Main)
                end

                --// CraftingEnded counts only once the minigame was seen;
                --// when the game fires it is not known for sure.
                if S.Result or (S.GameSeen and (not Main or S.Ended)) then
                    Minigame:Stop()
                    S.State = "Finishing"
                    S.StateStart = now
                elseif not S.GameSeen and now - S.StateStart > GAME_APPEAR_TIMEOUT then
                    Fail(now, "MINIGAME DID NOT OPEN")
                elseif now - S.StateStart > GAME_TIMEOUT then
                    Fail(now, "MINIGAME TIMED OUT")
                end
            elseif S.State == "Finishing" then
                if not Main or now - S.StateStart > END_TIMEOUT then
                    S.State = "Settling"
                    S.StateStart = now
                end
            elseif S.State == "Settling" then
                local Changed = Recipes:GetInventoryText() ~= S.InventoryBefore

                if Changed or now - S.StateStart > SETTLE_TIMEOUT then
                    --// Without a result on screen, a changed inventory is
                    --// the only sign the craft went through.
                    local Succeeded = S.Result == "Success" or (S.Result == nil and Changed)

                    S.IdleReason = ""
                    RecordResult(Succeeded, now)
                    EndJob()
                end
            end
        end

        --// Something already in reach while walking is fought off on the
        --// spot; the walk resumes after. True when it took the frame.
        local function DefendWhileWalking(now)
            local Threat = AICCombat.GetFightBackThreat()

            if not Threat then
                return false
            end

            S.WalkStart = now
            Movement:Hold()

            if AICFeature.EnsureWeaponDrawn and AICFeature.EnsureWeaponDrawn(now) then
                return true
            end

            AICCombat.FaceGoblin(Threat)
            AICCombat.RetreatAttack(Threat, now)
            return true
        end

        --// Leaves the job without touching the shared walker when there is
        --// none: Auto Mining may be using it right after this frame.
        local function GoIdle(Reason)
            S.IdleReason = Reason

            if S.State ~= "Idle" then
                EndJob()
            end

            return false
        end

        --// The craft order's recipe when it can be crafted now. Otherwise
        --// the order is ended, with why.
        local function PickOrder()
            local Order = S.Order
            local State = Recipes:Describe(
                { Name = Order.Name, Target = math.huge },
                Recipes:GetInventory(),
                Recipes:GetReserves(),
                Recipes:GetSkill()
            )

            if not State.Known then
                EndOrder("UNKNOWN RECIPE")
            elseif State.Locked then
                EndOrder("SMITHING SKILL TOO LOW")
            elseif IsPaused(Order.Name) then
                EndOrder("PAUSED AFTER FAILURES")
            elseif State.Craftable < 1 then
                EndOrder("OUT OF MATERIALS")
            else
                return State
            end

            return nil
        end

        --// Chooses at most every SELECT_INTERVAL, idle or not; the plan
        --// reads the whole inventory. True while there is a job.
        local function UpdateJob(now, RootPart)
            if now - S.LastSelect < SELECT_INTERVAL then
                return S.State ~= "Idle"
            end

            S.LastSelect = now

            local Next = S.Order and PickOrder()
            local Plan = nil

            if not Next then
                if not FeatureState.AutoSmithing.Enabled then
                    return GoIdle("NO CRAFT ORDER")
                end

                Next, Plan = Recipes:PickNext(IsPaused)
            end

            if not Next then
                return GoIdle(Feature.GetIdleReason(Plan))
            end

            local Table, Reason = ResolveTable(now, RootPart)

            if not Table then
                return GoIdle(Reason)
            end

            if Next.Name ~= S.Recipe or Table ~= S.Table then
                EndJob()
                S.State = "Walking"
                S.Recipe = Next.Name
                S.Table = Table
                S.WalkStart = now
                S.ApproachPoint = Movement:GetApproachPoint(GetTableParts(Table), APPROACH_STANDOFF, Table)
            end

            return true
        end

        --// True while smithing owns the frame. False hands it back: smithing
        --// is off with no craft order, or nothing can be crafted (or there
        --// is no table).
        function Feature.Step(now)
            local _, Humanoid, RootPart = Runtime:GetCharacter()
            local Active = FeatureState.AutoSmithing.Enabled or S.Order ~= nil

            if not Active or not Humanoid or not RootPart then
                if S.State ~= "Idle" then
                    EndJob()
                end

                return false
            end

            if IsCommitted() then
                Movement:Hold()
                Advance(now)
                return true
            end

            if not UpdateJob(now, RootPart) or not S.Table or not S.Table.Parent then
                return false
            end

            if DefendWhileWalking(now) then
                return true
            end

            local ProxBase = GetTableParts(S.Table)

            if (ProxBase.Position - RootPart.Position).Magnitude <= USE_DISTANCE then
                Movement:Hold()
                BeginCraft(now)
                return true
            end

            local Result = Movement:MoveTo(S.ApproachPoint, { Ignore = S.Table })

            if Result == "failed" or now - S.WalkStart > WALK_TIMEOUT then
                S.Unreachable[S.Table] = now + UNREACHABLE_SECONDS
                S.IdleReason = "TABLE UNREACHABLE"
                EndJob()
                --// Pick another table on the next frame, not in half a second.
                S.LastSelect = 0
            end

            return true
        end

        AICFeature.SmithingStep = Feature.Step

        ------------------------------------------------------------------------
        --// Status line and table billboards
        ------------------------------------------------------------------------

        --// Why nothing is being crafted, from the plan.
        function Feature.GetIdleReason(Plan)
            if #Plan == 0 then
                return "NO RECIPES IN PRIORITY"
            end

            local AnyLocked, AnyShort, AnyPaused = false, false, false

            for _, State in ipairs(Plan) do
                if State.Known and State.Remaining > 0 then
                    if State.Locked then
                        AnyLocked = true
                    elseif IsPaused(State.Name) then
                        AnyPaused = true
                    elseif State.Craftable < 1 then
                        AnyShort = true
                    end
                end
            end

            if AnyShort then
                return "NOT ENOUGH MATERIALS"
            elseif AnyPaused then
                return "PAUSED AFTER FAILURES"
            elseif AnyLocked then
                return "SMITHING SKILL TOO LOW"
            end

            return "ALL TARGETS MET"
        end

        local function GetStatusText()
            local Order = S.Order

            if not FeatureState.AutoSmithing.Enabled and not Order then
                return "OFF"
            end

            local Counts = string.format("  (OK %d / FAIL %d)", S.Crafted, S.Failed)
            local Recipe = S.Recipe or ""

            if Order then
                Counts = string.format("  [ORDER %s %d/%d]", Order.Name, Order.Done, Order.Count) .. Counts
            end

            if S.State == "Walking" then
                return "WALKING TO TABLE  " .. Recipe .. Counts
            elseif S.State == "Starting" then
                return "STARTING  " .. Recipe .. Counts
            elseif S.State == "Minigame" then
                return string.format("MINIGAME  %s  %d strikes", Recipe, Minigame:GetStrikes()) .. Counts
            elseif S.State == "Finishing" or S.State == "Settling" then
                return "FINISHING  " .. Recipe .. Counts
            end

            return "IDLE  //  " .. (S.IdleReason ~= "" and S.IdleReason or "WAITING") .. Counts
        end

        local function DescribeTable(Table, ProxBase, Saved, now)
            if Table == S.Table then
                return S.State == "Walking" and "TARGET  " .. S.Recipe or "CRAFTING  " .. S.Recipe, DEBUG_COLORS.OreMining
            elseif (S.Unreachable[Table] or 0) > now then
                return "UNREACHABLE", DEBUG_COLORS.OreBlocked
            elseif not FeatureState.IgnoreFarmZone.Enabled and AICCombatUtils.IsInsideFarmDeadzone(ProxBase.Position) then
                return "IN DEADZONE", DEBUG_COLORS.OreBlocked
            elseif Saved and (ProxBase.Position - Saved).Magnitude > TABLE_MATCH_DISTANCE then
                return "NOT THE SET TABLE", DEBUG_COLORS.OreIdle
            end

            return "READY", DEBUG_COLORS.OreReady
        end

        local function UpdateBillboards(now)
            if not (FeatureState.DebugVisualizer.Enabled and FeatureState.DebugSmithing.Enabled) then
                if S.BillboardsShown then
                    S.BillboardsShown = false
                    AICDebug.UpdateStatusBillboards("Smithing", nil)
                end

                return
            end

            local _, _, RootPart = Runtime:GetCharacter()

            if not RootPart then
                return
            end

            local Saved = Runtime:GetPlaceConfig().SMITH_TABLE
            local Entries = {}

            for _, Table in ipairs(GetTables()) do
                local ProxBase = GetTableParts(Table)

                if (ProxBase.Position - RootPart.Position).Magnitude <= BILLBOARD_RANGE then
                    local Status, Color = DescribeTable(Table, ProxBase, Saved, now)
                    local IsSaved = Saved and (ProxBase.Position - Saved).Magnitude <= TABLE_MATCH_DISTANCE

                    Entries[Table] = {
                        Core = ProxBase,
                        Title = IsSaved and "SMITHING  (SET)" or "SMITHING",
                        Status = Status,
                        Color = Color,
                    }
                end
            end

            S.BillboardsShown = true
            AICDebug.UpdateStatusBillboards("Smithing", Entries)
        end

        function Feature:Update()
            local now = os.clock()

            if now - S.LastStatus >= STATUS_INTERVAL then
                S.LastStatus = now

                if UIRef.SmithStatusLabel then
                    UIRef.SmithStatusLabel.Text = "STATUS  " .. GetStatusText()
                end
            end

            if now - S.LastBillboards >= BILLBOARD_INTERVAL then
                S.LastBillboards = now
                UpdateBillboards(now)
            end
        end

        --// Starts a craft order of Count crafts of Name, replacing any
        --// order already running. A craft already under way finishes first.
        function Feature:StartOrder(Name, Count)
            Count = math.floor(tonumber(Count) or 0)

            if Count < 1 or not Recipes:Get(Name) then
                return false
            end

            S.Order = { Name = Name, Count = Count, Done = 0 }
            S.PausedUntil[Name] = nil
            S.LastSelect = 0
            return true
        end

        function Feature:CancelOrder()
            EndOrder("CANCELLED")
        end

        --// { Name, Count, Done } of the running craft order, or nil.
        function Feature:GetOrder()
            return S.Order
        end

        --// Drops the current craft and any craft order. ClearMemory also
        --// forgets unreachable tables and paused recipes, which another
        --// profile should not inherit.
        function Feature:Reset(ClearMemory)
            EndOrder(S.Order and "CANCELLED" or nil)
            EndJob()

            if ClearMemory then
                table.clear(S.Unreachable)
                table.clear(S.Failures)
                table.clear(S.PausedUntil)
            end
        end

        --// The recipe list or reserves changed: choose again next frame.
        function Feature:Rescan()
            S.LastSelect = 0
        end

        function Feature:IsPaused(Name)
            return IsPaused(Name)
        end

        Context.Connect(Context.Player.CharacterAdded, function()
            EndJob()
        end)

        Context.Lifetime.OnEnd(function()
            Context.Lifetime.Disconnect(S.EndedConnection)
            S.EndedConnection = nil
        end)

        return Feature
    end,
}
