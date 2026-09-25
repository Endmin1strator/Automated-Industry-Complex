return {
    Name = "CombatUtils",
    Dependencies = {"Runtime"},
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

        local Module = Context.AICCombatUtils
        function AICCombatUtils.UpdateStuckTracker(now, IsMoving)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return
            end
        
            if not IsMoving then
                AICCombatUtils.S.StuckSamplePosition = nil
                AICCombatUtils.S.StuckStrikes = 0
                return
            end
        
            if now - AICCombatUtils.S.StuckSampleTime < (tonumber(CONFIG.STUCK_SAMPLE_INTERVAL) or 0.35) then
                return
            end
        
            AICCombatUtils.S.StuckSampleTime = now
        
            if AICCombatUtils.S.StuckSamplePosition then
                local Moved = (RootPart.Position - AICCombatUtils.S.StuckSamplePosition).Magnitude
        
                if Moved < (tonumber(CONFIG.STUCK_MIN_PROGRESS) or 0.6) then
                    AICCombatUtils.S.StuckStrikes += 1
                else
                    AICCombatUtils.S.StuckStrikes = 0
                end
            end
        
            AICCombatUtils.S.StuckSamplePosition = RootPart.Position
        end
        function AICCombatUtils.IsStuck()
            return AICCombatUtils.S.StuckStrikes >= 2
        end
        function AICCombatUtils.DoJumpIfObstacle(TargetPosition)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Humanoid then
                return false
            end
        
            if not AICCombatUtils.IsJumpableObstacleAhead(TargetPosition) then
                return false
            end
        
            AICCombatUtils.DoJump()
            return true
        end
        function AICCombatUtils.DoJump()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Humanoid then
                return
            end
        
            if Humanoid.FloorMaterial ~= Enum.Material.Air
                and Humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
            then
                Humanoid.Jump = true
                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
        
        ------------------------------------------------------------------------
        --// AICWorld  ::  zones, water, ground, line of sight, path clearance
        --// 12 function(s)
        ------------------------------------------------------------------------
        --// Farm Area Check
        --// Shared cylinder test for farm zones and deadzones.
        function AICCombatUtils.IsPositionInsideZone(Position, Zone)
            if not Position or not Zone or not Zone.Center then
                return false
            end
        
            local Offset = Position - Zone.Center
            local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
            if Distance > (tonumber(Zone.Radius) or 0) then
                return false
            end
        
            local MaxHeight = tonumber(CONFIG.ZONE_MAX_HEIGHT_DIFFERENCE) or 0
        
            if MaxHeight > 0 and math.abs(Offset.Y) > MaxHeight then
                return false
            end
        
            return true
        end
        function AICCombatUtils.IsInsideFarmDeadzone(Position)
            local PlaceConfig = Runtime:GetPlaceConfig()
            if not Position or not PlaceConfig then
                return false
            end
        
            for _, Zone in ipairs(PlaceConfig.DEADZONES or {}) do
                if AICCombatUtils.IsPositionInsideZone(Position, Zone) then
                    return true
                end
            end
        
            return false
        end
        function AICCombatUtils.IsInsideFarmArea(Position)
            local PlaceConfig = Runtime:GetPlaceConfig()
            if Feature.IgnoreFarmZone.Enabled or not PlaceConfig then
                return true
            end
        
            if not Position then
                return false
            end
        
            local FarmZones = PlaceConfig.FARM_ZONES or {}
        
            --// No farm zones means the profile does not constrain the farm area.
            --// Deadzones can still be used independently.
            if #FarmZones == 0 then
                return not AICCombatUtils.IsInsideFarmDeadzone(Position)
            end
        
            local InsideAnyFarmZone = false
        
            for _, Zone in ipairs(FarmZones) do
                if AICCombatUtils.IsPositionInsideZone(Position, Zone) then
                    InsideAnyFarmZone = true
                    break
                end
            end
        
            if not InsideAnyFarmZone then
                return false
            end
        
            return not AICCombatUtils.IsInsideFarmDeadzone(Position)
        end
        
        --// Water Check
        function AICCombatUtils.IsWaterAtPosition(Position, IgnoreModel)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Position then
                return false
            end
        
            local FilterInstances = {
                Character,
            }
        
            if IgnoreModel then
                table.insert(FilterInstances, IgnoreModel)
            end
            if AICCombatUtils.S.DebugFolder then
                table.insert(FilterInstances, AICCombatUtils.S.DebugFolder)
            end
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = FilterInstances
        
            local Origin    = Position + Vector3.new(0, 10, 0)
            local Direction = Vector3.new(0, -30, 0)
        
            local Result = workspace:Raycast(Origin, Direction, RaycastParams)
        
            return Result and Result.Material == Enum.Material.Water
        end
        function AICCombatUtils.IsPathThroughWater(TargetPosition)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return true
            end
        
            local Origin   = RootPart.Position
            local Offset   = TargetPosition - Origin
            local Distance = Offset.Magnitude
        
            if Distance <= 0 then
                return AICCombatUtils.IsWaterAtPosition(TargetPosition)
            end
        
            local Direction = Offset.Unit
        
            for DistanceTravelled = 0, Distance, CONFIG.WATER_SAMPLE_DISTANCE do
                local Position = Origin + Direction * DistanceTravelled
        
                if AICCombatUtils.IsWaterAtPosition(Position) then
                    return true
                end
            end
        
            return AICCombatUtils.IsWaterAtPosition(TargetPosition)
        end
        
        --// Deadzone Path Check
        function AICCombatUtils.IsPathThroughDeadzone(TargetPosition)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
        local PlaceConfig = Runtime:GetPlaceConfig()
            if Feature.IgnoreFarmZone.Enabled then
                return false
            end
        
            if not RootPart or not TargetPosition or not PlaceConfig then
                return false
            end
        
            local Origin   = RootPart.Position
            local Offset   = TargetPosition - Origin
            local Distance = Offset.Magnitude
        
            if Distance <= 0 then
                return AICCombatUtils.IsInsideFarmDeadzone(Origin)
            end
        
            local Direction = Offset.Unit
        
            for DistanceTravelled = 0, Distance, CONFIG.DEADZONE_SAMPLE_DISTANCE do
                local Position = Origin + Direction * DistanceTravelled
        
                if AICCombatUtils.IsInsideFarmDeadzone(Position) then
                    return true
                end
            end
        
            return AICCombatUtils.IsInsideFarmDeadzone(TargetPosition)
        end
        
        --// Line Of Sight
        function AICCombatUtils.CanSeeGoblin(Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not Goblin then
                return false
            end
        
            local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
            if not MobRoot then
                return false
            end
        
            local Origin    = RootPart.Position
            local Direction = MobRoot.Position - Origin
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = {
                Character,
            }
            if AICCombatUtils.S.DebugFolder then
                table.insert(RaycastParams.FilterDescendantsInstances, AICCombatUtils.S.DebugFolder)
            end
        
            local Result = workspace:Raycast(Origin, Direction, RaycastParams)
        
            if not Result then
                return true
            end
        
            return Result.Instance:IsDescendantOf(Goblin)
        end
        
        --// ============================================================
        --// COMBAT BLADE SYSTEM
        --// ============================================================
        function AICCombatUtils.GetHorizontalDistance(PositionA, PositionB)
            local Offset = PositionA - PositionB
        
            return Vector3.new(
                Offset.X,
                0,
                Offset.Z
            ).Magnitude
        end
        
        --// Retreat Obstacle Check
        function AICCombatUtils.IsPathClear(TargetPosition)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return false
            end
        
            if AICCombatUtils.IsWaterAtPosition(TargetPosition) then
                return false
            end
        
            if AICCombatUtils.IsPathThroughWater(TargetPosition) then
                return false
            end
        
            if AICCombatUtils.IsPathThroughDeadzone(TargetPosition) then
                return false
            end
        
            local Origin    = RootPart.Position
            local Direction = TargetPosition - Origin
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = {
                Character,
            }
            if AICCombatUtils.S.DebugFolder then
                table.insert(RaycastParams.FilterDescendantsInstances, AICCombatUtils.S.DebugFolder)
            end
        
            local Result = workspace:Raycast(Origin, Direction, RaycastParams)
        
            return Result == nil
        end
        function AICCombatUtils.IsEscapePathClear(TargetPosition)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition then
                return false
            end
        
            if not AICCombatUtils.IsInsideFarmArea(TargetPosition) then
                return false
            end
        
            if AICCombatUtils.IsWaterAtPosition(TargetPosition) then
                return false
            end
        
            if AICCombatUtils.IsPathThroughWater(TargetPosition) then
                return false
            end
        
            local Origin = RootPart.Position
            local Direction = TargetPosition - Origin
        
            if Direction.Magnitude <= 0.01 then
                return false
            end
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = {
                Character,
            }
            if AICCombatUtils.S.DebugFolder then
                table.insert(RaycastParams.FilterDescendantsInstances, AICCombatUtils.S.DebugFolder)
            end
        
            if workspace:Raycast(Origin, Direction, RaycastParams) then
                return false
            end
        
            --// Also check the character's physical width so the center point
            --// cannot pass a wall while the character body gets stuck on it.
            local BlockcastSize = Vector3.new(
                math.max(RootPart.Size.X, 2.5),
                math.max(RootPart.Size.Y, 4),
                math.max(RootPart.Size.Z, 2.5)
            )
        
            local BlockcastCFrame = CFrame.new(Origin)
            local BlockcastResult = workspace:Blockcast(
                BlockcastCFrame,
                BlockcastSize,
                Direction,
                RaycastParams
            )
        
            return BlockcastResult == nil
        end
        function AICCombatUtils.CanSeeGoblinFromPosition(Position, Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Position or not Goblin then
                return false
            end
        
            local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
            if not MobRoot then
                return false
            end
        
            local Direction = MobRoot.Position - Position
        
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
        
            local Result = workspace:Raycast(Position, Direction, RaycastParams)
        
            return Result == nil
        end
        
        --// ============================================================
        --// AUTO PATROL
        --// ============================================================
        --// True when something in the way can actually be jumped over.
        --//
        --// Two probes at different heights: a hit low down with clear space above it
        --// is a ledge, a step or a rock, and a jump clears it. A hit at both heights
        --// is a wall, where jumping achieves nothing. Nothing at either height means
        --// the path is open and there is no reason to leave the ground.
        --//
        --// Also treats ground that steps up sharply just ahead as jumpable, since a
        --// short ledge can sit below the low probe.
        function AICCombatUtils.IsJumpableObstacleAhead(TargetPosition)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition then
                return false
            end
        
            local Origin = RootPart.Position
            local Offset = TargetPosition - Origin
            local Flat = Vector3.new(Offset.X, 0, Offset.Z)
        
            if Flat.Magnitude <= 0.01 then
                return false
            end
        
            local Direction = Flat.Unit * (tonumber(CONFIG.JUMP_PROBE_DISTANCE) or 4.5)
        
            local Params = RaycastParams.new()
            Params.FilterType = Enum.RaycastFilterType.Exclude
            local Filter = { Character }
        
            --// Mobs and other players are not obstacles to jump over.
            local MobFolder = workspace:FindFirstChild("Mobs")
            if MobFolder then
                table.insert(Filter, MobFolder)
            end
            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                if OtherPlayer.Character and OtherPlayer.Character ~= Character then
                    table.insert(Filter, OtherPlayer.Character)
                end
            end
            if AICCombatUtils.S.DebugFolder then
                table.insert(Filter, AICCombatUtils.S.DebugFolder)
            end
            Params.FilterDescendantsInstances = Filter
        
            local HalfHeight = RootPart.Size.Y * 0.5
            local Feet = Origin - Vector3.new(0, HalfHeight, 0)
        
            local LowOrigin = Feet + Vector3.new(0, tonumber(CONFIG.JUMP_PROBE_LOW_OFFSET) or 0.6, 0)
            local HighOrigin = Feet + Vector3.new(0, tonumber(CONFIG.JUMP_PROBE_HIGH_OFFSET) or 3.2, 0)
        
            local LowHit = workspace:Raycast(LowOrigin, Direction, Params)
            local HighHit = workspace:Raycast(HighOrigin, Direction, Params)
        
            if LowHit and not HighHit then
                return true
            end
        
            if LowHit and HighHit then
                --// Solid from the ground up. Jumping will not get us past it.
                return false
            end
        
            --// Nothing hit either probe. Check for a step up that both probes passed
            --// over, by sampling the ground a little way ahead.
            local AheadOrigin = Origin + Flat.Unit * (tonumber(CONFIG.JUMP_PROBE_DISTANCE) or 4.5)
            local Down = workspace:Raycast(
                AheadOrigin + Vector3.new(0, HalfHeight, 0),
                Vector3.new(0, -(HalfHeight * 2 + 6), 0),
                Params
            )
        
            if not Down then
                return false
            end
        
            local StepUp = Down.Position.Y - Feet.Y
        
            return StepUp >= (tonumber(CONFIG.JUMP_STEP_HEIGHT) or 1.2)
        end
        function AICCombatUtils.GetPatrolGroundPosition(Position)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Position or not RootPart then
                return nil
            end
        
            if not AICCombatUtils.IsInsideFarmArea(Position) then
                return nil
            end
        
            local RaycastParams = RaycastParams.new()
            RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
            RaycastParams.FilterDescendantsInstances = {Character}
            if AICCombatUtils.S.DebugFolder then
                table.insert(RaycastParams.FilterDescendantsInstances, AICCombatUtils.S.DebugFolder)
            end
        
            --// เพิ่มความสูงเริ่มยิงและระยะยิงให้ครอบคลุมภูมิประเทศที่สูง/ต่ำกว่าเดิมมาก
            local Origin = Vector3.new(Position.X, RootPart.Position.Y + 60, Position.Z)
            local Result = workspace:Raycast(Origin, Vector3.new(0, -250, 0), RaycastParams)
        
            if not Result then
                return nil
            end
        
            if Result.Material == Enum.Material.Water then
                return nil
            end
        
            if Result.Normal.Y < 0.5 then
                return nil
            end
        
            local GroundPosition = Vector3.new(
                Position.X,
                Result.Position.Y + RootPart.Size.Y * 0.5,
                Position.Z
            )
        
            if AICCombatUtils.IsWaterAtPosition(GroundPosition)
                or AICCombatUtils.IsInsideFarmDeadzone(GroundPosition)
            then
                return nil
            end
        
            return GroundPosition
        end
        function AICCombatUtils.GetMobDistance(Mob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local MobRoot = Mob:FindFirstChild("HumanoidRootPart")
        
            if not MobRoot or not RootPart then
                return math.huge
            end
        
            local Offset = MobRoot.Position - RootPart.Position
        
            if CONFIG.DISTANCE_Y_CALCULATE then
                return Offset.Magnitude
            end
        
            return Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        end
        function AICCombatUtils.GetMobHealth(Mob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local MobHumanoid = Mob and Mob:FindFirstChildOfClass("Humanoid")
        
            if not MobHumanoid then
                return 0
            end
        
            return MobHumanoid.Health
        end
        
        ------------------------------------------------------------------------
        --// AICBlade  ::  enemy weapon hitboxes and danger geometry
        --// 8 function(s)
        ------------------------------------------------------------------------
        --// Get every BladePart inside one Mob.
        function AICCombatUtils.GetBladeParts(Mob)
            if not Mob then
                return {}
            end
        
            local now = os.clock()
            local Cached = AICCombatUtils.S.BladePartCache[Mob]
        
            if Cached
                and now - Cached.Time < CONFIG.BLADE_PART_CACHE_INTERVAL
            then
                return Cached.Parts
            end
        
            local BladeParts = {}
        
            for _, Descendant in Mob:GetDescendants() do
                if Descendant:IsA("BasePart") and Descendant.Name == "BladePart" then
                    table.insert(BladeParts, Descendant)
                end
            end
        
            AICCombatUtils.S.BladePartCache[Mob] = {
                Time  = now,
                Parts = BladeParts,
            }
        
            return BladeParts
        end
        
        --// Finds the closest point on an actual BladePart box.
        --// This is much more accurate than simply using BladePart.Position.
        function AICCombatUtils.GetClosestPointOnBlade(BladePart, Position)
            if not BladePart or not BladePart:IsA("BasePart") then
                return nil, math.huge
            end
        
            local LocalPosition = BladePart.CFrame:PointToObjectSpace(Position)
            local HalfSize      = BladePart.Size * 0.5
        
            local ClosestLocal = Vector3.new(
                math.clamp(LocalPosition.X, -HalfSize.X, HalfSize.X),
                math.clamp(LocalPosition.Y, -HalfSize.Y, HalfSize.Y),
                math.clamp(LocalPosition.Z, -HalfSize.Z, HalfSize.Z)
            )
        
            local ClosestWorld = BladePart.CFrame:PointToWorldSpace(ClosestLocal)
            local Distance     = (Position - ClosestWorld).Magnitude
        
            return ClosestWorld, Distance
        end
        function AICCombatUtils.GetBladeDangerDistance()
            return CONFIG.ENEMY_ATTACK_SAFE_DISTANCE + CONFIG.ENEMY_BLADE_PADDING
        end
        
        --// Walks a computed path toward a destination. Used when the straight line
        --// is blocked: the farm zone return had no pathfinding at all, so a wall or
        --// a ledge between the character and the zone left it walking into geometry.

        return Module
    end,
}
