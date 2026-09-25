return {
    Name = "Navigation",
    Dependencies = {"Runtime", "CombatUtils", "Targeting"},
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
        function AICCombat.IsSafeCombatPathClear(TargetPosition, Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition then
                return false
            end
        
            local Origin    = RootPart.Position + Vector3.new(0, 1.5, 0)
            local Direction = (TargetPosition - RootPart.Position)
        
            if Direction.Magnitude <= 0.01 then
                return true
            end
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = {
                Character,
                Goblin,   --// เพิ่ม Goblin เข้า exclude ด้วย กันโดนตัวมอนเองที่กำลังจะเดินเข้าหา
            }
        
            --// Ignore every player's character so other players do not block SafeCombat raycasts.
            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                if OtherPlayer.Character and OtherPlayer.Character ~= Character then
                    table.insert(RaycastParams.FilterDescendantsInstances, OtherPlayer.Character)
                end
            end
        
            if AICCombatUtils.S.DebugFolder then
                table.insert(RaycastParams.FilterDescendantsInstances, AICCombatUtils.S.DebugFolder)
            end
        
            local Result = workspace:Raycast(Origin, Direction, RaycastParams)
        
            if Result then
                --print("[SafeCombat] blocked by:", Result.Instance:GetFullName())
                return false
            end
        
            return true
        end
        
        --// Get a safe combat position around the Target.
        --// Cheap checks are performed first. Expensive path/visibility checks are
        --// only run for the best few candidates to reduce physics-query spikes.
        function AICCombat.GetSafeCombatPosition(TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetMob then
                return nil
            end
        
            local TargetRoot = TargetMob:FindFirstChild("HumanoidRootPart")
            if not TargetRoot then
                return nil
            end
        
            local Offset = RootPart.Position - TargetRoot.Position
            local CurrentDirection = Vector3.new(Offset.X, 0, Offset.Z)
        
            if CurrentDirection.Magnitude <= 0.01 then
                CurrentDirection = Vector3.zAxis
            else
                CurrentDirection = CurrentDirection.Unit
            end
        
            local CombatDistance = CONFIG.PLAYER_ATTACK_DISTANCE
            local LastAttacker = TargetMob:FindFirstChild("LastAttacker")
            local LastAttackerValue = LastAttacker and LastAttacker.Value
            local OtherAttacker = LastAttackerValue and LastAttackerValue ~= Player
        
            --// Always approach from behind first, regardless of who the LastAttacker is.
            --// When another player is attacking, also alternate the side used for the
            --// approach so the player does not stay on one predictable side.
            if AICCombat.S.LastAttackerCombatMob ~= TargetMob then
                AICCombat.S.LastAttackerCombatMob = TargetMob
                AICCombat.S.LastAttackerCombatSide = math.random(0, 1) == 0 and -1 or 1
                AICCombat.S.LastAttackerCombatSwitchTime = os.clock() + math.random() * (CONFIG.OTHER_ATTACKER_SIDE_SWITCH_MAX - CONFIG.OTHER_ATTACKER_SIDE_SWITCH_MIN) + CONFIG.OTHER_ATTACKER_SIDE_SWITCH_MIN
                AICCombat.S.LastAttackerCombatPosition = nil
            elseif os.clock() >= AICCombat.S.LastAttackerCombatSwitchTime then
                AICCombat.S.LastAttackerCombatSide *= -1
                AICCombat.S.LastAttackerCombatSwitchTime = os.clock() + math.random() * (CONFIG.OTHER_ATTACKER_SIDE_SWITCH_MAX - CONFIG.OTHER_ATTACKER_SIDE_SWITCH_MIN) + CONFIG.OTHER_ATTACKER_SIDE_SWITCH_MIN
                AICCombat.S.LastAttackerCombatPosition = nil
            end
        
            if OtherAttacker then
                CombatDistance = math.max(CombatDistance, CONFIG.GOBLIN_REACH_DISTANCE)
            end
        
            for _, BladePart in AICCombat.GetCombatBladeParts(TargetMob) do
                local BladeOffset = BladePart.Position - TargetRoot.Position
                local HorizontalBladeOffset = Vector3.new(BladeOffset.X, 0, BladeOffset.Z)
                local BladeDistance = HorizontalBladeOffset.Magnitude
                CombatDistance = math.max(
                    CombatDistance,
                    BladeDistance + AICCombatUtils.GetBladeDangerDistance()
                )
            end
        
            local Candidates = {}
            local DirectionCount = CONFIG.SAFE_COMBAT_DIRECTIONS
            local PreferredDirections = {}
        
            --// Farm Zone can make the normal attack radius unreachable when the mob
            --// is close to the edge of the zone. Try progressively closer combat
            --// positions instead of giving up at PLAYER_ATTACK_DISTANCE.
            local CombatDistances = {
                CombatDistance,
                math.max(CONFIG.GOBLIN_REACH_DISTANCE, CombatDistance - 2),
                math.max(CONFIG.GOBLIN_REACH_DISTANCE, CombatDistance - 4),
                math.max(CONFIG.GOBLIN_REACH_DISTANCE, CombatDistance - 6),
                math.max(CONFIG.GOBLIN_REACH_DISTANCE, CombatDistance - 8),
            }
        
            --// Always prefer the mob's rear. This applies both when LastAttacker is
            --// the local player and when another player is the current attacker.
            local Look = TargetRoot.CFrame.LookVector
            local Right = TargetRoot.CFrame.RightVector
            local Back = Vector3.new(-Look.X, 0, -Look.Z)
            local Side = Vector3.new(Right.X, 0, Right.Z) * AICCombat.S.LastAttackerCombatSide
            if Back.Magnitude > 0.01 then
                Back = Back.Unit
            end
            if Side.Magnitude > 0.01 then
                Side = Side.Unit
            end
            PreferredDirections = {
                Back,
                Side,
                -Side,
            }
        
            for _, Direction in ipairs(PreferredDirections) do
                for _, CandidateDistance in ipairs(CombatDistances) do
                    local CandidatePosition = TargetRoot.Position + Direction * CandidateDistance
                    if AICCombatUtils.IsInsideFarmArea(CandidatePosition)
                        and not AICCombatUtils.IsWaterAtPosition(CandidatePosition, TargetMob)
                        and not AICCombatUtils.IsPathThroughDeadzone(CandidatePosition)
                        and AICCombat.IsPositionSafeFromBladeGroup(CandidatePosition, TargetMob)
                    then
                        local Dot = math.clamp(CurrentDirection:Dot(Direction), -1, 1)
                        local DirectionPenalty = (1 - Dot) * CandidateDistance * 0.2
                        table.insert(Candidates, {
                            Position = CandidatePosition,
                            Score = (CandidatePosition - RootPart.Position).Magnitude + DirectionPenalty - 20,
                        })
                    end
                end
            end
        
            for Index = 0, DirectionCount - 1 do
                local Angle = (math.pi * 2 / DirectionCount) * Index
                local Direction = Vector3.new(math.cos(Angle), 0, math.sin(Angle))
        
                for _, CandidateDistance in ipairs(CombatDistances) do
                    local CandidatePosition = TargetRoot.Position + Direction * CandidateDistance
        
                    --// Cheap checks first. These avoid expensive raycasts for obviously
                    --// invalid positions.
                    if not AICCombatUtils.IsInsideFarmArea(CandidatePosition)
                        or AICCombatUtils.IsWaterAtPosition(CandidatePosition, TargetMob)
                        or AICCombatUtils.IsPathThroughDeadzone(CandidatePosition)
                        or not AICCombat.IsPositionSafeFromBladeGroup(CandidatePosition, TargetMob)
                    then
                        continue
                    end
        
                    local Dot = math.clamp(CurrentDirection:Dot(Direction), -1, 1)
                    local DirectionPenalty = (1 - Dot) * CandidateDistance * 0.35
                    local TravelDistance = (CandidatePosition - RootPart.Position).Magnitude
        
                    table.insert(Candidates, {
                        Position = CandidatePosition,
                        Score = TravelDistance + DirectionPenalty,
                    })
                end
            end
        
            table.sort(Candidates, function(A, B)
                return A.Score < B.Score
            end)
        
            local MaxPathTests = math.min(CONFIG.SAFE_COMBAT_MAX_PATH_TESTS, #Candidates)
        
            --// A spot the mob cannot be seen from is worse, not unusable. Rejecting
            --// it outright meant a pillar or a rock between us was enough to leave
            --// the solver with no answer at all, when walking around it was always
            --// an option. Sight is preferred; blocked sight is kept as a fallback
            --// and the pathfinder routes to it.
            local BlindFallback = nil
        
            for Index = 1, MaxPathTests do
                local CandidatePosition = Candidates[Index].Position
        
                if AICCombatUtils.IsPathThroughWater(CandidatePosition)
                    or AICCombat.IsPathThroughBladeGroupDanger(CandidatePosition, TargetMob)
                then
                    continue
                end
        
                if AICCombatUtils.CanSeeGoblinFromPosition(CandidatePosition, TargetMob)
                    and AICCombat.IsSafeCombatPathClear(CandidatePosition, TargetMob)
                then
                    return CandidatePosition
                end
        
                if not BlindFallback then
                    BlindFallback = CandidatePosition
                end
            end
        
            return BlindFallback
        end
        
        --// Calculate Retreat Position
        function AICCombat.IsRetreatPositionReachable(TargetPosition, RequirePathfinding)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition then
                return false
            end
        
            if not AICCombatUtils.IsInsideFarmArea(TargetPosition)
                or AICCombatUtils.IsWaterAtPosition(TargetPosition)
                or AICCombatUtils.IsPathThroughWater(TargetPosition)
                or AICCombatUtils.IsPathThroughDeadzone(TargetPosition)
            then
                return false
            end
        
            if not AICCombatUtils.IsPathClear(TargetPosition) then
                return false
            end
        
            --// A retreat position is only useful if it is outside every active
            --// enemy blade danger area, and the route does not cross one.
            for _, Goblin in AICCombat.GetLivingGoblins() do
                if AICCombat.IsPositionSafeFromBladeGroup(TargetPosition, Goblin) == false
                    or AICCombat.IsPathThroughBladeGroupDanger(TargetPosition, Goblin)
                then
                    return false
                end
            end
        
            if not RequirePathfinding then
                return true
            end
        
            local Path = PathfindingService:CreatePath({
                AgentRadius    = math.max(RootPart.Size.X * 0.5, 2),
                AgentHeight    = math.max(RootPart.Size.Y, 5),
                AgentCanJump   = true,
                WaypointSpacing = 4,
            })
        
            local Success = pcall(function()
                Path:ComputeAsync(RootPart.Position, TargetPosition)
            end)
        
            if not Success or Path.Status ~= Enum.PathStatus.Success then
                return false
            end
        
            local Waypoints = Path:GetWaypoints()
        
            if #Waypoints < 2 then
                return false
            end
        
            for Index = 2, #Waypoints do
                local Position = Waypoints[Index].Position
        
                if not AICCombatUtils.IsInsideFarmArea(Position)
                    or AICCombatUtils.IsWaterAtPosition(Position)
                    or AICCombatUtils.IsPathThroughDeadzone(Position)
                then
                    return false
                end
            end
        
            return true
        end
        function AICCombat.GetEnemySkillRetreatPosition()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            local Threats = AICCombat.GetLivingGoblins()
        
            if #Threats == 0 then
                return nil
            end
        
            local Origin = RootPart.Position
            local Away = Vector3.zero
        
            --// Weight every nearby enemy by inverse distance.
            --// This makes the retreat direction react to the whole group instead
            --// of blindly running directly away from the current target.
            for _, Goblin in Threats do
                local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
                if MobRoot then
                    local Offset = Origin - MobRoot.Position
                    local Horizontal = Vector3.new(Offset.X, 0, Offset.Z)
                    local Distance = Horizontal.Magnitude
        
                    if Distance > 0.01 then
                        Away += Horizontal.Unit / math.max(Distance, 4)
                    end
                end
            end
        
            if Away.Magnitude <= 0.01 then
                return nil
            end
        
            Away = Away.Unit
        
            local Directions = {}
        
            --// Test the direct escape first, then progressively wider angles.
            --// The longer candidates are preferred so the player gets out of
            --// the skill range quickly instead of stopping after a tiny step.
            for Index = 0, CONFIG.RETREAT_DIRECTIONS - 1 do
                local Angle = (math.pi * 2 / CONFIG.RETREAT_DIRECTIONS) * Index
                local Direction = CFrame.fromAxisAngle(Vector3.yAxis, Angle):VectorToWorldSpace(Away)
        
                table.insert(Directions, Direction)
            end
        
            local BestPosition = nil
            local BestScore = -math.huge
        
            for _, Direction in ipairs(Directions) do
                Direction = Vector3.new(Direction.X, 0, Direction.Z)
        
                if Direction.Magnitude <= 0.01 then
                    continue
                end
        
                Direction = Direction.Unit
        
                for _, Distance in ipairs({
                    CONFIG.SKILL_RETREAT_DISTANCE,
                    48,
                    36,
                    28,
                    20,
                    }) do
                    local Candidate = Origin + Direction * Distance
        
                    if not AICCombat.IsRetreatPositionReachable(Candidate, true) then
                        continue
                    end
        
                    local DirectionScore = Away:Dot(Direction)
                    local DistanceScore = Distance / CONFIG.SKILL_RETREAT_DISTANCE
        
                    --// Strongly prefer getting farther away, but only after the
                    --// candidate has passed the actual reachability/safety checks.
                    local Score = DirectionScore * 5 + DistanceScore * 3
        
                    if Score > BestScore then
                        BestScore = Score
                        BestPosition = Candidate
                    end
        
                    --// Once a safe long route exists in this direction, don't
                    --// waste pathfinding calls on the shorter candidates.
                    break
                end
            end
        
            --// Emergency local fallback: if every long retreat candidate is
            --// rejected, still try a short escape around the player. This does
            --// not use PathfindingService, but it still respects FarmZone,
            --// Deadzone, water and blade-safety checks.
            if not BestPosition then
                for _, Distance in ipairs({12, 8, 5}) do
                    local Candidate = Origin + Away * Distance
                    if AICCombat.IsRetreatPositionReachable(Candidate, false) then
                        BestPosition = Candidate
                        break
                    end
                end
            end
        
            return BestPosition
        end
        function AICCombat.GetRetreatPosition()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            local Goblins = AICCombat.GetLivingGoblins()
        
            if #Goblins == 0 then
                return nil
            end
        
            local RetreatDirection = Vector3.zero
        
            if AICCombat.S.ClosestTarget
                and AICCombat.S.ClosestTarget:IsDescendantOf(workspace)
            then
                local TargetHumanoid = AICCombat.S.ClosestTarget:FindFirstChildOfClass("Humanoid")
                local TargetRoot     = AICCombat.S.ClosestTarget:FindFirstChild("HumanoidRootPart")
        
                if TargetHumanoid
                    and TargetRoot
                    and TargetHumanoid.Health > 0
                then
                    local Offset = RootPart.Position - TargetRoot.Position
                    local Distance = Offset.Magnitude
        
                    if Distance > 0 then
                        RetreatDirection = Offset.Unit
                    end
                end
            end
        
            if RetreatDirection.Magnitude <= 0 then
                for _, Goblin in Goblins do
                    local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
                    if MobRoot then
                        local Offset = RootPart.Position - MobRoot.Position
                        local Distance = Offset.Magnitude
        
                        if Distance > 0 then
                            RetreatDirection += Offset.Unit / math.max(Distance, 1)
                        end
                    end
                end
        
                if RetreatDirection.Magnitude <= 0 then
                    return nil
                end
        
                RetreatDirection = RetreatDirection.Unit
            end
        
            local BestPosition = nil
            local BestScore    = -math.huge
        
            --// Only the full retreat distance used to be tried. Near a zone edge, or
            --// with any wall inside sixty studs, every direction failed and the
            --// caller was left standing in the damage. Shorter hops are worth far
            --// more than no movement at all.
            local Distances = {
                CONFIG.RETREAT_DISTANCE,
                45,
                32,
                22,
                14,
            }
        
            for _, Distance in ipairs(Distances) do
                for Index = 0, CONFIG.RETREAT_DIRECTIONS - 1 do
                    local Angle = (math.pi * 2 / CONFIG.RETREAT_DIRECTIONS) * Index
        
                    local Direction = Vector3.new(
                        math.cos(Angle),
                        0,
                        math.sin(Angle)
                    )
        
                    local TargetPosition = RootPart.Position + Direction * Distance
        
                    if AICCombatUtils.IsInsideFarmArea(TargetPosition)
                        and AICCombatUtils.IsPathClear(TargetPosition)
                    then
                        local Score = Direction:Dot(RetreatDirection)
        
                        if Score > BestScore then
                            BestScore    = Score
                            BestPosition = TargetPosition
                        end
                    end
                end
        
                --// Prefer the longest distance that produced anything.
                if BestPosition then
                    return BestPosition
                end
            end
        
            return BestPosition
        end
        
        --// Direction away from the nearest threat, with no validation at all. Used
        --// as the last resort when every vetted escape has failed: walking into a
        --// wall still beats standing still while a mob swings.
        function AICCombat.GetRawAwayDirection()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            local Origin = RootPart.Position
            local Nearest = nil
            local NearestDistance = math.huge
        
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder then
                return nil
            end
        
            for _, Mob in MobFolder:GetChildren() do
                if Mob:IsA("Model") then
                    local MobRoot = Mob:FindFirstChild("HumanoidRootPart")
                    local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
        
                    if MobRoot and MobHumanoid and MobHumanoid.Health > 0 then
                        local Distance = AICCombatUtils.GetHorizontalDistance(Origin, MobRoot.Position)
        
                        if Distance < NearestDistance then
                            NearestDistance = Distance
                            Nearest = MobRoot
                        end
                    end
                end
            end
        
            if not Nearest then
                return nil
            end
        
            local Offset = Origin - Nearest.Position
            local Flat = Vector3.new(Offset.X, 0, Offset.Z)
        
            if Flat.Magnitude <= 0.01 then
                return nil
            end
        
            return Flat.Unit
        end
        
        --// Check whether any living priority mob is close enough to justify retreat movement.
        --// Distance to the nearest living mob of any kind. The priority list decides
        --// what to attack, not what can hurt us: a mob outside it swings just as hard,
        --// and keying "am I safe to stand still" off the priority list meant the
        --// script would hold position while something not on the list beat on it.
        function AICCombat.GetNearestHostileDistance()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return math.huge
            end
        
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder then
                return math.huge
            end
        
            local Nearest = math.huge
        
            for _, Mob in MobFolder:GetChildren() do
                if Mob:IsA("Model") then
                    local MobRoot = Mob:FindFirstChild("HumanoidRootPart")
                    local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
        
                    if MobRoot and MobHumanoid and MobHumanoid.Health > 0 then
                        local Distance = AICCombatUtils.GetHorizontalDistance(RootPart.Position, MobRoot.Position)
        
                        if Distance < Nearest then
                            Nearest = Distance
                        end
                    end
                end
            end
        
            return Nearest
        end
        function AICCombat.GetNearestLivingGoblinDistance()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return math.huge
            end
        
            local NearestDistance = math.huge
        
            for _, Goblin in AICCombat.GetLivingGoblins() do
                local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
                if MobRoot then
                    local Distance = AICCombatUtils.GetHorizontalDistance(RootPart.Position, MobRoot.Position)
        
                    if Distance < NearestDistance then
                        NearestDistance = Distance
                    end
                end
            end
        
            return NearestDistance
        end
        
        --// Retreat
        --// Dodging a skill is a race, and the pathfinding solver is not fast enough
        --// to win it: sixteen directions by five distances is up to eighty
        --// ComputeAsync calls plus hundreds of samples, which stalls frames badly
        --// enough that the character appears to crawl.
        --//
        --// This picks a direction away from the whole group and validates it with
        --// nothing but a farm-zone test, a ground ray and one body-width blockcast.
        --// It is allowed to be imperfect; moving now beats moving well later.
        function AICCombat.GetImmediateEscapePosition()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            local Origin = RootPart.Position
            local Away = Vector3.zero
        
            for _, Goblin in AICCombat.GetLivingGoblins() do
                local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
                if MobRoot then
                    local Offset = Origin - MobRoot.Position
                    local Flat = Vector3.new(Offset.X, 0, Offset.Z)
                    local Distance = Flat.Magnitude
        
                    if Distance > 0.01 then
                        --// Inverse distance: the mob about to hit us dominates.
                        Away += Flat.Unit / math.max(Distance, 4)
                    end
                end
            end
        
            if Away.Magnitude <= 0.01 then
                Away = -Vector3.new(
                    RootPart.CFrame.LookVector.X,
                    0,
                    RootPart.CFrame.LookVector.Z
                )
        
                if Away.Magnitude <= 0.01 then
                    return nil
                end
            end
        
            Away = Away.Unit
        
            local DirectionCount = math.max(1, tonumber(CONFIG.SKILL_DODGE_DIRECTIONS) or 9)
            local Spread = tonumber(CONFIG.SKILL_DODGE_SPREAD) or 110
            local Distances = {
                tonumber(CONFIG.SKILL_DODGE_DISTANCE) or 26,
                tonumber(CONFIG.SKILL_DODGE_FALLBACK_DISTANCE) or 14,
            }
        
            for _, Distance in ipairs(Distances) do
                for Index = 0, DirectionCount - 1 do
                    --// Straight away first, then alternating outward to either side.
                    local Step = math.ceil(Index / 2)
                    local Sign = (Index % 2 == 0) and 1 or -1
                    local Angle = math.rad((Spread / math.max(1, DirectionCount - 1)) * Step * Sign)
                    local Direction = CFrame.fromAxisAngle(Vector3.yAxis, Angle):VectorToWorldSpace(Away)
        
                    Direction = Vector3.new(Direction.X, 0, Direction.Z)
        
                    if Direction.Magnitude > 0.01 then
                        Direction = Direction.Unit
        
                        local Candidate = AICCombatUtils.GetPatrolGroundPosition(Origin + Direction * Distance)
        
                        if Candidate
                            and AICCombatUtils.IsInsideFarmArea(Candidate)
                            and not AICCombatUtils.IsInsideFarmDeadzone(Candidate)
                            and AICCombatUtils.IsEscapePathClear(Candidate)
                        then
                            return Candidate
                        end
                    end
                end
            end
        
            return nil
        end
        function AICCombat.RetreatFromGoblins(IsEnemySkill)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
        local FaceOrientation = Runtime:GetFaceOrientation()
            local RetreatPosition = nil
            local now = os.clock()
        
            --// Normal retreat only triggers movement/jump when a mob is within
            --// the configured nearby distance. Enemy skill retreat is different:
            --// if a mob is actively using a skill, keep the skill-escape logic
            --// even when that mob is farther than the normal 30-stud trigger.
            if not IsEnemySkill then
                --// Any living mob counts here, not just the ones we would attack.
                local NearestMobDistance = AICCombat.GetNearestHostileDistance()
                if NearestMobDistance > CONFIG.RETREAT_NEARBY_MOB_DISTANCE then
                    Humanoid.AutoRotate = false
                    Humanoid:Move(Vector3.zero)
                    return false
                end
            end
        
            if IsEnemySkill then
                --// Keep running toward the position already chosen while it is still
                --// worth reaching, so the character commits to one escape instead of
                --// re-deciding every frame and shuffling on the spot.
                if AICCombat.S.SkillRetreatPosition
                    and now - AICCombat.S.LastSkillRetreatTime < CONFIG.RETREAT_RECALCULATE_INTERVAL
                    and AICCombatUtils.GetHorizontalDistance(RootPart.Position, AICCombat.S.SkillRetreatPosition) > 3
                    and AICCombatUtils.IsInsideFarmArea(AICCombat.S.SkillRetreatPosition)
                    and not AICCombatUtils.IsInsideFarmDeadzone(AICCombat.S.SkillRetreatPosition)
                then
                    RetreatPosition = AICCombat.S.SkillRetreatPosition
                else
                    --// Cheap solver first. It answers in a handful of raycasts.
                    RetreatPosition = AICCombat.GetImmediateEscapePosition()
        
                    --// Only when there is no room at all does the expensive
                    --// pathfinding solver run, and then no more than once every
                    --// SKILL_SOLVER_INTERVAL so it cannot stall frame after frame.
                    if not RetreatPosition
                        and now - AICCombat.S.LastSkillSolverTime >= (tonumber(CONFIG.SKILL_SOLVER_INTERVAL) or 0.6)
                    then
                        AICCombat.S.LastSkillSolverTime = now
                        RetreatPosition = AICCombat.GetEnemySkillRetreatPosition()
                    end
        
                    if RetreatPosition then
                        AICCombat.S.SkillRetreatPosition = RetreatPosition
                        AICCombat.S.LastSkillRetreatTime = now
                    else
                        AICCombat.S.SkillRetreatPosition = nil
                    end
                end
            else
                if AICCombat.S.LastRetreatPosition
                    and now - AICCombat.S.LastRetreatCalculateTime < CONFIG.RETREAT_RECALCULATE_INTERVAL
                then
                    RetreatPosition = AICCombat.S.LastRetreatPosition
                else
                    RetreatPosition = AICCombat.GetRetreatPosition()
        
                    --// Same cheap solver the skill dodge uses. It accepts ground the
                    --// vetted search rejects, which is the difference between moving
                    --// and standing still.
                    if not RetreatPosition then
                        RetreatPosition = AICCombat.GetImmediateEscapePosition()
                    end
        
                    if RetreatPosition then
                        AICCombat.S.LastRetreatPosition      = RetreatPosition
                        AICCombat.S.LastRetreatCalculateTime = now
                        AICCombat.S.RetreatNoPositionSince   = nil
                    elseif not AICCombat.S.RetreatNoPositionSince then
                        AICCombat.S.RetreatNoPositionSince = now
                    end
                end
            end
        
            if RetreatPosition then
                AICCombat.S.RetreatNoPositionSince = nil
        
                --// Face the actual retreat direction instead of the target.
                Humanoid.AutoRotate = false
                Humanoid:MoveTo(RetreatPosition)
        
                local RootPosition = RootPart.Position
                local RetreatDirection = Vector3.new(
                    RetreatPosition.X - RootPosition.X,
                    0,
                    RetreatPosition.Z - RootPosition.Z
                )
        
                if RetreatDirection.Magnitude > 0.01 then
                    FaceOrientation.CFrame = CFrame.lookAt(
                        RootPosition,
                        RootPosition + RetreatDirection.Unit
                    )
                    FaceOrientation.Enabled = true
                end
        
                AICCombatUtils.DoJumpIfObstacle(RetreatPosition)
                return true
            end
        
            --// Nothing passed any check. Standing still here is the worst possible
            --// answer and is exactly what the script used to do: it would hold
            --// position, still flagged as retreating, and take hits until it died.
            if not AICCombat.S.RetreatNoPositionSince then
                AICCombat.S.RetreatNoPositionSince = now
            end
        
            if now - AICCombat.S.RetreatNoPositionSince < (tonumber(CONFIG.RETREAT_NO_POSITION_TIMEOUT) or 1.5) then
                local Away = AICCombat.GetRawAwayDirection()
        
                if Away then
                    Humanoid.AutoRotate = false
                    local RawTarget = RootPart.Position + Away * CONFIG.SKILL_DODGE_FALLBACK_DISTANCE
                    Humanoid:MoveTo(RawTarget)
                    AICCombatUtils.DoJumpIfObstacle(RawTarget)
                    return true
                end
            else
                --// Boxed in for long enough that retreating is clearly not working.
                --// Fighting back beats being a stationary target, so hand control
                --// back to the combat loop.
                AICCombat.S.RETREATING = false
                AICCombat.S.RetreatNoPositionSince = nil
                AICCombat.S.SkillRetreatPosition = nil
                AICCombat.S.LastRetreatPosition = nil
            end
        
            Humanoid.AutoRotate = false
            Humanoid:Move(Vector3.zero)
            return false
        end
        
        --// Approach Position Check
        function AICCombat.IsApproachPositionClear(TargetPosition, Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition then
                return false
            end
        
            if not AICCombatUtils.IsInsideFarmArea(TargetPosition) then
                return false
            end
        
            if AICCombatUtils.IsWaterAtPosition(TargetPosition, Goblin) then
                return false
            end
        
            if AICCombatUtils.IsPathThroughWater(TargetPosition) then
                return false
            end
        
            if AICCombatUtils.IsPathThroughDeadzone(TargetPosition) then
                return false
            end
        
            --// Never select a position inside any BladePart danger zone
            --// around the target group.
            if AICCombat.S.SafeCombatPositionEnabled
                and Goblin
                and not AICCombat.IsPositionSafeFromBladeGroup(TargetPosition, Goblin)
            then
                return false
            end
        
            --// Also make sure the route itself doesn't pass through
            --// an enemy BladePart danger zone.
            if AICCombat.S.SafeCombatPositionEnabled
                and Goblin
                and AICCombat.IsPathThroughBladeGroupDanger(TargetPosition, Goblin)
            then
                return false
            end
        
            local Origin    = RootPart.Position
            local Direction = TargetPosition - Origin
        
            if Direction.Magnitude <= 0 then
                return true
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
        
            local Result = workspace:Raycast(Origin, Direction, RaycastParams)
        
            return Result == nil
        end
        
        --// Target Reposition
        function AICCombat.GetTargetRepositionPosition(Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Goblin then
                return nil
            end
        
            local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
            if not MobRoot then
                return nil
            end
        
            --// Calculate the minimum safe radius around the target.
            local SafeRadius = CONFIG.PLAYER_ATTACK_DISTANCE
        
            if AICCombat.S.SafeCombatPositionEnabled then
                for _, BladePart in AICCombat.GetCombatBladeParts(Goblin) do
                    local Offset = BladePart.Position - MobRoot.Position
                    local HorizontalOffset = Vector3.new(Offset.X, 0, Offset.Z)
                    local BladeDistance = HorizontalOffset.Magnitude
        
                    SafeRadius = math.max(
                        SafeRadius,
                        BladeDistance + AICCombatUtils.GetBladeDangerDistance()
                    )
                end
            end
        
            --// Never make the radius absurdly small.
            SafeRadius = math.max(SafeRadius, CONFIG.GOBLIN_REACH_DISTANCE)
        
            local BestPosition = nil
            local BestScore    = math.huge
        
            for Index = 0, CONFIG.TARGET_REPOSITION_DIRECTIONS - 1 do
                local Angle = (math.pi * 2 / CONFIG.TARGET_REPOSITION_DIRECTIONS) * Index
        
                local Direction = Vector3.new(
                    math.cos(Angle),
                    0,
                    math.sin(Angle)
                )
        
                local CandidatePosition = MobRoot.Position + Direction * SafeRadius
        
                if not AICCombat.IsApproachPositionClear(CandidatePosition, Goblin) then
                    continue
                end
        
                if AICCombat.S.SafeCombatPositionEnabled
                    and not AICCombat.IsPositionSafeFromBladeGroup(CandidatePosition, Goblin)
                then
                    continue
                end
        
                local Offset = CandidatePosition - RootPart.Position
                local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
                --// Prefer positions closer to the current player
                --// while still maintaining safety.
                local TargetOffset = CandidatePosition - MobRoot.Position
                local TargetDistance = Vector3.new(TargetOffset.X, 0, TargetOffset.Z).Magnitude
        
                local Score = Distance + TargetDistance * 0.15
        
                --// Penalise rather than discard a spot with no view of the mob, so a
                --// wall in the way costs a detour instead of the whole candidate set.
                if not AICCombatUtils.CanSeeGoblinFromPosition(CandidatePosition, Goblin) then
                    Score += CONFIG.BLIND_POSITION_PENALTY
                end
        
                if Score < BestScore then
                    BestScore    = Score
                    BestPosition = CandidatePosition
                end
            end
        
            return BestPosition
        end
        function AICCombat.IsSafeCombatDirectPathBlocked(Goblin, TargetPosition, now)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Goblin or not TargetPosition then
                return true
            end
        
            if AICCombat.S.LastDirectPathTarget == Goblin
                and AICCombat.S.LastDirectPathPosition == TargetPosition
                and now - AICCombat.S.LastDirectPathCheckTime < CONFIG.DIRECT_PATH_CACHE_INTERVAL
            then
                return AICCombat.S.LastDirectPathBlocked
            end
        
            AICCombat.S.LastDirectPathCheckTime = now
            AICCombat.S.LastDirectPathTarget = Goblin
            AICCombat.S.LastDirectPathPosition = TargetPosition
        
            AICCombat.S.LastDirectPathBlocked =
                not AICCombatUtils.CanSeeGoblin(Goblin)
                or not AICCombat.IsSafeCombatPathClear(TargetPosition, Goblin)
                or AICCombatUtils.IsPathThroughWater(TargetPosition)
                or AICCombatUtils.IsPathThroughDeadzone(TargetPosition)
                or AICCombat.IsPathThroughBladeGroupDanger(TargetPosition, Goblin)
        
            return AICCombat.S.LastDirectPathBlocked
        end
        
        --// ============================================================
        --// TARGET PATHFINDING
        --// ============================================================
        function AICCombat.ResetTargetPath()
            AICCombat.S.TargetPath             = nil
            AICCombat.S.TargetPathMob          = nil
            AICCombat.S.TargetPathDestination  = nil
            AICCombat.S.TargetPathWaypoint     = 1
            AICCombat.S.LastTargetPathTime     = 0
            AICCombat.S.TargetPathBlockedSince = nil
        end
        function AICCombat.ComputeTargetPath(Goblin, Destination)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Goblin or not Destination then
                AICCombat.ResetTargetPath()
                return false
            end
        
            local Path = PathfindingService:CreatePath({
                AgentRadius = math.max(RootPart.Size.X * 0.5, 2),
                AgentHeight = math.max(RootPart.Size.Y, 5),
                AgentCanJump = true,
                WaypointSpacing = 4,
            })
        
            local Success = pcall(function()
                Path:ComputeAsync(RootPart.Position, Destination)
            end)
        
            if not Success or Path.Status ~= Enum.PathStatus.Success then
                AICCombat.ResetTargetPath()
                return false
            end
        
            local Waypoints = Path:GetWaypoints()
        
            if #Waypoints < 2 then
                AICCombat.ResetTargetPath()
                return false
            end
        
            --// Never follow a path that leaves the FarmZone, and never one that cuts
            --// through a deadzone. IsInsideFarmArea covers both, but it short
            --// circuits to true when Ignore Farm Zone is on, so the deadzone test is
            --// spelled out for the case where only the zone restriction is waived.
            for Index = 2, #Waypoints do
                local Position = Waypoints[Index].Position
        
                if not AICCombatUtils.IsInsideFarmArea(Position) then
                    AICCombat.ResetTargetPath()
                    return false
                end
        
                if not FeatureState.IgnoreFarmZone.Enabled
                    and AICCombatUtils.IsInsideFarmDeadzone(Position)
                then
                    AICCombat.ResetTargetPath()
                    return false
                end
            end
        
            AICCombat.S.TargetPath             = Path
            AICCombat.S.TargetPathMob          = Goblin
            AICCombat.S.TargetPathDestination  = Destination
            AICCombat.S.TargetPathWaypoint     = 2
            AICCombat.S.LastTargetPathTime     = os.clock()
            AICCombat.S.TargetPathBlockedSince = nil
        
            return true
        end
        function AICCombat.MoveAlongTargetPath(Goblin, Destination)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Goblin or not Destination then
                return false
            end
        
            local now = os.clock()
            local NeedRecalculate =
                AICCombat.S.TargetPath == nil
                or AICCombat.S.TargetPathMob ~= Goblin
                or not AICCombat.S.TargetPathDestination
                or (AICCombat.S.TargetPathDestination - Destination).Magnitude > 5
                or now - AICCombat.S.LastTargetPathTime >= CONFIG.TARGET_PATH_RECALCULATE_INTERVAL
        
            if NeedRecalculate then
                if not AICCombat.ComputeTargetPath(Goblin, Destination) then
                    if not AICCombat.S.TargetPathBlockedSince then
                        AICCombat.S.TargetPathBlockedSince = now
                    end
        
                    return false
                end
            end
        
            local Waypoints = AICCombat.S.TargetPath:GetWaypoints()
        
            while AICCombat.S.TargetPathWaypoint <= #Waypoints do
                local Waypoint = Waypoints[AICCombat.S.TargetPathWaypoint]
                local Offset = Waypoint.Position - RootPart.Position
                local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
                if Distance <= CONFIG.TARGET_PATH_WAYPOINT_DISTANCE then
                    AICCombat.S.TargetPathWaypoint += 1
                    continue
                end
        
                --// The pathfinder marks jumps generously, including on flat ground.
                --// Only take them when something is actually in the way, or when the
                --// character has stopped making progress.
                if Waypoint.Action == Enum.PathWaypointAction.Jump
                    and (AICCombatUtils.IsJumpableObstacleAhead(Waypoint.Position) or AICCombatUtils.IsStuck())
                then
                    AICCombatUtils.DoJump()
                end
        
                Humanoid.AutoRotate = false
                Humanoid:MoveTo(Waypoint.Position)
                AICCombat.FaceGoblin(Goblin)
                return true
            end
        
            --// Path reached its final waypoint. Let combat positioning decide
            --// whether we should attack or make a final adjustment.
            AICCombat.ResetTargetPath()
            return false
        end
        
        --// ============================================================
        --// SAFE ENEMY RANGE
        --// ============================================================
        function AICCombat.GetSafeEnemyRangePosition(Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Goblin then
                return nil
            end
        
            local SafeRange = math.max(tonumber(CONFIG.SAFE_ENEMY_RANGE) or 0, 0)
            if SafeRange <= 0 then
                return nil
            end
        
            local TargetRoot = Goblin:FindFirstChild("HumanoidRootPart")
            if not TargetRoot then
                return nil
            end
        
            local BladeParts = AICCombat.GetCombatBladeParts(Goblin)
            if #BladeParts == 0 then
                return nil
            end
        
            local LastAttacker = Goblin:FindFirstChild("LastAttacker")
            local IsPlayerAttacker = LastAttacker and LastAttacker.Value == Player
        
            local ClosestBlade = nil
            local ClosestPoint = nil
            local ClosestDistance = math.huge
        
            for _, BladePart in ipairs(BladeParts) do
                local Point, Distance = AICCombatUtils.GetClosestPointOnBlade(BladePart, RootPart.Position)
                if Point and Distance < ClosestDistance then
                    ClosestBlade = BladePart
                    ClosestPoint = Point
                    ClosestDistance = Distance
                end
            end
        
            if not ClosestBlade or not ClosestPoint then
                return nil
            end
        
            local CurrentPosition = RootPart.Position
        
            --// When the local player is the LastAttacker, prefer the mob's rear
            --// first, then the two sides. No visibility/path/water checks are used.
            local Look = TargetRoot.CFrame.LookVector
            local Right = TargetRoot.CFrame.RightVector
            local Back = Vector3.new(-Look.X, 0, -Look.Z)
            local Side = Vector3.new(Right.X, 0, Right.Z)
        
            if Back.Magnitude > 0.01 then
                Back = Back.Unit
            else
                Back = Vector3.zAxis
            end
        
            if Side.Magnitude > 0.01 then
                Side = Side.Unit
            else
                Side = Vector3.xAxis
            end
        
            local AwayFromBlade = CurrentPosition - ClosestPoint
            local FlatAwayFromBlade = Vector3.new(AwayFromBlade.X, 0, AwayFromBlade.Z)
            if FlatAwayFromBlade.Magnitude > 0.01 then
                FlatAwayFromBlade = FlatAwayFromBlade.Unit
            else
                FlatAwayFromBlade = Back
            end
        
            local Directions
            if IsPlayerAttacker then
                Directions = {
                    Back,
                    Side,
                    -Side,
                    FlatAwayFromBlade,
                }
            else
                Directions = {
                    FlatAwayFromBlade,
                    Back,
                    Side,
                    -Side,
                }
            end
        
            for _, Direction in ipairs(Directions) do
                local Candidate = ClosestPoint + Direction * SafeRange
        
                --// The only environment checks for Safe Enemy Range:
                --// stay inside FarmZone and never enter a Deadzone.
                if AICCombatUtils.IsInsideFarmArea(Candidate) and not AICCombatUtils.IsInsideFarmDeadzone(Candidate) then
                    local SafeFromAllBlades = true
                    for _, BladePart in ipairs(BladeParts) do
                        local _, Distance = AICCombatUtils.GetClosestPointOnBlade(BladePart, Candidate)
                        if Distance < SafeRange then
                            SafeFromAllBlades = false
                            break
                        end
                    end
        
                    if SafeFromAllBlades then
                        return Candidate
                    end
                end
            end
        
            return nil
        end
        
        --// ============================================================
        --// MOVE TO GOBLIN
        --// ============================================================
        function AICCombat.MoveToGoblin(Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
        local FaceOrientation = Runtime:GetFaceOrientation()
            local now = os.clock()
            if not Goblin or not RootPart then
                return
            end
        
            if not AICCombat.IsTargetLockValid(Goblin) then
                if AICCombat.S.ClosestTarget == Goblin then
                    AICCombat.S.ClosestTarget = nil
                end
        
                AICCombat.ResetTargetReposition()
                AICCombat.ResetTargetPath()
                return
            end
        
            local MobHumanoid = Goblin:FindFirstChildOfClass("Humanoid")
            local MobRoot     = Goblin:FindFirstChild("HumanoidRootPart")
        
            --// Secondary threat handling:
            --// Keep the current target locked, but make room if another mob
            --// closes in from the player's side or rear.
            local ThreatMob, ThreatDistance = AICCombat.GetNearbyThreatMob(Goblin)
            if ThreatMob and ThreatDistance <= CONFIG.ENEMY_ATTACK_SAFE_DISTANCE + CONFIG.THREAT_ESCAPE_DISTANCE then
                local ThreatEscapePosition = AICCombat.GetThreatEscapePosition(Goblin, ThreatMob)
        
                if ThreatEscapePosition then
                    Humanoid.AutoRotate = false
                    Humanoid:MoveTo(ThreatEscapePosition)
                    AICCombat.FaceGoblin(Goblin)
                    return
                end
            end
        
            if not MobHumanoid
                or not MobRoot
                or MobHumanoid.Health <= 0
            then
                if AICCombat.S.ClosestTarget == Goblin then
                    AICCombat.S.ClosestTarget = nil
                end
        
                AICCombat.S.ValidMobs[Goblin] = nil
                AICCombat.ResetTargetReposition()
                AICCombat.ResetTargetPath()
        
                return
            end
        
            --// Safe Enemy Range has its own lightweight rule set.
            --// It only cares about BladePart distance, FarmZone, and Deadzone.
            --// It does not use CanSeeGoblin, water checks, path checks, or SafeCombat.
            local SafeEnemyRangePosition = AICCombat.GetSafeEnemyRangePosition(Goblin)
            if SafeEnemyRangePosition then
                local SafeEnemyOffset = SafeEnemyRangePosition - RootPart.Position
                local SafeEnemyDistance = Vector3.new(SafeEnemyOffset.X, 0, SafeEnemyOffset.Z).Magnitude
        
                if SafeEnemyDistance > CONFIG.SAFE_ENEMY_RANGE_ARRIVAL then
                    AICCombat.ResetTargetPath()
                    Humanoid.AutoRotate = false
                    Humanoid:MoveTo(SafeEnemyRangePosition)
                    AICCombat.FaceGoblin(Goblin)
                    return
                end
            end
        
            --// Safe Combat Position disabled:
            --// simply move directly toward the target.
            if not AICCombat.S.SafeCombatPositionEnabled then
                AICCombat.ResetTargetReposition()
                AICCombat.ResetTargetPath()
                Humanoid.AutoRotate = false
                Humanoid:MoveTo(MobRoot.Position)
                AICCombat.FaceGoblin(Goblin)
                return
            end
        
            if AICCombat.S.TargetApproachMob ~= Goblin then
                AICCombat.ResetTargetReposition()
                AICCombat.S.TargetApproachMob = Goblin
                AICCombat.S.CACHED_SAFECOMBAT_POSITION = nil
                AICCombat.S.CACHED_SAFECOMBAT_TARGET = Goblin
                AICCombat.S.LAST_SAFECOMBAT_TIME = 0
            end
        
            --// ========================================================
            --// FIRST PRIORITY:
            --// Get away from ANY BladePart that is currently too close.
            --// ========================================================
        
            local PushDirection, ClosestEffectiveDistance, ClosestBlade = AICCombat.GetBladeDangerData(Goblin)
        
            if ClosestEffectiveDistance <= 0 then
                if PushDirection.Magnitude > 0 then
                    local RetreatDistance = math.abs(ClosestEffectiveDistance) + CONFIG.ENEMY_ATTACK_SAFE_DISTANCE + 2
                    local RetreatPosition = RootPart.Position + PushDirection * RetreatDistance
        
                    if AICCombatUtils.IsInsideFarmArea(RetreatPosition)
                        and not AICCombatUtils.IsWaterAtPosition(RetreatPosition, Goblin)
                        and not AICCombatUtils.IsPathThroughWater(RetreatPosition)
                        and not AICCombatUtils.IsPathThroughDeadzone(RetreatPosition)
                        and not AICCombat.IsPathThroughBladeGroupDanger(RetreatPosition, Goblin)
                        and AICCombatUtils.IsEscapePathClear(RetreatPosition)
                    then
                        Humanoid.AutoRotate = false
                        Humanoid:MoveTo(RetreatPosition)
                        AICCombat.FaceGoblin(Goblin)
                    else
                        local MoveDistance  = math.abs(ClosestEffectiveDistance) + CONFIG.ENEMY_ATTACK_SAFE_DISTANCE + 2
                        local MovePosition  = RootPart.Position + PushDirection * MoveDistance
        
                        if AICCombatUtils.IsInsideFarmArea(MovePosition)
                            and not AICCombatUtils.IsWaterAtPosition(MovePosition, Goblin)
                            and not AICCombatUtils.IsPathThroughWater(MovePosition)
                            and not AICCombatUtils.IsPathThroughDeadzone(MovePosition)
                        then
                            Humanoid.AutoRotate = false
                            Humanoid:MoveTo(MovePosition)
                            AICCombat.FaceGoblin(Goblin)
                        else
                            Humanoid.AutoRotate = true
                            Humanoid:Move(Vector3.zero)
                            AICCombat.FaceGoblin(Goblin)
                        end
                    end
                else
                    --FaceOrientation.Enabled = false
                    Humanoid.AutoRotate = true
                    Humanoid:Move(Vector3.zero)
                end
        
                return
            end
        
            --// ========================================================
            --// SECOND PRIORITY:
            --// Move to a safe attack position.
            --// ========================================================
        
            local SafeCombatPosition = AICCombat.S.CACHED_SAFECOMBAT_POSITION
            if AICCombat.S.CACHED_SAFECOMBAT_TARGET ~= Goblin
                or now - AICCombat.S.LAST_SAFECOMBAT_TIME >= CONFIG.SAFECOMBAT_INTERVAL
                or (SafeCombatPosition and not AICCombatUtils.IsInsideFarmArea(SafeCombatPosition))
            then
                AICCombat.S.LAST_SAFECOMBAT_TIME = now
                AICCombat.S.CACHED_SAFECOMBAT_TARGET = Goblin
                SafeCombatPosition = AICCombat.GetSafeCombatPosition(Goblin)
                AICCombat.S.CACHED_SAFECOMBAT_POSITION = SafeCombatPosition
            end
        
            if SafeCombatPosition then
                local Offset = SafeCombatPosition - RootPart.Position
                local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
                --// Already at the desired safe position.
                if Distance <= CONFIG.COMBAT_POSITION_ARRIVAL then
                    --// Stop movement but keep the character locked onto the target.
                    Humanoid.AutoRotate = false
                    Humanoid:Move(Vector3.zero)
                    AICCombat.FaceGoblin(Goblin)
        
                    AICCombat.S.TargetUnreachableSince = nil
                    AICCombat.S.TargetApproachPosition = nil
        
                    return
                end
        
                local DirectPathBlocked = AICCombat.IsSafeCombatDirectPathBlocked(Goblin, SafeCombatPosition, now)
        
                if not DirectPathBlocked then
                    AICCombat.ResetTargetPath()
                    AICCombat.S.TargetUnreachableSince = nil
                    AICCombat.S.TargetApproachPosition = nil
        
                    Humanoid.AutoRotate = false
                    Humanoid:MoveTo(SafeCombatPosition)
                    AICCombat.FaceGoblin(Goblin)
                    return
                end
            end
        
            --// ========================================================
            --// THIRD PRIORITY:
            --// Use real pathfinding when an object blocks the direct route.
            --// A blocked line of sight does NOT mean the target is unreachable.
            --// ========================================================
        
            local PathDestination = SafeCombatPosition or MobRoot.Position
        
            local OtherPlayerDetour = AICCombat.GetOtherPlayerDetourPosition(PathDestination, Goblin)
            if OtherPlayerDetour then
                AICCombat.ResetTargetPath()
                Humanoid.AutoRotate = false
                Humanoid:MoveTo(OtherPlayerDetour)
                AICCombat.FaceGoblin(Goblin)
                return
            end
        
            if AICCombat.MoveAlongTargetPath(Goblin, PathDestination) then
                AICCombat.S.TargetUnreachableSince = nil
                AICCombat.S.TargetApproachPosition = nil
                return
            end
        
            --// The chosen combat spot may be unreachable while the mob itself is
            --// perfectly walkable, so try routing to the mob before treating the
            --// target as out of reach. An obstacle between us is a detour, not a
            --// reason to drop the target.
            if PathDestination ~= MobRoot.Position
                and AICCombat.MoveAlongTargetPath(Goblin, MobRoot.Position)
            then
                AICCombat.S.TargetUnreachableSince = nil
                AICCombat.S.TargetApproachPosition = nil
                return
            end
        
            --// ========================================================
            --// FOURTH PRIORITY:
            --// Reposition around the entire enemy group.
            --// ========================================================
        
            if not AICCombat.S.TargetUnreachableSince then
                AICCombat.S.TargetUnreachableSince = now
            end
        
            if not AICCombat.S.TargetApproachPosition
                or now - AICCombat.S.LastTargetRepositionTime >= CONFIG.TARGET_REPOSITION_INTERVAL
            then
                AICCombat.S.LastTargetRepositionTime = now
                AICCombat.S.TargetApproachPosition = AICCombat.GetTargetRepositionPosition(Goblin)
            end
        
            if AICCombat.S.TargetApproachPosition then
                local ApproachOffset = AICCombat.S.TargetApproachPosition - RootPart.Position
                local ApproachDistance = Vector3.new(ApproachOffset.X, 0, ApproachOffset.Z).Magnitude
        
                if ApproachDistance <= CONFIG.APPROACH_ARRIVAL_DISTANCE then
                    AICCombat.S.TargetApproachPosition = nil
                else
                    Humanoid.AutoRotate = false
                    Humanoid:MoveTo(AICCombat.S.TargetApproachPosition)
                    AICCombat.FaceGoblin(Goblin)
                    return
                end
            end
        
            --// No safe combat position was found. Do not make the target appear
            --// invisible just because the safe-position solver failed. If the direct
            --// route is clear, move toward the actual mob and let the blade-danger check
            --// above keep us from standing inside the enemy weapon range.
            if AICCombat.IsSafeCombatPathClear(MobRoot.Position, Goblin)
                and not AICCombatUtils.IsPathThroughWater(MobRoot.Position)
                and not AICCombatUtils.IsPathThroughDeadzone(MobRoot.Position)
            then
                AICCombat.S.TargetUnreachableSince = nil
                Humanoid.AutoRotate = false
                Humanoid:MoveTo(MobRoot.Position)
                AICCombat.FaceGoblin(Goblin)
                return
            end
        
            --// The mob is still a valid target even when the safe-position solver
            --// cannot find a perfect attack point. Keep the target locked while the
            --// pathfinding/reposition logic retries instead of dropping visibility.
            Humanoid.AutoRotate = true
            Humanoid:Move(Vector3.zero)
        
            if now - AICCombat.S.TargetUnreachableSince >= CONFIG.TARGET_UNREACHABLE_TIMEOUT then
                --// Nothing worked: no safe spot, no path to one, no path to the mob
                --// and no clear line. Remember that, or the next selection hands the
                --// same mob back and the whole attempt repeats forever.
                AICCombat.MarkMobUnreachable(Goblin)
        
                if AICCombat.S.ClosestTarget == Goblin then
                    AICCombat.S.ClosestTarget = nil
                end
        
                AICCombat.ResetTargetReposition()
                AICCombat.ResetTargetPath()
            end
        end
        
        ------------------------------------------------------------------------
        --// AICCombat  ::  target acquisition and attack / skill execution
        --// 8 function(s)
        ------------------------------------------------------------------------
        --// PRO COMBAT ACTION ENGINE
        function AICCombat.MoveAlongPathTo(Destination, AllowOutsideFarmArea)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Humanoid or not Destination then
                return false
            end
        
            local Path = PathfindingService:CreatePath({
                AgentRadius     = math.max(RootPart.Size.X * 0.5, 2),
                AgentHeight     = math.max(RootPart.Size.Y, 5),
                AgentCanJump    = true,
                WaypointSpacing = 4,
            })
        
            local Success = pcall(function()
                Path:ComputeAsync(RootPart.Position, Destination)
            end)
        
            if not Success or Path.Status ~= Enum.PathStatus.Success then
                return false
            end
        
            local Waypoints = Path:GetWaypoints()
        
            if #Waypoints < 2 then
                return false
            end
        
            for Index = 2, #Waypoints do
                local Waypoint = Waypoints[Index]
        
                --// Returning to the zone starts outside it by definition, so that
                --// caller opts out of the containment check.
                if not AllowOutsideFarmArea
                    and not AICCombatUtils.IsInsideFarmArea(Waypoint.Position)
                then
                    return false
                end
        
                if AICCombatUtils.IsInsideFarmDeadzone(Waypoint.Position) then
                    return false
                end
            end
        
            for Index = 2, #Waypoints do
                local Waypoint = Waypoints[Index]
                local Offset = Waypoint.Position - RootPart.Position
                local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
                if Distance > CONFIG.TARGET_PATH_WAYPOINT_DISTANCE then
                    --// The pathfinder marks jumps generously, including on flat ground.
                    --// Only take them when something is actually in the way, or when the
                    --// character has stopped making progress.
                    if Waypoint.Action == Enum.PathWaypointAction.Jump
                        and (AICCombatUtils.IsJumpableObstacleAhead(Waypoint.Position) or AICCombatUtils.IsStuck())
                    then
                        AICCombatUtils.DoJump()
                    end
        
                    Humanoid.AutoRotate = true
                    Humanoid:MoveTo(Waypoint.Position)
                    return true
                end
            end
        
            return false
        end
        
        
        ------------------------------------------------------------------------
        --// AICCombat
        --//
        --// targeting, approach, retreat and attack execution
        --//
        --// 49 function(s). Definitions only; nothing here runs
        --// at load time.
        ------------------------------------------------------------------------
        
        --// Target Reposition

        return Module
    end,
}
