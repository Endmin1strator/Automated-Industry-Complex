return {
    Name = "AutoFarming",
    IsFeature = true,
    Dependencies = {"Runtime", "Combat", "Targeting", "Navigation", "CombatUtils", "ProfileManager", "Components"},
    Start = function(Context)
        local Runtime = Context.Runtime
        local Services = Context.Services
        local Players = Services.Players
        local Player = Context.Player
        local PlayerGui = Context.PlayerGui
        local Replicated = Services.Replicated
        local StarterGui = Services.StarterGui
        local RunService = Services.RunService
        local PathfindingService = Services.PathfindingService
        local HttpService = Services.HttpService
        local CONFIG = Context.CONFIG
        local FeatureState = Context.Feature
        local AICConfig = Context.AICConfig
        local AICProfile = Context.AICProfile
        local AICCombatUtils = Context.AICCombatUtils
        local AICCombat = Context.AICCombat
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICDebug = Context.AICDebug
        local UIRef = Context.UIRef
        local UI = Context.UI
        local PatrolState = Context.PatrolState
        local MiningFeature = Context.MiningFeature
        local NotifyAction = Context.NotifyAction

        local Feature = {
            Name = "AutoFarming",
            IsFeature = true,
        }
        function Feature.updateCharacter()
            local Character = Player.Character
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")

            Runtime:SetCharacter(Character, Humanoid, RootPart)

            if not Character or not RootPart then
                return
            end

            if not AICFeature.S.FaceAttachment then
                AICFeature.S.FaceAttachment = Instance.new("Attachment")
                AICFeature.S.FaceAttachment.Name = "FaceGoblinAttachment"
                AICFeature.S.FaceAttachment.Parent = RootPart
            end

            local FaceOrientation = Runtime:GetFaceOrientation()
            if not FaceOrientation then
                FaceOrientation = Instance.new("AlignOrientation")
                FaceOrientation.Name = "FaceGoblin"
                FaceOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
                FaceOrientation.Attachment0 = AICFeature.S.FaceAttachment
                FaceOrientation.RigidityEnabled = false
                FaceOrientation.Responsiveness = 25
                FaceOrientation.MaxTorque = math.huge
                FaceOrientation.Enabled = false
                FaceOrientation.Parent = RootPart
                Runtime:SetFaceOrientation(FaceOrientation)
            end

            task.defer(function()
                if not Humanoid then
                    return
                end

                Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                Humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
                Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
            end)
        end

        function Feature.GetPlayerStatValue(Name, Default)
            local PlayerStats = Player:FindFirstChild("PlayerStats")
            local Stat = PlayerStats and PlayerStats:FindFirstChild(Name)
        
            if not Stat then
                return Default
            end
        
            return tonumber(Stat.Value) or Default
        end
        function Feature.GetPlayerLevel()
            return Feature.GetPlayerStatValue("Level", 0)
        end
        
        --// Toggle Screen GUI
        function Feature.CreateToggleContainer()
        end
        function Feature.RegenStamina()
            task.spawn(function()
                local PlayerStats = Player:FindFirstChild("PlayerStats")
                if not PlayerStats then
                    repeat task.wait(0.5) until Player:FindFirstChild("PlayerStats")
                    PlayerStats = Player:FindFirstChild("PlayerStats")
                end
                local GameGui = PlayerGui:FindFirstChild("GameGui")
                if not GameGui then
                    repeat task.wait(0.5) until PlayerGui:FindFirstChild("GameGui")
                    GameGui = PlayerGui:FindFirstChild("GameGui")
                end
                local Stamina = GameGui:FindFirstChild("Stamina")
                local MaxStamina = PlayerStats:FindFirstChild("MaxStamina")
        
                --// Both values are required. Without MaxStamina there is no target
                --// value to restore, so the connection would error on every change.
                if not Stamina or not MaxStamina then
                    return
                end
        
                AICFeature.S.StaminaConnection = Stamina:GetPropertyChangedSignal("Value"):Connect(function()
                    if Stamina.Value < MaxStamina.Value then
                        Stamina.Value = MaxStamina.Value
                    end
                end)
            end)
        end

        function Feature:RenderUpdate(dt)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local PlaceConfig = Runtime:GetPlaceConfig()

            AICUI.updatePosition()

            if Humanoid then
                if AICFeature.GetPlayerLevel() >= CONFIG.HIGH_LEVEL_THRESHOLD then
                    if Humanoid.WalkSpeed < CONFIG.MAXIMUM_WALKSPEED then
                        Humanoid.WalkSpeed = CONFIG.MAXIMUM_WALKSPEED
                    end
                elseif Humanoid.WalkSpeed < CONFIG.MINIMUM_WALKSPEED then
                    Humanoid.WalkSpeed = CONFIG.MINIMUM_WALKSPEED
                end
            end
        end
        function Feature:Update(dt)

            local now = os.clock()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local InputBindableFunction = Runtime:GetInputBindableFunction()
            local FaceOrientation = Runtime:GetFaceOrientation()
            local PlaceConfig = Runtime:GetPlaceConfig()

            --// Auto Block is controlled by the active profile/default config.
            --// Do not gate it by the static PLACE_CONFIG table because profiles can
            --// enable Auto Block even when the current PlaceId has no built-in config.
            --if IsValidPlace(game.PlaceId) then
            --    Enabled = false
            --    updateButton()
            --    return
            --end

            if not Humanoid or not RootPart then
                AICFeature.updateCharacter()
                table.clear(AICCombat.S.ValidMobs)
                AICCombat.S.ClosestTarget = nil
                return
            end

            if Humanoid.Health <= 0 then
                AICDebug.ResetDebugWaypoints()
                CONFIG.CURRENT_WAYPOINT_TARGET = 1
                table.clear(AICCombat.S.ValidMobs)
                AICCombat.S.ClosestTarget = nil
                return
            end

            if now - AICUI.S.LAST_TEXT_UPDATE_TIME >= CONFIG.TEXT_UPDATE_INTERVAL then
                AICUI.S.LAST_TEXT_UPDATE_TIME = now
                AICUI.updatePlayTime()
                AICUI.updateEventCurrency()

                UIRef.WayPointLabel.Text = "WAYPOINTS:  ".. CONFIG.CURRENT_WAYPOINT_TARGET .. "/" .. (PlaceConfig and #PlaceConfig.WAYPOINTS or 0)
                UIRef.WalkSpeedLabel.Text = "WALKSPEED:  " .. tostring(math.floor(Humanoid.WalkSpeed + 0.5))
                UIRef.DeathLabel.Text = "DEATH:  " .. tostring(AICFeature.S.DEATH_COUNT)
            end

            if FeatureState.DebugVisualizer.Enabled then
                AICDebug.UpdateDebugWaypointColors()
            end

            --// Feeds the jump logic. Only counts while the character is actually
            --// trying to move, so standing still on purpose is not read as stuck.
            AICCombatUtils.UpdateStuckTracker(now, Humanoid.MoveDirection.Magnitude > 0.1)

            --// Realtime Mob Validation
            if now - AICCombat.S.LAST_MOB_VALIDATION_TIME >= CONFIG.MOB_VALIDATION_INTERVAL then
                AICCombat.S.LAST_MOB_VALIDATION_TIME = now
                AICCombat.UpdateValidMobs()
            end

            if not AICFeature.S.Enabled then
                FaceOrientation.Enabled = false
                Humanoid.AutoRotate = true
                Humanoid:Move(Vector3.zero)
                return
            end

            if not InputBindableFunction then
                InputBindableFunction = PlayerGui:FindFirstChild("InputBindableFunction", true) :: BindableFunction
                Runtime:SetInputBindableFunction(InputBindableFunction)
                return
            end

            local PlayerStats = Player:FindFirstChild("PlayerStats")
            local Sword = Character:FindFirstChild("Sword")

            if not Sword or not Sword:FindFirstChild("MainWeld", true) or not PlayerStats then
                return
            end

            local MainWeld = Sword:FindFirstChild("MainWeld", true)

            if AICFeature.HandleDeadzoneEscape() then
                return
            end

            --// Emergency Retreat
            local RetreatHealthPercent = math.clamp(tonumber(CONFIG.RETREAT_HEALTH_PERCENT) or 40, 30, 80)
            local AutoHealHealthPercent = math.clamp(tonumber(CONFIG.AUTO_HEAL_HEALTH_PERCENT) or 65, 30, 80)
            local RetreatHealthRatio = RetreatHealthPercent / 100
            local AutoHealHealthRatio = AutoHealHealthPercent / 100
            local RecoverHealthPercent = math.min(95, math.max(70, RetreatHealthPercent + 10))
            local EmergencyHealth = Humanoid.Health <= Humanoid.MaxHealth * RetreatHealthRatio
            local ShouldHeal      = Humanoid.Health <= Humanoid.MaxHealth * AutoHealHealthRatio

            --// Watches every nearby mob rather than only the current target, and
            --// latches for a short hold so a flickering sound or emitter cannot drop
            --// the dodge partway through.
            local EnemyUsingSkill = AICCombat.UpdateSkillThreat(now)

            if EnemyUsingSkill then
                AICCombat.S.RETREATING = true
            end

            --// Execute: a target this close to death is finished instead of retreated
            --// from, at any health of our own. An enemy skill still overrides it,
            --// because eating a skill to land one more hit is not a good trade.
            local ExecuteCharge = false
            local ExecutePercent = math.clamp(tonumber(CONFIG.EXECUTE_CHARGE_HP_PERCENT) or 0, 0, 90)

            if ExecutePercent > 0 and not EnemyUsingSkill and AICCombat.S.ClosestTarget then
                local TargetHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")

                if TargetHumanoid
                    and TargetHumanoid.MaxHealth > 0
                    and TargetHumanoid.Health > 0
                then
                    ExecuteCharge =
                        (TargetHumanoid.Health / TargetHumanoid.MaxHealth) * 100 <= ExecutePercent
                end
            end

            --// Retreat is a health decision only. The old build also entered retreat
            --// whenever WalkSpeed had not been raised yet, but RenderStepped restores
            --// WalkSpeed every frame, so that clause only produced random retreats.
            if ExecuteCharge then
                AICCombat.S.RETREATING = false
            elseif EmergencyHealth then
                AICCombat.S.RETREATING = true
            elseif AICCombat.S.RETREATING and Humanoid.Health >= Humanoid.MaxHealth * (RecoverHealthPercent / 100) and not EnemyUsingSkill then
                AICCombat.S.RETREATING = false

                --// Re-acquire a valid target immediately after healing so the
                --// combat loop does not wait for another target cycle.
                if not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                    AICCombat.S.ClosestTarget = AICCombat.GetClosestGoblin()
                end
            end

            if AICCombat.S.RETREATING then
                --// PlayerStats is already resolved above in this same handler.
                local UseConsumable = Replicated:FindFirstChild("UseConsumable", true)

                AICCombat.RetreatFromGoblins(EnemyUsingSkill)

                local LastConsumed = PlayerStats and PlayerStats:FindFirstChild("LastConsumed")
                local WantsConsume = UseConsumable
                    and LastConsumed
                    and LastConsumed.Value ~= ""
                    and (EmergencyHealth or ShouldHeal)
                    and now - AICFeature.S.LAST_CONSUME_TIME >= CONFIG.CONSUME_INTERVAL
                    --// Never stop to drink mid-dodge. Getting out of the skill first
                    --// is worth more than the heal, and sheathing costs an animation.
                    and not EnemyUsingSkill

                --// Sheathe only when a potion is actually about to be drunk. The old
                --// build sheathed on every retreat frame and drew again as soon as
                --// the retreat ended, which is where the constant draw/sheathe came
                --// from, and each toggle also threw away the frame it happened on.
                if WantsConsume
                    and InputBindableFunction
                    and (AICFeature.S.Equipped or (MainWeld.Part1 and MainWeld.Part1.Name ~= "UpperTorso"))
                    and now - AICFeature.S.LAST_EQUIP_TIME >= CONFIG.EQUIP_TOGGLE_COOLDOWN
                then
                    AICFeature.S.Equipped = false
                    AICFeature.S.LAST_EQUIP_TIME = now

                    InputBindableFunction:Invoke(
                        "EquipButton",
                        Enum.UserInputState.Begin
                    )

                    return
                end

                if WantsConsume and not AICFeature.S.Equipped then
                    AICFeature.S.LAST_CONSUME_TIME = now
                    UseConsumable:InvokeServer(LastConsumed.Value)
                end

                return
            end

            --// Enemy skill retreat speed is temporary. Once retreating ends,
            --// return to the normal movement cap on the next heartbeat.
            if not EnemyUsingSkill and Humanoid.WalkSpeed > CONFIG.MAXIMUM_WALKSPEED then
                Humanoid.WalkSpeed = CONFIG.MAXIMUM_WALKSPEED
            end

            --// Player Check
            --// Whitelisted players are ignored entirely, so a server holding only
            --// them is left alone. Anyone else is blocked individually and then the
            --// server is abandoned; the whole lobby is no longer blocked one by one.
            if AICFeature.S.BlockEnabled then
                local Intruder = nil

                for _, plr in Players:GetPlayers() do
                    if plr ~= Player and not AICFeature.IsWhitelisted(plr.UserId) then
                        Intruder = plr
                        break
                    end
                end

                if Intruder then
                    if not AICFeature.isBlocked(Intruder.UserId) then
                        AICFeature.promptBlockPlayer(Intruder)
                        return
                    end

                    AICFeature.S.BlockCache[Intruder.UserId] = nil
                    AICFeature.TeleportToPlace()
                    return
                end
            end

            --// Play Time
            if workspace.DistributedGameTime >= CONFIG.MAX_SERVER_AGE then
                AICFeature.TeleportToPlace()
                return
            end

            --// Movement
            --// Waypoint route always has priority over combat/patrol.
            --// Combat target acquisition is completely disabled until the route is finished.
            local HasWaypoints = PlaceConfig and type(PlaceConfig.WAYPOINTS) == "table" and #PlaceConfig.WAYPOINTS > 0
            local WaypointIndex = tonumber(CONFIG.CURRENT_WAYPOINT_TARGET) or 1
            local target = nil

            if HasWaypoints then
                if WaypointIndex < 1 then
                    WaypointIndex = 1
                    CONFIG.CURRENT_WAYPOINT_TARGET = 1
                end

                local WaypointCount = #PlaceConfig.WAYPOINTS
                local AtLastWaypoint = WaypointIndex > WaypointCount
                target = not AtLastWaypoint and PlaceConfig.WAYPOINTS[WaypointIndex] or nil

                --// Route mode: never let combat target state leak into waypoint movement.
                if not FeatureState.AutoFind.Enabled and target then
                    AICCombat.S.ClosestTarget = nil
                    AICCombat.S.TargetPath = nil
                    AICCombat.S.TargetPathMob = nil
                    AICCombat.S.TargetApproachMob = nil
                    AICCombat.S.TargetApproachPosition = nil
                    AICCombat.S.RETREATING = false

                    local WaypointOffset = target - RootPart.Position
                    local WaypointHorizontalDistance = Vector3.new(
                        WaypointOffset.X,
                        0,
                        WaypointOffset.Z
                    ).Magnitude
                    local WaypointVerticalDistance = math.abs(WaypointOffset.Y)
                    local ReachDistance = tonumber(PlaceConfig.REACH_DISTANCE) or 5

                    if WaypointHorizontalDistance <= ReachDistance
                        and WaypointVerticalDistance <= math.max(ReachDistance, CONFIG.JUMP_HEIGHT + 2)
                    then
                        CONFIG.CURRENT_WAYPOINT_TARGET = WaypointIndex + 1
                        AICCombatUtils.S.LAST_STUCK_POSITION = nil
                        AICCombatUtils.S.LAST_STUCK_TIME = now
                        AICDebug.UpdateDebugWaypointColors()

                        WaypointIndex = CONFIG.CURRENT_WAYPOINT_TARGET
                        target = PlaceConfig.WAYPOINTS[WaypointIndex]
                    end

                    if target then
                        FaceOrientation.Enabled = false
                        Humanoid.AutoRotate = true
                        Humanoid:MoveTo(target)
                    end

                    if now - AICCombatUtils.S.LAST_STUCK_TIME >= CONFIG.STUCK_CHECK_INTERVAL then
                        AICCombatUtils.S.LAST_STUCK_TIME = now
                        if AICCombatUtils.S.LAST_STUCK_POSITION
                            and (RootPart.Position - AICCombatUtils.S.LAST_STUCK_POSITION).Magnitude < 1
                        then
                            AICCombatUtils.DoJump()
                        else
                            AICCombatUtils.S.LAST_STUCK_POSITION = RootPart.Position
                        end
                    end

                else
                    --// Final waypoint reached: only now allow farm-zone return/combat/patrol.
                    local OutsideFarmZone = not AICCombatUtils.IsInsideFarmArea(RootPart.Position)
                    local InFarmDeadzone = AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position)

                    if FeatureState.ReturnToFarmZone.Enabled
                        and not FeatureState.IgnoreFarmZone.Enabled
                        and (OutsideFarmZone or InFarmDeadzone)
                    then
                        AICCombat.S.ClosestTarget = nil
                        AICFeature.CancelPatrol()
                        AICFeature.MoveBackToFarmZone()
                    else
                        if not AICCombat.S.ClosestTarget or not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                            AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(now)
                        else
                            local LockedTarget = AICCombat.AcquireCombatTarget(now)
                            if LockedTarget then
                                AICCombat.S.ClosestTarget = LockedTarget
                            end
                        end

                        if AICCombat.S.ClosestTarget then
                            --// Combat outranks patrolling, so drop whatever the
                            --// patrol was doing rather than leaving a pause or a leg
                            --// chain to resume once the fight is over.
                            AICFeature.CancelPatrol()
                            AICCombat.MoveToGoblin(AICCombat.S.ClosestTarget)
                        elseif FeatureState.AutoPatrol.Enabled then
                            AICFeature.MoveToPatrol()
                        else
                            PatrolState.PatrolPosition = nil
                            AICFeature.S.FarmReturnPosition = nil
                            FaceOrientation.Enabled = false
                            Humanoid.AutoRotate = true
                            Humanoid:Move(Vector3.zero)
                        end
                    end
                end

            else
                --// No configured waypoints: preserve the original combat/patrol flow.
                local OutsideFarmZone = not AICCombatUtils.IsInsideFarmArea(RootPart.Position)
                local InFarmDeadzone = AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position)

                if FeatureState.ReturnToFarmZone.Enabled
                    and not FeatureState.IgnoreFarmZone.Enabled
                    and (OutsideFarmZone or InFarmDeadzone)
                then
                    AICCombat.S.ClosestTarget = nil
                    AICFeature.CancelPatrol()
                    AICFeature.MoveBackToFarmZone()
                else
                    if not AICCombat.S.ClosestTarget or not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                        AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(now)
                    else
                        local LockedTarget = AICCombat.AcquireCombatTarget(now)
                        if LockedTarget then
                            AICCombat.S.ClosestTarget = LockedTarget
                        end
                    end

                    if AICCombat.S.ClosestTarget then
                        --// Combat outranks patrolling, so drop whatever the patrol
                        --// was doing rather than leaving a pause or a leg chain to
                        --// resume once the fight is over.
                        AICFeature.CancelPatrol()
                        AICCombat.MoveToGoblin(AICCombat.S.ClosestTarget)
                    elseif FeatureState.AutoPatrol.Enabled then
                        AICFeature.MoveToPatrol()
                    else
                        PatrolState.PatrolPosition = nil
                        AICFeature.S.FarmReturnPosition = nil
                        FaceOrientation.Enabled = false
                        Humanoid.AutoRotate = true
                        Humanoid:Move(Vector3.zero)
                    end
                end
            end

            --// Jump. A waypoint sitting higher is not a reason on its own: a ramp
            --// climbs fine on foot, and hopping up one only costs speed. Probe for
            --// something actually in the way instead.
            if PlaceConfig and not FeatureState.AutoFind.Enabled and target then
                AICCombatUtils.DoJumpIfObstacle(target)
            end

            --// Swim Recovery
            if Humanoid:GetState() == Enum.HumanoidStateType.Swimming then
                AICCombatUtils.DoJump()
                return
            end

            if Humanoid.Sit == true then
                Humanoid.Sit = false
                AICCombatUtils.DoJump()
                return
            end

            --// Combat
            --// Never enter combat while a configured waypoint route is still active.
            local WaypointRouteFinished = not HasWaypoints
                or (tonumber(CONFIG.CURRENT_WAYPOINT_TARGET) or 1) > #PlaceConfig.WAYPOINTS

            if WaypointRouteFinished
                and (FeatureState.AutoFind.Enabled or not HasWaypoints or (AICCombat.S.ClosestTarget and not FeatureState.IgnoreFarmZone.Enabled)) then
                if AICCombat.S.ClosestTarget then
                    if not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                        AICCombat.S.ClosestTarget = nil
                        return
                    end

                    if not AICCombat.IsCombatTargetValid(AICCombat.S.ClosestTarget) then
                        FaceOrientation.Enabled = false
                        Humanoid.AutoRotate = true
                        Humanoid:Move(Vector3.zero)
                        return
                    end

                    if (not AICFeature.S.Equipped or (MainWeld.Part1 and MainWeld.Part1.Name == "UpperTorso"))
                        and now - AICFeature.S.LAST_EQUIP_TIME >= CONFIG.EQUIP_TOGGLE_COOLDOWN
                    then
                        AICFeature.S.Equipped = true
                        AICFeature.S.LAST_EQUIP_TIME = now

                        InputBindableFunction:Invoke(
                            "EquipButton",
                            Enum.UserInputState.Begin
                        )

                        return
                    end

                    local MobHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")
                    local MobRoot     = AICCombat.S.ClosestTarget:FindFirstChild("HumanoidRootPart")

                    if MobHumanoid and MobRoot and MobHumanoid.Health > 0 then
                        AICCombat.PerformCombatActions(AICCombat.S.ClosestTarget, now)
                    else
                        AICCombat.S.ValidMobs[AICCombat.S.ClosestTarget] = nil
                        AICCombat.S.ClosestTarget = nil
                    end
                end
            else
                if now - AICFeature.S.LAST_INTERACTION_TIME >= CONFIG.INTERACTION_INTERVAL then
                    AICFeature.S.LAST_INTERACTION_TIME = now

                    InputBindableFunction:Invoke(
                        "InteractButton",
                        Enum.UserInputState.Begin
                    )
                end
            end
        end
        function Feature:Update(dt)

            local now = os.clock()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local InputBindableFunction = Runtime:GetInputBindableFunction()
            local FaceOrientation = Runtime:GetFaceOrientation()
            local PlaceConfig = Runtime:GetPlaceConfig()

            --// Auto Block is controlled by the active profile/default config.
            --// Do not gate it by the static PLACE_CONFIG table because profiles can
            --// enable Auto Block even when the current PlaceId has no built-in config.
            --if IsValidPlace(game.PlaceId) then
            --    Enabled = false
            --    updateButton()
            --    return
            --end

            if not Humanoid or not RootPart then
                AICFeature.updateCharacter()
                table.clear(AICCombat.S.ValidMobs)
                AICCombat.S.ClosestTarget = nil
                return
            end

            if Humanoid.Health <= 0 then
                AICDebug.ResetDebugWaypoints()
                CONFIG.CURRENT_WAYPOINT_TARGET = 1
                table.clear(AICCombat.S.ValidMobs)
                AICCombat.S.ClosestTarget = nil
                return
            end

            if now - AICUI.S.LAST_TEXT_UPDATE_TIME >= CONFIG.TEXT_UPDATE_INTERVAL then
                AICUI.S.LAST_TEXT_UPDATE_TIME = now
                AICUI.updatePlayTime()
                AICUI.updateEventCurrency()

                UIRef.WayPointLabel.Text = "WAYPOINTS:  ".. CONFIG.CURRENT_WAYPOINT_TARGET .. "/" .. (PlaceConfig and #PlaceConfig.WAYPOINTS or 0)
                UIRef.WalkSpeedLabel.Text = "WALKSPEED:  " .. tostring(math.floor(Humanoid.WalkSpeed + 0.5))
                UIRef.DeathLabel.Text = "DEATH:  " .. tostring(AICFeature.S.DEATH_COUNT)
            end

            if FeatureState.DebugVisualizer.Enabled then
                AICDebug.UpdateDebugWaypointColors()
            end

            --// Feeds the jump logic. Only counts while the character is actually
            --// trying to move, so standing still on purpose is not read as stuck.
            AICCombatUtils.UpdateStuckTracker(now, Humanoid.MoveDirection.Magnitude > 0.1)

            --// Realtime Mob Validation
            if now - AICCombat.S.LAST_MOB_VALIDATION_TIME >= CONFIG.MOB_VALIDATION_INTERVAL then
                AICCombat.S.LAST_MOB_VALIDATION_TIME = now
                AICCombat.UpdateValidMobs()
            end

            if not AICFeature.S.Enabled then
                FaceOrientation.Enabled = false
                Humanoid.AutoRotate = true
                Humanoid:Move(Vector3.zero)
                return
            end

            if not InputBindableFunction then
                InputBindableFunction = PlayerGui:FindFirstChild("InputBindableFunction", true) :: BindableFunction
                Runtime:SetInputBindableFunction(InputBindableFunction)
                return
            end

            local PlayerStats = Player:FindFirstChild("PlayerStats")
            local Sword = Character:FindFirstChild("Sword")

            if not Sword or not Sword:FindFirstChild("MainWeld", true) or not PlayerStats then
                return
            end

            local MainWeld = Sword:FindFirstChild("MainWeld", true)

            if AICFeature.HandleDeadzoneEscape() then
                return
            end

            --// Emergency Retreat
            local RetreatHealthPercent = math.clamp(tonumber(CONFIG.RETREAT_HEALTH_PERCENT) or 40, 30, 80)
            local AutoHealHealthPercent = math.clamp(tonumber(CONFIG.AUTO_HEAL_HEALTH_PERCENT) or 65, 30, 80)
            local RetreatHealthRatio = RetreatHealthPercent / 100
            local AutoHealHealthRatio = AutoHealHealthPercent / 100
            local RecoverHealthPercent = math.min(95, math.max(70, RetreatHealthPercent + 10))
            local EmergencyHealth = Humanoid.Health <= Humanoid.MaxHealth * RetreatHealthRatio
            local ShouldHeal      = Humanoid.Health <= Humanoid.MaxHealth * AutoHealHealthRatio

            --// Watches every nearby mob rather than only the current target, and
            --// latches for a short hold so a flickering sound or emitter cannot drop
            --// the dodge partway through.
            local EnemyUsingSkill = AICCombat.UpdateSkillThreat(now)

            if EnemyUsingSkill then
                AICCombat.S.RETREATING = true
            end

            --// Execute: a target this close to death is finished instead of retreated
            --// from, at any health of our own. An enemy skill still overrides it,
            --// because eating a skill to land one more hit is not a good trade.
            local ExecuteCharge = false
            local ExecutePercent = math.clamp(tonumber(CONFIG.EXECUTE_CHARGE_HP_PERCENT) or 0, 0, 90)

            if ExecutePercent > 0 and not EnemyUsingSkill and AICCombat.S.ClosestTarget then
                local TargetHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")

                if TargetHumanoid
                    and TargetHumanoid.MaxHealth > 0
                    and TargetHumanoid.Health > 0
                then
                    ExecuteCharge =
                        (TargetHumanoid.Health / TargetHumanoid.MaxHealth) * 100 <= ExecutePercent
                end
            end

            --// Retreat is a health decision only. The old build also entered retreat
            --// whenever WalkSpeed had not been raised yet, but RenderStepped restores
            --// WalkSpeed every frame, so that clause only produced random retreats.
            if ExecuteCharge then
                AICCombat.S.RETREATING = false
            elseif EmergencyHealth then
                AICCombat.S.RETREATING = true
            elseif AICCombat.S.RETREATING and Humanoid.Health >= Humanoid.MaxHealth * (RecoverHealthPercent / 100) and not EnemyUsingSkill then
                AICCombat.S.RETREATING = false

                --// Re-acquire a valid target immediately after healing so the
                --// combat loop does not wait for another target cycle.
                if not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                    AICCombat.S.ClosestTarget = AICCombat.GetClosestGoblin()
                end
            end

            if AICCombat.S.RETREATING then
                --// PlayerStats is already resolved above in this same handler.
                local UseConsumable = Replicated:FindFirstChild("UseConsumable", true)

                AICCombat.RetreatFromGoblins(EnemyUsingSkill)

                local LastConsumed = PlayerStats and PlayerStats:FindFirstChild("LastConsumed")
                local WantsConsume = UseConsumable
                    and LastConsumed
                    and LastConsumed.Value ~= ""
                    and (EmergencyHealth or ShouldHeal)
                    and now - AICFeature.S.LAST_CONSUME_TIME >= CONFIG.CONSUME_INTERVAL
                    --// Never stop to drink mid-dodge. Getting out of the skill first
                    --// is worth more than the heal, and sheathing costs an animation.
                    and not EnemyUsingSkill

                --// Sheathe only when a potion is actually about to be drunk. The old
                --// build sheathed on every retreat frame and drew again as soon as
                --// the retreat ended, which is where the constant draw/sheathe came
                --// from, and each toggle also threw away the frame it happened on.
                if WantsConsume
                    and InputBindableFunction
                    and (AICFeature.S.Equipped or (MainWeld.Part1 and MainWeld.Part1.Name ~= "UpperTorso"))
                    and now - AICFeature.S.LAST_EQUIP_TIME >= CONFIG.EQUIP_TOGGLE_COOLDOWN
                then
                    AICFeature.S.Equipped = false
                    AICFeature.S.LAST_EQUIP_TIME = now

                    InputBindableFunction:Invoke(
                        "EquipButton",
                        Enum.UserInputState.Begin
                    )

                    return
                end

                if WantsConsume and not AICFeature.S.Equipped then
                    AICFeature.S.LAST_CONSUME_TIME = now
                    UseConsumable:InvokeServer(LastConsumed.Value)
                end

                return
            end

            --// Enemy skill retreat speed is temporary. Once retreating ends,
            --// return to the normal movement cap on the next heartbeat.
            if not EnemyUsingSkill and Humanoid.WalkSpeed > CONFIG.MAXIMUM_WALKSPEED then
                Humanoid.WalkSpeed = CONFIG.MAXIMUM_WALKSPEED
            end

            --// Player Check
            --// Whitelisted players are ignored entirely, so a server holding only
            --// them is left alone. Anyone else is blocked individually and then the
            --// server is abandoned; the whole lobby is no longer blocked one by one.
            if AICFeature.S.BlockEnabled then
                local Intruder = nil

                for _, plr in Players:GetPlayers() do
                    if plr ~= Player and not AICFeature.IsWhitelisted(plr.UserId) then
                        Intruder = plr
                        break
                    end
                end

                if Intruder then
                    if not AICFeature.isBlocked(Intruder.UserId) then
                        AICFeature.promptBlockPlayer(Intruder)
                        return
                    end

                    AICFeature.S.BlockCache[Intruder.UserId] = nil
                    AICFeature.TeleportToPlace()
                    return
                end
            end

            --// Play Time
            if workspace.DistributedGameTime >= CONFIG.MAX_SERVER_AGE then
                AICFeature.TeleportToPlace()
                return
            end

            --// Movement
            --// Waypoint route always has priority over combat/patrol.
            --// Combat target acquisition is completely disabled until the route is finished.
            local HasWaypoints = PlaceConfig and type(PlaceConfig.WAYPOINTS) == "table" and #PlaceConfig.WAYPOINTS > 0
            local WaypointIndex = tonumber(CONFIG.CURRENT_WAYPOINT_TARGET) or 1
            local target = nil

            if HasWaypoints then
                if WaypointIndex < 1 then
                    WaypointIndex = 1
                    CONFIG.CURRENT_WAYPOINT_TARGET = 1
                end

                local WaypointCount = #PlaceConfig.WAYPOINTS
                local AtLastWaypoint = WaypointIndex > WaypointCount
                target = not AtLastWaypoint and PlaceConfig.WAYPOINTS[WaypointIndex] or nil

                --// Route mode: never let combat target state leak into waypoint movement.
                if not FeatureState.AutoFind.Enabled and target then
                    AICCombat.S.ClosestTarget = nil
                    AICCombat.S.TargetPath = nil
                    AICCombat.S.TargetPathMob = nil
                    AICCombat.S.TargetApproachMob = nil
                    AICCombat.S.TargetApproachPosition = nil
                    AICCombat.S.RETREATING = false

                    local WaypointOffset = target - RootPart.Position
                    local WaypointHorizontalDistance = Vector3.new(
                        WaypointOffset.X,
                        0,
                        WaypointOffset.Z
                    ).Magnitude
                    local WaypointVerticalDistance = math.abs(WaypointOffset.Y)
                    local ReachDistance = tonumber(PlaceConfig.REACH_DISTANCE) or 5

                    if WaypointHorizontalDistance <= ReachDistance
                        and WaypointVerticalDistance <= math.max(ReachDistance, CONFIG.JUMP_HEIGHT + 2)
                    then
                        CONFIG.CURRENT_WAYPOINT_TARGET = WaypointIndex + 1
                        AICCombatUtils.S.LAST_STUCK_POSITION = nil
                        AICCombatUtils.S.LAST_STUCK_TIME = now
                        AICDebug.UpdateDebugWaypointColors()

                        WaypointIndex = CONFIG.CURRENT_WAYPOINT_TARGET
                        target = PlaceConfig.WAYPOINTS[WaypointIndex]
                    end

                    if target then
                        FaceOrientation.Enabled = false
                        Humanoid.AutoRotate = true
                        Humanoid:MoveTo(target)
                    end

                    if now - AICCombatUtils.S.LAST_STUCK_TIME >= CONFIG.STUCK_CHECK_INTERVAL then
                        AICCombatUtils.S.LAST_STUCK_TIME = now
                        if AICCombatUtils.S.LAST_STUCK_POSITION
                            and (RootPart.Position - AICCombatUtils.S.LAST_STUCK_POSITION).Magnitude < 1
                        then
                            AICCombatUtils.DoJump()
                        else
                            AICCombatUtils.S.LAST_STUCK_POSITION = RootPart.Position
                        end
                    end

                else
                    --// Final waypoint reached: only now allow farm-zone return/combat/patrol.
                    local OutsideFarmZone = not AICCombatUtils.IsInsideFarmArea(RootPart.Position)
                    local InFarmDeadzone = AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position)

                    if FeatureState.ReturnToFarmZone.Enabled
                        and not FeatureState.IgnoreFarmZone.Enabled
                        and (OutsideFarmZone or InFarmDeadzone)
                    then
                        AICCombat.S.ClosestTarget = nil
                        AICFeature.CancelPatrol()
                        AICFeature.MoveBackToFarmZone()
                    else
                        if not AICCombat.S.ClosestTarget or not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                            AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(now)
                        else
                            local LockedTarget = AICCombat.AcquireCombatTarget(now)
                            if LockedTarget then
                                AICCombat.S.ClosestTarget = LockedTarget
                            end
                        end

                        if AICCombat.S.ClosestTarget then
                            --// Combat outranks patrolling, so drop whatever the
                            --// patrol was doing rather than leaving a pause or a leg
                            --// chain to resume once the fight is over.
                            AICFeature.CancelPatrol()
                            AICCombat.MoveToGoblin(AICCombat.S.ClosestTarget)
                        elseif FeatureState.AutoPatrol.Enabled then
                            AICFeature.MoveToPatrol()
                        else
                            PatrolState.PatrolPosition = nil
                            AICFeature.S.FarmReturnPosition = nil
                            FaceOrientation.Enabled = false
                            Humanoid.AutoRotate = true
                            Humanoid:Move(Vector3.zero)
                        end
                    end
                end

            else
                --// No configured waypoints: preserve the original combat/patrol flow.
                local OutsideFarmZone = not AICCombatUtils.IsInsideFarmArea(RootPart.Position)
                local InFarmDeadzone = AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position)

                if FeatureState.ReturnToFarmZone.Enabled
                    and not FeatureState.IgnoreFarmZone.Enabled
                    and (OutsideFarmZone or InFarmDeadzone)
                then
                    AICCombat.S.ClosestTarget = nil
                    AICFeature.CancelPatrol()
                    AICFeature.MoveBackToFarmZone()
                else
                    if not AICCombat.S.ClosestTarget or not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                        AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(now)
                    else
                        local LockedTarget = AICCombat.AcquireCombatTarget(now)
                        if LockedTarget then
                            AICCombat.S.ClosestTarget = LockedTarget
                        end
                    end

                    if AICCombat.S.ClosestTarget then
                        --// Combat outranks patrolling, so drop whatever the patrol
                        --// was doing rather than leaving a pause or a leg chain to
                        --// resume once the fight is over.
                        AICFeature.CancelPatrol()
                        AICCombat.MoveToGoblin(AICCombat.S.ClosestTarget)
                    elseif FeatureState.AutoPatrol.Enabled then
                        AICFeature.MoveToPatrol()
                    else
                        PatrolState.PatrolPosition = nil
                        AICFeature.S.FarmReturnPosition = nil
                        FaceOrientation.Enabled = false
                        Humanoid.AutoRotate = true
                        Humanoid:Move(Vector3.zero)
                    end
                end
            end

            --// Jump. A waypoint sitting higher is not a reason on its own: a ramp
            --// climbs fine on foot, and hopping up one only costs speed. Probe for
            --// something actually in the way instead.
            if PlaceConfig and not FeatureState.AutoFind.Enabled and target then
                AICCombatUtils.DoJumpIfObstacle(target)
            end

            --// Swim Recovery
            if Humanoid:GetState() == Enum.HumanoidStateType.Swimming then
                AICCombatUtils.DoJump()
                return
            end

            if Humanoid.Sit == true then
                Humanoid.Sit = false
                AICCombatUtils.DoJump()
                return
            end

            --// Combat
            --// Never enter combat while a configured waypoint route is still active.
            local WaypointRouteFinished = not HasWaypoints
                or (tonumber(CONFIG.CURRENT_WAYPOINT_TARGET) or 1) > #PlaceConfig.WAYPOINTS

            if WaypointRouteFinished
                and (FeatureState.AutoFind.Enabled or not HasWaypoints or (AICCombat.S.ClosestTarget and not FeatureState.IgnoreFarmZone.Enabled)) then
                if AICCombat.S.ClosestTarget then
                    if not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                        AICCombat.S.ClosestTarget = nil
                        return
                    end

                    if not AICCombat.IsCombatTargetValid(AICCombat.S.ClosestTarget) then
                        FaceOrientation.Enabled = false
                        Humanoid.AutoRotate = true
                        Humanoid:Move(Vector3.zero)
                        return
                    end

                    if (not AICFeature.S.Equipped or (MainWeld.Part1 and MainWeld.Part1.Name == "UpperTorso"))
                        and now - AICFeature.S.LAST_EQUIP_TIME >= CONFIG.EQUIP_TOGGLE_COOLDOWN
                    then
                        AICFeature.S.Equipped = true
                        AICFeature.S.LAST_EQUIP_TIME = now

                        InputBindableFunction:Invoke(
                            "EquipButton",
                            Enum.UserInputState.Begin
                        )

                        return
                    end

                    local MobHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")
                    local MobRoot     = AICCombat.S.ClosestTarget:FindFirstChild("HumanoidRootPart")

                    if MobHumanoid and MobRoot and MobHumanoid.Health > 0 then
                        AICCombat.PerformCombatActions(AICCombat.S.ClosestTarget, now)
                    else
                        AICCombat.S.ValidMobs[AICCombat.S.ClosestTarget] = nil
                        AICCombat.S.ClosestTarget = nil
                    end
                end
            else
                if now - AICFeature.S.LAST_INTERACTION_TIME >= CONFIG.INTERACTION_INTERVAL then
                    AICFeature.S.LAST_INTERACTION_TIME = now

                    InputBindableFunction:Invoke(
                        "InteractButton",
                        Enum.UserInputState.Begin
                    )
                end
            end
        end
        AICFeature.updateCharacter()
        table.clear(AICCombat.S.ValidMobs)
        AICCombat.S.ClosestTarget = nil
        return
    end

    if Humanoid.Health <= 0 then
        AICDebug.ResetDebugWaypoints()
        CONFIG.CURRENT_WAYPOINT_TARGET = 1
        table.clear(AICCombat.S.ValidMobs)
        AICCombat.S.ClosestTarget = nil
        return
    end

    if now - AICUI.S.LAST_TEXT_UPDATE_TIME >= CONFIG.TEXT_UPDATE_INTERVAL then
        AICUI.S.LAST_TEXT_UPDATE_TIME = now
        AICUI.updatePlayTime()
        AICUI.updateEventCurrency()

        UIRef.WayPointLabel.Text = "WAYPOINTS:  ".. CONFIG.CURRENT_WAYPOINT_TARGET .. "/" .. (PlaceConfig and #PlaceConfig.WAYPOINTS or 0)
        UIRef.WalkSpeedLabel.Text = "WALKSPEED:  " .. tostring(math.floor(Humanoid.WalkSpeed + 0.5))
        UIRef.DeathLabel.Text = "DEATH:  " .. tostring(AICFeature.S.DEATH_COUNT)
    end

    if FeatureState.DebugVisualizer.Enabled then
        AICDebug.UpdateDebugWaypointColors()
    end

    --// Feeds the jump logic. Only counts while the character is actually
    --// trying to move, so standing still on purpose is not read as stuck.
    AICCombatUtils.UpdateStuckTracker(now, Humanoid.MoveDirection.Magnitude > 0.1)

    --// Realtime Mob Validation
    if now - AICCombat.S.LAST_MOB_VALIDATION_TIME >= CONFIG.MOB_VALIDATION_INTERVAL then
        AICCombat.S.LAST_MOB_VALIDATION_TIME = now
        AICCombat.UpdateValidMobs()
    end

    if not AICFeature.S.Enabled then
        FaceOrientation.Enabled = false
        Humanoid.AutoRotate = true
        Humanoid:Move(Vector3.zero)
        return
    end

    if not InputBindableFunction then
        InputBindableFunction = PlayerGui:FindFirstChild("InputBindableFunction", true) :: BindableFunction
        Runtime:SetInputBindableFunction(InputBindableFunction)
        return
    end

    local PlayerStats = Player:FindFirstChild("PlayerStats")
    local Sword = Character:FindFirstChild("Sword")

    if not Sword or not Sword:FindFirstChild("MainWeld", true) or not PlayerStats then
        return
    end

    local MainWeld = Sword:FindFirstChild("MainWeld", true)

    if AICFeature.HandleDeadzoneEscape() then
        return
    end

    --// Emergency Retreat
    local RetreatHealthPercent = math.clamp(tonumber(CONFIG.RETREAT_HEALTH_PERCENT) or 40, 30, 80)
    local AutoHealHealthPercent = math.clamp(tonumber(CONFIG.AUTO_HEAL_HEALTH_PERCENT) or 65, 30, 80)
    local RetreatHealthRatio = RetreatHealthPercent / 100
    local AutoHealHealthRatio = AutoHealHealthPercent / 100
    local RecoverHealthPercent = math.min(95, math.max(70, RetreatHealthPercent + 10))
    local EmergencyHealth = Humanoid.Health <= Humanoid.MaxHealth * RetreatHealthRatio
    local ShouldHeal      = Humanoid.Health <= Humanoid.MaxHealth * AutoHealHealthRatio

    --// Watches every nearby mob rather than only the current target, and
    --// latches for a short hold so a flickering sound or emitter cannot drop
    --// the dodge partway through.
    local EnemyUsingSkill = AICCombat.UpdateSkillThreat(now)

    if EnemyUsingSkill then
        AICCombat.S.RETREATING = true
    end

    --// Execute: a target this close to death is finished instead of retreated
    --// from, at any health of our own. An enemy skill still overrides it,
    --// because eating a skill to land one more hit is not a good trade.
    local ExecuteCharge = false
    local ExecutePercent = math.clamp(tonumber(CONFIG.EXECUTE_CHARGE_HP_PERCENT) or 0, 0, 90)

    if ExecutePercent > 0 and not EnemyUsingSkill and AICCombat.S.ClosestTarget then
        local TargetHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")

        if TargetHumanoid
            and TargetHumanoid.MaxHealth > 0
            and TargetHumanoid.Health > 0
        then
            ExecuteCharge =
                (TargetHumanoid.Health / TargetHumanoid.MaxHealth) * 100 <= ExecutePercent
        end
    end

    --// Retreat is a health decision only. The old build also entered retreat
    --// whenever WalkSpeed had not been raised yet, but RenderStepped restores
    --// WalkSpeed every frame, so that clause only produced random retreats.
    if ExecuteCharge then
        AICCombat.S.RETREATING = false
    elseif EmergencyHealth then
        AICCombat.S.RETREATING = true
    elseif AICCombat.S.RETREATING and Humanoid.Health >= Humanoid.MaxHealth * (RecoverHealthPercent / 100) and not EnemyUsingSkill then
        AICCombat.S.RETREATING = false

        --// Re-acquire a valid target immediately after healing so the
        --// combat loop does not wait for another target cycle.
        if not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
            AICCombat.S.ClosestTarget = AICCombat.GetClosestGoblin()
        end
    end

    if AICCombat.S.RETREATING then
        --// PlayerStats is already resolved above in this same handler.
        local UseConsumable = Replicated:FindFirstChild("UseConsumable", true)

        AICCombat.RetreatFromGoblins(EnemyUsingSkill)

        local LastConsumed = PlayerStats and PlayerStats:FindFirstChild("LastConsumed")
        local WantsConsume = UseConsumable
            and LastConsumed
            and LastConsumed.Value ~= ""
            and (EmergencyHealth or ShouldHeal)
            and now - AICFeature.S.LAST_CONSUME_TIME >= CONFIG.CONSUME_INTERVAL
            --// Never stop to drink mid-dodge. Getting out of the skill first
            --// is worth more than the heal, and sheathing costs an animation.
            and not EnemyUsingSkill

        --// Sheathe only when a potion is actually about to be drunk. The old
        --// build sheathed on every retreat frame and drew again as soon as
        --// the retreat ended, which is where the constant draw/sheathe came
        --// from, and each toggle also threw away the frame it happened on.
        if WantsConsume
            and InputBindableFunction
            and (AICFeature.S.Equipped or (MainWeld.Part1 and MainWeld.Part1.Name ~= "UpperTorso"))
            and now - AICFeature.S.LAST_EQUIP_TIME >= CONFIG.EQUIP_TOGGLE_COOLDOWN
        then
            AICFeature.S.Equipped = false
            AICFeature.S.LAST_EQUIP_TIME = now

            InputBindableFunction:Invoke(
                "EquipButton",
                Enum.UserInputState.Begin
            )

            return
        end

        if WantsConsume and not AICFeature.S.Equipped then
            AICFeature.S.LAST_CONSUME_TIME = now
            UseConsumable:InvokeServer(LastConsumed.Value)
        end

        return
    end

    --// Enemy skill retreat speed is temporary. Once retreating ends,
    --// return to the normal movement cap on the next heartbeat.
    if not EnemyUsingSkill and Humanoid.WalkSpeed > CONFIG.MAXIMUM_WALKSPEED then
        Humanoid.WalkSpeed = CONFIG.MAXIMUM_WALKSPEED
    end

    --// Player Check
    --// Whitelisted players are ignored entirely, so a server holding only
    --// them is left alone. Anyone else is blocked individually and then the
    --// server is abandoned; the whole lobby is no longer blocked one by one.
    if AICFeature.S.BlockEnabled then
        local Intruder = nil

        for _, plr in Players:GetPlayers() do
            if plr ~= Player and not AICFeature.IsWhitelisted(plr.UserId) then
                Intruder = plr
                break
            end
        end

        if Intruder then
            if not AICFeature.isBlocked(Intruder.UserId) then
                AICFeature.promptBlockPlayer(Intruder)
                return
            end

            AICFeature.S.BlockCache[Intruder.UserId] = nil
            AICFeature.TeleportToPlace()
            return
        end
    end

    --// Play Time
    if workspace.DistributedGameTime >= CONFIG.MAX_SERVER_AGE then
        AICFeature.TeleportToPlace()
        return
    end

    --// Movement
    --// Waypoint route always has priority over combat/patrol.
    --// Combat target acquisition is completely disabled until the route is finished.
    local HasWaypoints = PlaceConfig and type(PlaceConfig.WAYPOINTS) == "table" and #PlaceConfig.WAYPOINTS > 0
    local WaypointIndex = tonumber(CONFIG.CURRENT_WAYPOINT_TARGET) or 1
    local target = nil

    if HasWaypoints then
        if WaypointIndex < 1 then
            WaypointIndex = 1
            CONFIG.CURRENT_WAYPOINT_TARGET = 1
        end

        local WaypointCount = #PlaceConfig.WAYPOINTS
        local AtLastWaypoint = WaypointIndex > WaypointCount
        target = not AtLastWaypoint and PlaceConfig.WAYPOINTS[WaypointIndex] or nil

        --// Route mode: never let combat target state leak into waypoint movement.
        if not FeatureState.AutoFind.Enabled and target then
            AICCombat.S.ClosestTarget = nil
            AICCombat.S.TargetPath = nil
            AICCombat.S.TargetPathMob = nil
            AICCombat.S.TargetApproachMob = nil
            AICCombat.S.TargetApproachPosition = nil
            AICCombat.S.RETREATING = false

            local WaypointOffset = target - RootPart.Position
            local WaypointHorizontalDistance = Vector3.new(
                WaypointOffset.X,
                0,
                WaypointOffset.Z
            ).Magnitude
            local WaypointVerticalDistance = math.abs(WaypointOffset.Y)
            local ReachDistance = tonumber(PlaceConfig.REACH_DISTANCE) or 5

            if WaypointHorizontalDistance <= ReachDistance
                and WaypointVerticalDistance <= math.max(ReachDistance, CONFIG.JUMP_HEIGHT + 2)
            then
                CONFIG.CURRENT_WAYPOINT_TARGET = WaypointIndex + 1
                AICCombatUtils.S.LAST_STUCK_POSITION = nil
                AICCombatUtils.S.LAST_STUCK_TIME = now
                AICDebug.UpdateDebugWaypointColors()

                WaypointIndex = CONFIG.CURRENT_WAYPOINT_TARGET
                target = PlaceConfig.WAYPOINTS[WaypointIndex]
            end

            if target then
                FaceOrientation.Enabled = false
                Humanoid.AutoRotate = true
                Humanoid:MoveTo(target)
            end

            if now - AICCombatUtils.S.LAST_STUCK_TIME >= CONFIG.STUCK_CHECK_INTERVAL then
                AICCombatUtils.S.LAST_STUCK_TIME = now
                if AICCombatUtils.S.LAST_STUCK_POSITION
                    and (RootPart.Position - AICCombatUtils.S.LAST_STUCK_POSITION).Magnitude < 1
                then
                    AICCombatUtils.DoJump()
                else
                    AICCombatUtils.S.LAST_STUCK_POSITION = RootPart.Position
                end
            end

        else
            --// Final waypoint reached: only now allow farm-zone return/combat/patrol.
            local OutsideFarmZone = not AICCombatUtils.IsInsideFarmArea(RootPart.Position)
            local InFarmDeadzone = AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position)

            if FeatureState.ReturnToFarmZone.Enabled
                and not FeatureState.IgnoreFarmZone.Enabled
                and (OutsideFarmZone or InFarmDeadzone)
            then
                AICCombat.S.ClosestTarget = nil
                AICFeature.CancelPatrol()
                AICFeature.MoveBackToFarmZone()
            else
                if not AICCombat.S.ClosestTarget or not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                    AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(now)
                else
                    local LockedTarget = AICCombat.AcquireCombatTarget(now)
                    if LockedTarget then
                        AICCombat.S.ClosestTarget = LockedTarget
                    end
                end

                if AICCombat.S.ClosestTarget then
                    --// Combat outranks patrolling, so drop whatever the
                    --// patrol was doing rather than leaving a pause or a leg
                    --// chain to resume once the fight is over.
                    AICFeature.CancelPatrol()
                    AICCombat.MoveToGoblin(AICCombat.S.ClosestTarget)
                elseif FeatureState.AutoPatrol.Enabled then
                    AICFeature.MoveToPatrol()
                else
                    PatrolState.PatrolPosition = nil
                    AICFeature.S.FarmReturnPosition = nil
                    FaceOrientation.Enabled = false
                    Humanoid.AutoRotate = true
                    Humanoid:Move(Vector3.zero)
                end
            end
        end

    else
        --// No configured waypoints: preserve the original combat/patrol flow.
        local OutsideFarmZone = not AICCombatUtils.IsInsideFarmArea(RootPart.Position)
        local InFarmDeadzone = AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position)

        if FeatureState.ReturnToFarmZone.Enabled
            and not FeatureState.IgnoreFarmZone.Enabled
            and (OutsideFarmZone or InFarmDeadzone)
        then
            AICCombat.S.ClosestTarget = nil
            AICFeature.CancelPatrol()
            AICFeature.MoveBackToFarmZone()
        else
            if not AICCombat.S.ClosestTarget or not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(now)
            else
                local LockedTarget = AICCombat.AcquireCombatTarget(now)
                if LockedTarget then
                    AICCombat.S.ClosestTarget = LockedTarget
                end
            end

            if AICCombat.S.ClosestTarget then
                --// Combat outranks patrolling, so drop whatever the patrol
                --// was doing rather than leaving a pause or a leg chain to
                --// resume once the fight is over.
                AICFeature.CancelPatrol()
                AICCombat.MoveToGoblin(AICCombat.S.ClosestTarget)
            elseif FeatureState.AutoPatrol.Enabled then
                AICFeature.MoveToPatrol()
            else
                PatrolState.PatrolPosition = nil
                AICFeature.S.FarmReturnPosition = nil
                FaceOrientation.Enabled = false
                Humanoid.AutoRotate = true
                Humanoid:Move(Vector3.zero)
            end
        end
    end

    --// Jump. A waypoint sitting higher is not a reason on its own: a ramp
    --// climbs fine on foot, and hopping up one only costs speed. Probe for
    --// something actually in the way instead.
    if PlaceConfig and not FeatureState.AutoFind.Enabled and target then
        AICCombatUtils.DoJumpIfObstacle(target)
    end

    --// Swim Recovery
    if Humanoid:GetState() == Enum.HumanoidStateType.Swimming then
        AICCombatUtils.DoJump()
        return
    end

    if Humanoid.Sit == true then
        Humanoid.Sit = false
        AICCombatUtils.DoJump()
        return
    end

    --// Combat
    --// Never enter combat while a configured waypoint route is still active.
    local WaypointRouteFinished = not HasWaypoints
        or (tonumber(CONFIG.CURRENT_WAYPOINT_TARGET) or 1) > #PlaceConfig.WAYPOINTS

    if WaypointRouteFinished
        and (FeatureState.AutoFind.Enabled or not HasWaypoints or (AICCombat.S.ClosestTarget and not FeatureState.IgnoreFarmZone.Enabled)) then
        if AICCombat.S.ClosestTarget then
            if not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                AICCombat.S.ClosestTarget = nil
                return
            end

            if not AICCombat.IsCombatTargetValid(AICCombat.S.ClosestTarget) then
                FaceOrientation.Enabled = false
                Humanoid.AutoRotate = true
                Humanoid:Move(Vector3.zero)
                return
            end

            if (not AICFeature.S.Equipped or (MainWeld.Part1 and MainWeld.Part1.Name == "UpperTorso"))
                and now - AICFeature.S.LAST_EQUIP_TIME >= CONFIG.EQUIP_TOGGLE_COOLDOWN
            then
                AICFeature.S.Equipped = true
                AICFeature.S.LAST_EQUIP_TIME = now

                InputBindableFunction:Invoke(
                    "EquipButton",
                    Enum.UserInputState.Begin
                )

                return
            end

            local MobHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")
            local MobRoot     = AICCombat.S.ClosestTarget:FindFirstChild("HumanoidRootPart")

            if MobHumanoid and MobRoot and MobHumanoid.Health > 0 then
                AICCombat.PerformCombatActions(AICCombat.S.ClosestTarget, now)
            else
                AICCombat.S.ValidMobs[AICCombat.S.ClosestTarget] = nil
                AICCombat.S.ClosestTarget = nil
            end
        end
    else
        if now - AICFeature.S.LAST_INTERACTION_TIME >= CONFIG.INTERACTION_INTERVAL then
            AICFeature.S.LAST_INTERACTION_TIME = now

            InputBindableFunction:Invoke(
                "InteractButton",
                Enum.UserInputState.Begin
            )
        end
    end
        end


        AICFeature.updateCharacter = function(...) return Feature.updateCharacter(...) end
        AICFeature.GetPlayerStatValue = function(...) return Feature.GetPlayerStatValue(...) end
        AICFeature.GetPlayerLevel = function(...) return Feature.GetPlayerLevel(...) end
        AICFeature.CreateToggleContainer = function(...) return Feature.CreateToggleContainer(...) end
        AICFeature.RegenStamina = function(...) return Feature.RegenStamina(...) end

        function Feature:CreateUI()
            if UIRef.FeatureSection and UIRef.FeatureSection.AddToggle then
                self.Button = AICUI.CreateFeature("Auto Farm", AICFeature.S.Enabled, function(Value)
                    AICFeature.S.Enabled = Value
                    FeatureState.AutoFarm.Enabled = Value
                    AICProfile.SaveActiveProfile()
                end)
                FeatureState.AutoFarm.Button = self.Button
            end
        end

        Feature:CreateUI()

        if UIRef.FeatureSection then
            UIRef.ExecuteChargeSlider = UIRef.FeatureSection:AddSlider(
                "Execute Charge at Enemy HP %",
                math.clamp(tonumber(CONFIG.EXECUTE_CHARGE_HP_PERCENT) or 0, 0, 90),
                0,
                90,
                function(Value)
                    CONFIG.EXECUTE_CHARGE_HP_PERCENT = math.clamp(math.floor(tonumber(Value) or 0), 0, 90)
                    AICProfile.QueueProfileSave()
                end
            )

            UIRef.RetreatHealthSlider = UIRef.FeatureSection:AddSlider(
                "Retreat At Health %",
                math.clamp(tonumber(CONFIG.RETREAT_HEALTH_PERCENT) or 40, 30, 80),
                30,
                80,
                function(Value)
                    CONFIG.RETREAT_HEALTH_PERCENT = math.clamp(math.floor(tonumber(Value) or 40), 30, 80)
                    AICProfile.QueueProfileSave()
                end
            )

            UIRef.AutoHealHealthSlider = UIRef.FeatureSection:AddSlider(
                "Auto Heal at HP",
                math.clamp(tonumber(CONFIG.AUTO_HEAL_HEALTH_PERCENT) or 65, 30, 80),
                30,
                80,
                function(Value)
                    CONFIG.AUTO_HEAL_HEALTH_PERCENT = math.clamp(math.floor(tonumber(Value) or 65), 30, 80)
                    AICProfile.QueueProfileSave()
                end
            )
        end

        if UIRef.StatusSection then
            UIRef.PlaceIDLabel = UIRef.StatusSection:AddLabel("PLACE ID       " .. tostring(game.PlaceId))
            UIRef.WalkSpeedLabel = UIRef.StatusSection:AddLabel("WALKSPEED      0")
            UIRef.WayPointLabel = UIRef.StatusSection:AddLabel("WAYPOINTS:  0/" .. ((Runtime:GetPlaceConfig() and #Runtime:GetPlaceConfig().WAYPOINTS) or 0))
            UIRef.EventCurrencyLabel = UIRef.StatusSection:AddLabel("EVENT CURRENCY  0")
            UIRef.ServerAgeLabel = UIRef.StatusSection:AddLabel("PLAY TIME      00:00:00")
            UIRef.PositionLabel = UIRef.StatusSection:AddLabel("POSITION       --")
            UIRef.DeathLabel = UIRef.StatusSection:AddLabel("DEATH          0")
            UIRef.ExpLabel = UIRef.StatusSection:AddLabel("EXP            0/0")
        end
        return Feature
    end,
}
