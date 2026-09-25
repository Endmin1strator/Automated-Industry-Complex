return {
    Name = "Targeting",
    Dependencies = {"Runtime", "CombatUtils", "EnemyPriority", "Components"},
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

        local Module = Context.AICCombat
        function AICCombat.ResetTargetReposition()
            AICCombat.S.TargetUnreachableSince   = nil
            AICCombat.S.TargetApproachPosition   = nil
            AICCombat.S.TargetApproachMob        = nil
            AICCombat.S.LastTargetRepositionTime = 0
            AICCombat.S.CACHED_SAFECOMBAT_POSITION = nil
            AICCombat.S.CACHED_SAFECOMBAT_TARGET = nil
            AICCombat.S.LastAttackerCombatMob = nil
            AICCombat.S.LastAttackerCombatPosition = nil
            AICCombat.S.LastAttackerCombatSwitchTime = 0
            AICCombat.S.LAST_SAFECOMBAT_TIME = 0
            AICCombat.S.LastDirectPathTarget = nil
            AICCombat.S.LastDirectPathPosition = nil
            AICCombat.S.CombatBladeCache = {}
        end
        function AICCombat.ResetTargetState()
            AICCombat.S.ClosestTarget = nil
            AICCombat.ClearUnreachableMobs()
            table.clear(AICCombat.S.ValidMobs)
            table.clear(AICCombat.S.CombatGroupCache)
            AICCombat.S.COMBAT_TARGET_LOST_SINCE = nil
            AICCombat.S.COMBAT_TARGET_SCORE = math.huge
            AICCombat.S.LAST_COMBAT_TARGET_CHECK = 0
            AICCombat.S.COMBAT_ATTACK_PHASE = 0
            AICCombat.S.COMBAT_NEXT_ATTACK_TIME = 0
            AICCombat.S.COMBAT_NEXT_SKILL_TIME = 0
            AICCombat.ResetTargetReposition()
        end
        
        ------------------------------------------------------------------------
        --// AICEntity  ::  mob discovery, validation, priority, target selection
        --// 15 function(s)
        ------------------------------------------------------------------------
        function AICCombat.GetDetectedEnemyEntities()
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder then
                return {}
            end
        
            local EntitySet = {}
        
            for _, Mob in MobFolder:GetChildren() do
                if not Mob:IsA("Model") then
                    continue
                end
        
                local Config = Mob:FindFirstChild("Config")
        
                if not Config then
                    continue
                end
        
                local Entity = Config:FindFirstChild("Entity")
        
                if not Entity then
                    continue
                end
        
                if typeof(Entity.Value) ~= "string" or Entity.Value == "" then
                    continue
                end
        
                EntitySet[Entity.Value] = true
            end
        
            local Result = {}
        
            for EntityName in EntitySet do
                table.insert(Result, EntityName)
            end
        
            table.sort(Result, function(A, B)
                local APriority = table.find(CONFIG.TARGET_ENTITY_PRIORITY, A)
                local BPriority = table.find(CONFIG.TARGET_ENTITY_PRIORITY, B)
        
                if APriority and BPriority then
                    return APriority < BPriority
                end
        
                if APriority then
                    return true
                end
        
                if BPriority then
                    return false
                end
        
                return A < B
            end)
        
            return Result
        end
        function AICCombat.IsEntityInPriority(EntityName: string): boolean
            return table.find(CONFIG.TARGET_ENTITY_PRIORITY, EntityName) ~= nil
        end
        
        --// Raised whenever the set of mobs, or the entity a mob reports, changes.
        --// Nothing here knows who listens; the UI assigns OnMobSetChanged so the
        --// picker can rebuild without this module depending on the UI at all.
        function AICCombat.NotifyMobSetChanged()
            if AICCombat.OnMobSetChanged then
                AICCombat.OnMobSetChanged()
            end
        end
        function AICCombat.DisconnectMob(Mob)
            local Connections = AICCombat.S.MobConnections[Mob]
        
            if not Connections then
                return
            end
        
            for _, Connection in Connections do
                Connection:Disconnect()
            end
        
            AICCombat.S.MobConnections[Mob] = nil
            AICCombat.S.UnreachableMobs[Mob] = nil
            AICCombatUtils.S.BladePartCache[Mob] = nil
            AICCombat.S.CombatGroupCache[Mob] = nil
            AICCombat.S.CombatBladeCache[Mob] = nil
        end
        function AICCombat.WatchMob(Mob)
            if not Mob:IsA("Model") then
                return
            end
        
            AICCombat.DisconnectMob(Mob)
        
            local Connections = {}
            AICCombat.S.MobConnections[Mob] = Connections
        
            local function WatchConfig(Config)
                if not Config then
                    return
                end
        
                local Entity = Config:FindFirstChild("Entity")
        
                if Entity and Entity:IsA("StringValue") then
                    table.insert(Connections, Entity:GetPropertyChangedSignal("Value"):Connect(function()
                        AICCombat.NotifyMobSetChanged()
        
                        AICCombat.S.ValidMobs[Mob] = nil
        
                        if AICCombat.S.ClosestTarget == Mob and not AICCombat.IsEntityInPriority(Entity.Value) then
                            AICCombat.S.ClosestTarget = nil
                        end
                    end))
                end
        
                table.insert(Connections, Config.ChildAdded:Connect(function(Child)
                    if Child.Name ~= "Entity" then
                        return
                    end
        
                    if Child:IsA("StringValue") then
                        table.insert(Connections, Child:GetPropertyChangedSignal("Value"):Connect(function()
                            AICCombat.NotifyMobSetChanged()
                            AICCombat.S.ValidMobs[Mob] = nil
        
                            if AICCombat.S.ClosestTarget == Mob and not AICCombat.IsEntityInPriority(Child.Value) then
                                AICCombat.S.ClosestTarget = nil
                            end
                        end))
                    end
        
                    AICCombat.NotifyMobSetChanged()
                    AICCombat.S.ValidMobs[Mob] = nil
                end))
        
                table.insert(Connections, Config.ChildRemoved:Connect(function(Child)
                    if Child.Name == "Entity" then
                        AICCombat.S.ValidMobs[Mob] = nil
        
                        if AICCombat.S.ClosestTarget == Mob then
                            AICCombat.S.ClosestTarget = nil
                        end
        
                        AICCombat.NotifyMobSetChanged()
                    end
                end))
            end
        
            local Config = Mob:FindFirstChild("Config")
        
            if Config then
                WatchConfig(Config)
            end
        
            table.insert(Connections, Mob.ChildAdded:Connect(function(Child)
                if Child.Name == "Config" then
                    WatchConfig(Child)
                    AICCombat.NotifyMobSetChanged()
                    AICCombat.S.ValidMobs[Mob] = nil
                end
            end))
        
            table.insert(Connections, Mob.ChildRemoved:Connect(function(Child)
                if Child.Name == "Config" then
                    AICCombat.S.ValidMobs[Mob] = nil
        
                    if AICCombat.S.ClosestTarget == Mob then
                        AICCombat.S.ClosestTarget = nil
                    end
        
                    AICCombat.NotifyMobSetChanged()
                end
            end))
        
            AICCombat.NotifyMobSetChanged()
        end
        function AICCombat.WatchMobFolder(MobFolder)
            for _, Connection in AICCombat.S.MobFolderConnections do
                Connection:Disconnect()
            end
        
            table.clear(AICCombat.S.MobFolderConnections)
        
            for Mob in AICCombat.S.MobConnections do
                AICCombat.DisconnectMob(Mob)
            end
        
            for _, Mob in MobFolder:GetChildren() do
                AICCombat.WatchMob(Mob)
            end
        
            table.insert(AICCombat.S.MobFolderConnections, MobFolder.ChildAdded:Connect(function(Mob)
                AICCombat.WatchMob(Mob)
                AICCombat.NotifyMobSetChanged()
            end))
        
            table.insert(AICCombat.S.MobFolderConnections, MobFolder.ChildRemoved:Connect(function(Mob)
                AICCombat.DisconnectMob(Mob)
                AICCombat.S.ValidMobs[Mob] = nil
        
                if AICCombat.S.ClosestTarget == Mob then
                    AICCombat.S.ClosestTarget = nil
                end
        
                AICCombat.NotifyMobSetChanged()
            end))
        end
        
        --// Target Lock Validation
        --// Mobs with no route to them are remembered for a while. Dropping the
        --// target without this just hands the same unreachable mob straight back on
        --// the next selection, which is how the character ends up sprinting at a
        --// ledge it cannot climb for as long as the mob lives.
        function AICCombat.MarkMobUnreachable(Mob)
            if not Mob then
                return
            end
        
            AICCombat.S.UnreachableMobs[Mob] = os.clock() + (tonumber(CONFIG.UNREACHABLE_COOLDOWN) or 15)
        end
        function AICCombat.IsMobUnreachable(Mob)
            local Expiry = AICCombat.S.UnreachableMobs[Mob]
        
            if not Expiry then
                return false
            end
        
            if os.clock() >= Expiry then
                AICCombat.S.UnreachableMobs[Mob] = nil
                return false
            end
        
            return true
        end
        function AICCombat.ClearUnreachableMobs()
            table.clear(AICCombat.S.UnreachableMobs)
        end
        function AICCombat.IsTargetLockValid(Mob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Mob or not Mob:IsA("Model") then
                return false
            end
        
            if not Mob:IsDescendantOf(workspace) then
                return false
            end
        
            if not RootPart then
                return false
            end
        
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder or not Mob:IsDescendantOf(MobFolder) then
                return false
            end
        
            local Config = Mob:FindFirstChild("Config")
        
            if not Config then
                return false
            end
        
            local Entity = Config:FindFirstChild("Entity")
        
            if not Entity or not Entity:IsA("StringValue") then
                return false
            end
        
            if not AICCombat.IsEntityInPriority(Entity.Value) then
                return false
            end
        
            local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
            local MobRoot     = Mob:FindFirstChild("HumanoidRootPart")
        
            if not MobHumanoid or not MobRoot then
                return false
            end
        
            if MobHumanoid.Health <= 0 then
                return false
            end
        
            local Offset   = MobRoot.Position - RootPart.Position
            local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
            if CONFIG.DISTANCE_Y_CALCULATE then
                Distance = Offset.Magnitude
            end
        
            if Distance > CONFIG.MOB_DETECTION_DISTANCE then
                return false
            end
        
            if not AICCombatUtils.IsInsideFarmArea(MobRoot.Position) then
                return false
            end
        
            if AICCombatUtils.IsWaterAtPosition(MobRoot.Position, Mob) then
                return false
            end
        
            --// Recently proven to have no route. IsInsideFarmArea above already
            --// rejects anything outside the farm zone or inside a deadzone, unless
            --// Ignore Farm Zone is on.
            if AICCombat.IsMobUnreachable(Mob) then
                return false
            end
        
            return true
        end
        
        --// Validate Mob
        --// IsValidMob and IsTargetLockValid applied exactly the same 12 checks.
        --// Keeping two copies meant a rule change had to be made twice, so the
        --// cache filter now delegates to the single canonical implementation.
        function AICCombat.IsValidMob(Mob)
            return AICCombat.IsTargetLockValid(Mob)
        end
        
        --// Update Realtime Valid Mob List
        function AICCombat.UpdateValidMobs()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder or not RootPart then
                table.clear(AICCombat.S.ValidMobs)
        
                if AICCombat.S.ClosestTarget and not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                    AICCombat.S.ClosestTarget = nil
                end
        
                return
            end
        
            local CurrentMobs = {}
        
            for _, Mob in MobFolder:GetChildren() do
                CurrentMobs[Mob] = true
        
                if AICCombat.IsValidMob(Mob) then
                    AICCombat.S.ValidMobs[Mob] = true
                else
                    AICCombat.S.ValidMobs[Mob] = nil
                end
            end
        
            for Mob in AICCombat.S.ValidMobs do
                if not CurrentMobs[Mob] then
                    AICCombat.S.ValidMobs[Mob] = nil
                end
            end
        
            if AICCombat.S.ClosestTarget and not AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget) then
                AICCombat.S.ClosestTarget = nil
            end
        end
        
        --// Closest Visible Goblin
        function AICCombat.GetMobPriority(Mob)
            local Config = Mob:FindFirstChild("Config")
        
            if not Config then
                return nil
            end
        
            local Entity = Config:FindFirstChild("Entity")
        
            if not Entity then
                return nil
            end
        
            return table.find(CONFIG.TARGET_ENTITY_PRIORITY, Entity.Value)
        end
        
        --// Priority always decides first. Target Type only breaks ties between mobs
        --// of the same priority, and "Disabled" leaves that tie to distance, which
        --// is the original behaviour.
        function AICCombat.IsBetterTarget(Priority, Distance, Health, BestPriority, BestDistance, BestHealth)
            if Priority < BestPriority then
                return true
            end
        
            if Priority > BestPriority then
                return false
            end
        
            local Mode = tostring(CONFIG.TARGET_HP_MODE or "Disabled")
        
            if Mode == "Highest HP" then
                if Health > BestHealth then
                    return true
                end
        
                if Health < BestHealth then
                    return false
                end
            elseif Mode == "Lowest HP" then
                if Health < BestHealth then
                    return true
                end
        
                if Health > BestHealth then
                    return false
                end
            end
        
            return Distance < BestDistance
        end
        function AICCombat.GetClosestGoblin()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            local BestTarget   = nil
            local BestPriority = math.huge
            local BestDistance = math.huge
            local BestHealth   = nil
        
            --// Primary source: realtime validated mob cache.
            for Mob in AICCombat.S.ValidMobs do
                if not AICCombat.IsTargetLockValid(Mob) then
                    AICCombat.S.ValidMobs[Mob] = nil
                    continue
                end
        
                local Priority = AICCombat.GetMobPriority(Mob)
                local Distance = AICCombatUtils.GetMobDistance(Mob)
                local Health = AICCombatUtils.GetMobHealth(Mob)
        
                if Priority
                    and (not BestTarget
                        or AICCombat.IsBetterTarget(
                            Priority, Distance, Health,
                            BestPriority, BestDistance, BestHealth or 0
                        ))
                then
                    BestPriority = Priority
                    BestDistance = Distance
                    BestHealth = Health
                    BestTarget = Mob
                end
            end
        
            --// Fallback: scan the actual Mobs folder.
            --// This covers spawn/replication timing and prevents a transient
            --// validation failure from making the target completely invisible.
            if not BestTarget then
                local MobFolder = workspace:FindFirstChild("Mobs")
        
                if MobFolder then
                    for _, Mob in MobFolder:GetChildren() do
                        if AICCombat.IsTargetLockValid(Mob) then
                            local Priority = AICCombat.GetMobPriority(Mob)
                            local Distance = AICCombatUtils.GetMobDistance(Mob)
                            local Health = AICCombatUtils.GetMobHealth(Mob)
        
                            if Priority
                                and (not BestTarget
                                    or AICCombat.IsBetterTarget(
                                        Priority, Distance, Health,
                                        BestPriority, BestDistance, BestHealth or 0
                                    ))
                            then
                                BestPriority = Priority
                                BestDistance = Distance
                                BestHealth = Health
                                BestTarget = Mob
                            end
                        end
                    end
                end
            end
        
            return BestTarget
        end
        
        --// Detect a secondary mob approaching from the side or behind.
        --// The primary target is never replaced by this system.
        function AICCombat.GetNearbyThreatMob(TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetMob then
                return nil
            end
        
            local BestThreat = nil
            local BestDistance = math.huge
            local LookVector = Vector3.new(RootPart.CFrame.LookVector.X, 0, RootPart.CFrame.LookVector.Z)
        
            if LookVector.Magnitude <= 0.01 then
                return nil
            end
        
            LookVector = LookVector.Unit
        
            for Mob in AICCombat.S.ValidMobs do
                if Mob == TargetMob then
                    continue
                end
        
                local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
                local MobRoot = Mob:FindFirstChild("HumanoidRootPart")
        
                if not MobHumanoid or not MobRoot or MobHumanoid.Health <= 0 then
                    continue
                end
        
                local Offset = MobRoot.Position - RootPart.Position
                local HorizontalOffset = Vector3.new(Offset.X, 0, Offset.Z)
                local Distance = HorizontalOffset.Magnitude
        
                if Distance <= 0.01 or Distance > CONFIG.THREAT_DETECTION_DISTANCE then
                    continue
                end
        
                local Direction = HorizontalOffset.Unit
                local Dot = math.clamp(LookVector:Dot(Direction), -1, 1)
                local Angle = math.deg(math.acos(Dot))
        
                --// 0 = directly in front, 90 = side, 180 = behind.
                if Angle >= CONFIG.THREAT_ANGLE and Distance < BestDistance then
                    BestThreat = Mob
                    BestDistance = Distance
                end
            end
        
            return BestThreat, BestDistance
        end
        function AICCombat.GetThreatEscapePosition(TargetMob, ThreatMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not ThreatMob then
                return nil
            end
        
            local ThreatRoot = ThreatMob:FindFirstChild("HumanoidRootPart")
            local TargetRoot = TargetMob and TargetMob:FindFirstChild("HumanoidRootPart")
        
            if not ThreatRoot or not TargetRoot then
                return nil
            end
        
            local Origin = RootPart.Position
            local Away = Origin - ThreatRoot.Position
            local AwayDirection = Vector3.new(Away.X, 0, Away.Z)
        
            if AwayDirection.Magnitude <= 0.01 then
                return nil
            end
        
            AwayDirection = AwayDirection.Unit
        
            --// Try several directions instead of blindly retreating straight back.
            --// This prevents Safe Distance from pushing the player into a wall,
            --// corner, or narrow gap when the direct retreat path is blocked.
            local Directions = {
                AwayDirection,
                CFrame.fromAxisAngle(Vector3.yAxis, math.rad(45)):VectorToWorldSpace(AwayDirection),
                CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-45)):VectorToWorldSpace(AwayDirection),
                CFrame.fromAxisAngle(Vector3.yAxis, math.rad(90)):VectorToWorldSpace(AwayDirection),
                CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-90)):VectorToWorldSpace(AwayDirection),
                CFrame.fromAxisAngle(Vector3.yAxis, math.rad(135)):VectorToWorldSpace(AwayDirection),
                CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-135)):VectorToWorldSpace(AwayDirection),
            }
        
            local CurrentTargetDistance = AICCombatUtils.GetHorizontalDistance(Origin, TargetRoot.Position)
            local BestPosition = nil
            local BestScore = math.huge
        
            for Index, Direction in ipairs(Directions) do
                Direction = Vector3.new(Direction.X, 0, Direction.Z)
        
                if Direction.Magnitude <= 0.01 then
                    continue
                end
        
                Direction = Direction.Unit
        
                --// Prefer shorter movement when multiple escape directions are safe.
                local Candidate = Origin + Direction * CONFIG.THREAT_ESCAPE_DISTANCE
        
                if not AICCombatUtils.IsInsideFarmArea(Candidate)
                    or AICCombatUtils.IsWaterAtPosition(Candidate, TargetMob)
                    or AICCombatUtils.IsPathThroughWater(Candidate)
                    or AICCombatUtils.IsPathThroughDeadzone(Candidate)
                    or AICCombat.IsPathThroughBladeGroupDanger(Candidate, TargetMob)
                    or not AICCombatUtils.IsEscapePathClear(Candidate)
                then
                    continue
                end
        
                --// Keep enough space from the threat while avoiding a huge
                --// increase in distance from the primary target.
                local ThreatDistance = AICCombatUtils.GetHorizontalDistance(Candidate, ThreatRoot.Position)
                local TargetDistance = AICCombatUtils.GetHorizontalDistance(Candidate, TargetRoot.Position)
        
                --// Penalize positions that move much farther from the primary target.
                local TargetDistancePenalty = math.max(0, TargetDistance - CurrentTargetDistance) * 0.35
        
                --// Prefer directions closer to directly away from the threat.
                local DirectionPenalty = (1 - math.clamp(AwayDirection:Dot(Direction), -1, 1)) * 2
        
                local Score = TargetDistancePenalty + DirectionPenalty + Index * 0.01
        
                --// The old build tested THREAT_DETECTION_DISTANCE first and then
                --// ENEMY_ATTACK_SAFE_DISTANCE in an elseif with an identical body.
                --// The first condition is a subset of the second, so only the
                --// smaller threshold ever decided anything.
                if ThreatDistance > CONFIG.ENEMY_ATTACK_SAFE_DISTANCE
                    and Score < BestScore
                then
                    BestScore = Score
                    BestPosition = Candidate
                end
            end
        
            return BestPosition
        end
        
        --// Combat Target Validation
        function AICCombat.IsCombatTargetValid(Mob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Mob or not Mob:IsA("Model") then
                return false
            end
        
            if not Mob:IsDescendantOf(workspace) then
                return false
            end
        
            if not RootPart then
                return false
            end
        
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder
                or not Mob:IsDescendantOf(MobFolder)
            then
                return false
            end
        
            local Config      = Mob:FindFirstChild("Config")
            local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
            local MobRoot     = Mob:FindFirstChild("HumanoidRootPart")
        
            if not Config
                or not MobHumanoid
                or not MobRoot
            then
                return false
            end
        
            local Entity = Config:FindFirstChild("Entity")
        
            if not Entity
                or not Entity:IsA("StringValue")
            then
                return false
            end
        
            if not AICCombat.IsEntityInPriority(Entity.Value) then
                return false
            end
        
            if MobHumanoid.Health <= 0 then
                return false
            end
        
            local Offset = MobRoot.Position - RootPart.Position
            local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
            if CONFIG.DISTANCE_Y_CALCULATE then
                Distance = Offset.Magnitude
            end
        
            return Distance <= CONFIG.COMBAT_ENGAGE_MAX_DISTANCE
        end
        
        ------------------------------------------------------------------------
        --// AICNav  ::  combat positioning, pathfinding, retreat, patrol
        --// 26 function(s)
        ------------------------------------------------------------------------
        --// Find a short detour when another player is physically blocking the route.
        function AICCombat.GetOtherPlayerDetourPosition(TargetPosition, Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition then
                return nil
            end
        
            local Origin = RootPart.Position
            local Direction = TargetPosition - Origin
            if Direction.Magnitude <= 0.01 then
                return nil
            end
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = {
                Character,
                Goblin,
            }
            if AICCombatUtils.S.DebugFolder then
                table.insert(RaycastParams.FilterDescendantsInstances, AICCombatUtils.S.DebugFolder)
            end
        
            local Hit = workspace:Raycast(Origin, Direction, RaycastParams)
            if not Hit then
                return nil
            end
        
            local Blocker = Hit.Instance and Hit.Instance:FindFirstAncestorOfClass("Model")
            local BlockerPlayer = Blocker and Players:GetPlayerFromCharacter(Blocker)
            if not BlockerPlayer or BlockerPlayer == Player then
                return nil
            end
        
            local BlockerRoot = Blocker:FindFirstChild("HumanoidRootPart")
            if not BlockerRoot then
                return nil
            end
        
            local FlatDirection = Vector3.new(Direction.X, 0, Direction.Z)
            if FlatDirection.Magnitude <= 0.01 then
                return nil
            end
            FlatDirection = FlatDirection.Unit
        
            local Side = Vector3.new(-FlatDirection.Z, 0, FlatDirection.X)
            local DetourDistance = CONFIG.OTHER_PLAYER_DETOUR_DISTANCE
            local Candidates = {
                BlockerRoot.Position + Side * DetourDistance,
                BlockerRoot.Position - Side * DetourDistance,
            }
        
            for _, Candidate in ipairs(Candidates) do
                local GroundCandidate = AICCombatUtils.GetPatrolGroundPosition(Candidate) or Candidate
                if AICCombatUtils.IsInsideFarmArea(GroundCandidate)
                    and not AICCombatUtils.IsInsideFarmDeadzone(GroundCandidate)
                    and not AICCombatUtils.IsWaterAtPosition(GroundCandidate, Goblin)
                    and not AICCombatUtils.IsPathThroughWater(GroundCandidate)
                    and not AICCombatUtils.IsPathThroughDeadzone(GroundCandidate)
                then
                    local ToDetour = GroundCandidate - Origin
                    local DetourHit = workspace:Raycast(Origin, ToDetour, RaycastParams)
                    if not DetourHit then
                        return GroundCandidate
                    end
                end
            end
        
            return nil
        end
        
        --// Get a safe combat position around the Target.
        function AICCombat.AcquireCombatTarget(now)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            if AICCombat.S.ClosestTarget
                and AICCombat.IsTargetLockValid(AICCombat.S.ClosestTarget)
                and now - AICCombat.S.LAST_COMBAT_TARGET_CHECK < CONFIG.COMBAT_TARGET_RECHECK
            then
                return AICCombat.S.ClosestTarget
            end
        
            AICCombat.S.LAST_COMBAT_TARGET_CHECK = now
        
            local Current = AICCombat.S.ClosestTarget
            local Candidate = AICCombat.GetClosestGoblin()
        
            if Current and AICCombat.IsTargetLockValid(Current) then
                local CurrentDistance = AICCombatUtils.GetMobDistance(Current)
                local CandidateDistance = Candidate and AICCombatUtils.GetMobDistance(Candidate) or math.huge
                local CurrentPriority = AICCombat.GetMobPriority(Current) or math.huge
                local CandidatePriority = Candidate and (AICCombat.GetMobPriority(Candidate) or math.huge) or math.huge
        
                local BetterPriority = CandidatePriority < CurrentPriority
                local MeaningfullyCloser =
                    CandidateDistance + CONFIG.COMBAT_STICKY_DISTANCE_BONUS < CurrentDistance
        
                if not BetterPriority and not MeaningfullyCloser then
                    return Current
                end
            end
        
            if Candidate then
                AICCombat.S.COMBAT_TARGET_LOST_SINCE = nil
                AICCombat.S.COMBAT_TARGET_SCORE = AICCombatUtils.GetMobDistance(Candidate)
                return Candidate
            end
        
            if Current and AICCombat.IsTargetLockValid(Current) then
                if not AICCombat.S.COMBAT_TARGET_LOST_SINCE then
                    AICCombat.S.COMBAT_TARGET_LOST_SINCE = now
                end
        
                if now - AICCombat.S.COMBAT_TARGET_LOST_SINCE <= CONFIG.COMBAT_TARGET_GRACE then
                    return Current
                end
            end
        
            AICCombat.S.COMBAT_TARGET_LOST_SINCE = nil
            AICCombat.S.COMBAT_TARGET_SCORE = math.huge
            return nil
        end
        
        --// Get All Living Goblins

        function Module:CreateUI()
            if UIRef.TargetSection then
                UIRef.SafeEnemyRangeSlider = UIRef.TargetSection:AddSlider(
                    "Safe Enemy Range",
                    math.clamp(tonumber(CONFIG.SAFE_ENEMY_RANGE) or 4, 0, 30),
                    0,
                    30,
                    function(Value)
                        CONFIG.SAFE_ENEMY_RANGE = math.clamp(tonumber(Value) or 4, 0, 30)
                        AICProfile.QueueProfileSave()
                    end
                )
            end
        end

        Module:CreateUI()

        AICCombat.S.ExistingMobFolder = workspace:FindFirstChild("Mobs")

        if AICCombat.S.ExistingMobFolder then
            AICCombat.WatchMobFolder(AICCombat.S.ExistingMobFolder)
        end

        workspace.ChildAdded:Connect(function(Child)
            if Child.Name ~= "Mobs" then
                return
            end

            AICCombat.WatchMobFolder(Child)
            AICUI.RefreshEnemyPicker()
        end)

        workspace.ChildRemoved:Connect(function(Child)
            if Child.Name ~= "Mobs" then
                return
            end

            for _, Connection in AICCombat.S.MobFolderConnections do
                Connection:Disconnect()
            end

            table.clear(AICCombat.S.MobFolderConnections)

            for Mob in AICCombat.S.MobConnections do
                AICCombat.DisconnectMob(Mob)
            end

            table.clear(AICCombat.S.ValidMobs)
            AICCombat.S.ClosestTarget = nil
            AICUI.RefreshEnemyPicker()
        end)

        return Module
    end,
}
