return {
    Name = "Combat",
    Dependencies = {"Runtime", "CombatUtils", "Targeting", "Navigation"},
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
        function AICCombat.FaceGoblin(Goblin)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
        local FaceOrientation = Runtime:GetFaceOrientation()
            if not RootPart or not Goblin then
                return
            end
        
            local MobRoot = Goblin:FindFirstChild("HumanoidRootPart")
        
            if not MobRoot then
                return
            end
        
            local RootPosition = RootPart.Position
            local TargetPosition = MobRoot.Position
        
            local Direction = Vector3.new(
                TargetPosition.X - RootPosition.X,
                0,
                TargetPosition.Z - RootPosition.Z
            )
        
            if Direction.Magnitude <= 0.01 then
                return
            end
        
            FaceOrientation.CFrame = CFrame.lookAt(
                RootPosition,
                RootPosition + Direction
            )
        
            FaceOrientation.Enabled = true
        end
        function AICCombat.GetCombatHealthPercent()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not Humanoid or Humanoid.MaxHealth <= 0 then
                return 100
            end
        
            return (Humanoid.Health / Humanoid.MaxHealth) * 100
        end
        function AICCombat.IsEnemyUsingSkill(Mob)
            if not Mob then
                return false
            end
        
            local EnemySword = Mob:FindFirstChild("Sword")
            local BladePart = EnemySword and EnemySword:FindFirstChild("BladePart")
            local SkillObject = Mob:FindFirstChild("Skill", true)
            local Sparkles = BladePart and BladePart:FindFirstChild("Sparkles", true)
        
            local SkillSoundActive = SkillObject
                and SkillObject:IsA("Sound")
                and SkillObject.IsPlaying
        
            local SparklesActive = Sparkles
                and Sparkles:IsA("ParticleEmitter")
                and Sparkles.Enabled
        
            return SkillSoundActive or SparklesActive or false
        end
        
        --// Scan every nearby living priority mob, not only the current target. A
        --// skill from a mob we are not fighting lands just the same, and the old
        --// check missed it entirely.
        function AICCombat.GetSkillThreat()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return false, nil
            end
        
            local Range = tonumber(CONFIG.SKILL_DETECT_DISTANCE) or 45
            local Closest = nil
            local ClosestDistance = math.huge
        
            local function Consider(Mob)
                local MobRoot = Mob:FindFirstChild("HumanoidRootPart")
                local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
        
                if not MobRoot or not MobHumanoid or MobHumanoid.Health <= 0 then
                    return
                end
        
                --// Distance first: it is far cheaper than walking the mob for a
                --// sound and an emitter, and this runs every frame.
                local Distance = AICCombatUtils.GetHorizontalDistance(RootPart.Position, MobRoot.Position)
        
                if Distance > Range or Distance >= ClosestDistance then
                    return
                end
        
                if AICCombat.IsEnemyUsingSkill(Mob) then
                    Closest = Mob
                    ClosestDistance = Distance
                end
            end
        
            --// Only whether a skill is in progress matters, not which mob is closest,
            --// so this stops at the first hit instead of ranking them. It runs every
            --// heartbeat, so the saving is worth having.
            for Mob in AICCombat.S.ValidMobs do
                if Mob:IsDescendantOf(workspace) then
                    Consider(Mob)
        
                    if Closest then
                        return true, Closest
                    end
                end
            end
        
            --// ValidMobs lags a freshly spawned mob by up to one validation tick, so
            --// also look straight at the folder.
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if MobFolder then
                for _, Mob in MobFolder:GetChildren() do
                    if Mob:IsA("Model") and not AICCombat.S.ValidMobs[Mob] then
                        local Config = Mob:FindFirstChild("Config")
                        local Entity = Config and Config:FindFirstChild("Entity")
        
                        if Entity
                            and Entity:IsA("StringValue")
                            and AICCombat.IsEntityInPriority(Entity.Value)
                        then
                            Consider(Mob)
        
                            if Closest then
                                return true, Closest
                            end
                        end
                    end
                end
            end
        
            return Closest ~= nil, Closest
        end
        
        --// Latches the dodge on for a short hold. The sound and the emitter both
        --// flicker, and without this the script would step back into the attack
        --// between two frames of the same skill.
        function AICCombat.UpdateSkillThreat(now)
            local Detected = AICCombat.GetSkillThreat()
        
            if Detected then
                AICCombat.S.SkillThreatUntil = now + (tonumber(CONFIG.SKILL_DODGE_HOLD) or 0.75)
            end
        
            return now < AICCombat.S.SkillThreatUntil
        end
        function AICCombat.GetCombatAttackRange(TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            local Range = CONFIG.COMBAT_ATTACK_RANGE
        
            if not TargetMob then
                return Range
            end
        
            local MobHumanoid = TargetMob:FindFirstChildOfClass("Humanoid")
            if MobHumanoid and MobHumanoid.MaxHealth > 0 then
                local HP = (MobHumanoid.Health / MobHumanoid.MaxHealth) * 100
                if HP <= CONFIG.COMBAT_FINISHER_HP_PERCENT then
                    Range += CONFIG.COMBAT_FINISHER_RANGE_BONUS
                end
            end
        
            return Range
        end
        function AICCombat.FaceCombatTarget(TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
        local FaceOrientation = Runtime:GetFaceOrientation()
            if not RootPart or not TargetMob then
                return
            end
        
            local TargetRoot = TargetMob:FindFirstChild("HumanoidRootPart")
            if not TargetRoot then
                return
            end
        
            local Offset = TargetRoot.Position - RootPart.Position
            local Flat = Vector3.new(Offset.X, 0, Offset.Z)
            if Flat.Magnitude <= 0.01 then
                return
            end
        
            if FaceOrientation then
                FaceOrientation.CFrame = CFrame.lookAt(
                    RootPart.Position,
                    RootPart.Position + Flat.Unit
                )
                FaceOrientation.Enabled = true
            end
        end
        function AICCombat.InvokeCombatInput(InputName)
            local InputBindableFunction = Runtime:GetInputBindableFunction()
            if not InputBindableFunction then
                return false
            end
        
            local Success = pcall(function()
                InputBindableFunction:Invoke(
                    InputName,
                    Enum.UserInputState.Begin
                )
            end)
        
            return Success
        end
        function AICCombat.CanCombatAttack(TargetMob, now)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not TargetMob or not RootPart then
                return false
            end
        
            local MobHumanoid = TargetMob:FindFirstChildOfClass("Humanoid")
            local MobRoot = TargetMob:FindFirstChild("HumanoidRootPart")
            if not MobHumanoid or not MobRoot or MobHumanoid.Health <= 0 then
                return false
            end
        
            local Offset = MobRoot.Position - RootPart.Position
            local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
            if CONFIG.DISTANCE_Y_CALCULATE then
                Distance = Offset.Magnitude
            end
        
            return Distance <= AICCombat.GetCombatAttackRange(TargetMob)
                and now >= AICCombat.S.COMBAT_NEXT_ATTACK_TIME
        end
        function AICCombat.PerformCombatActions(TargetMob, now)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not TargetMob or not AICCombat.IsCombatTargetValid(TargetMob) then
                return
            end
        
            local MobRoot = TargetMob:FindFirstChild("HumanoidRootPart")
            local MobHumanoid = TargetMob:FindFirstChildOfClass("Humanoid")
            if not MobRoot or not MobHumanoid or MobHumanoid.Health <= 0 then
                return
            end
        
            local Offset = MobRoot.Position - RootPart.Position
            local Distance = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
        
            if CONFIG.DISTANCE_Y_CALCULATE then
                Distance = Offset.Magnitude
            end
        
            local EnemySkill = AICCombat.IsEnemyUsingSkill(TargetMob)
            local PlayerHP = AICCombat.GetCombatHealthPercent()
        
            if Distance <= CONFIG.COMBAT_FACE_RANGE then
                AICCombat.FaceCombatTarget(TargetMob)
            end
        
            if Feature.AutoSkill.Enabled
                and Distance <= CONFIG.COMBAT_SKILL_RANGE
                and PlayerHP >= CONFIG.COMBAT_SKILL_MIN_HP_PERCENT
                and not EnemySkill
                and now >= AICCombat.S.COMBAT_NEXT_SKILL_TIME
            then
                if AICCombat.InvokeCombatInput("SkillButton") then
                    AICCombat.S.LAST_SKILL_TIME = now
                    AICCombat.S.COMBAT_NEXT_SKILL_TIME = now + CONFIG.SKILL_INTERVAL
                    AICCombat.S.COMBAT_NEXT_ATTACK_TIME = math.max(AICCombat.S.COMBAT_NEXT_ATTACK_TIME, now + 0.08)
                end
            end
        
            if AICCombat.CanCombatAttack(TargetMob, now) then
                if AICCombat.InvokeCombatInput("AttackButton") then
                    AICCombat.S.LAST_ATTACK_TIME = now
                    AICCombat.S.COMBAT_ATTACK_PHASE = (AICCombat.S.COMBAT_ATTACK_PHASE % 2) + 1
        
                    local PhaseJitter = (AICCombat.S.COMBAT_ATTACK_PHASE == 1)
                        and CONFIG.COMBAT_ACTION_JITTER
                        or 0
        
                    AICCombat.S.COMBAT_NEXT_ATTACK_TIME = now
                        + CONFIG.ATTACK_INTERVAL
                        + PhaseJitter
                end
            end
        end
        function AICCombat.GetLivingGoblins()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            --// Cached for a fraction of a second. The retreat solver asks for this
            --// once per candidate position, which meant rescanning the entire mob
            --// folder tens of times for a single decision.
            local now = os.clock()
        
            if AICCombat.S.LivingGoblinCache
                and now - AICCombat.S.LivingGoblinCacheTime < (tonumber(CONFIG.LIVING_MOB_CACHE_INTERVAL) or 0.1)
            then
                return AICCombat.S.LivingGoblinCache
            end
        
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if not MobFolder then
                AICCombat.S.LivingGoblinCache = {}
                AICCombat.S.LivingGoblinCacheTime = now
                return AICCombat.S.LivingGoblinCache
            end
        
            local Goblins = {}
        
            for _, Mob in MobFolder:GetChildren() do
                if not Mob:IsA("Model") then
                    continue
                end
        
                local Config      = Mob:FindFirstChild("Config")
                local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
                local MobRoot     = Mob:FindFirstChild("HumanoidRootPart")
        
                if not Config or not MobHumanoid or not MobRoot then
                    continue
                end
        
                local Entity = Config:FindFirstChild("Entity")
        
                if not Entity then
                    continue
                end
        
                if not AICCombat.IsEntityInPriority(Entity.Value) then
                    continue
                end
        
                if MobHumanoid.Health <= 0 then
                    continue
                end
        
                table.insert(Goblins, Mob)
            end
        
            AICCombat.S.LivingGoblinCache = Goblins
            AICCombat.S.LivingGoblinCacheTime = now
        
            return Goblins
        end
        
        --// Return all mobs around the current combat group.
        function AICCombat.GetNearbyCombatMobs(TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not TargetMob then
                return {}
            end
        
            local TargetRoot = TargetMob:FindFirstChild("HumanoidRootPart")
        
            if not TargetRoot then
                return {}
            end
        
            local now = os.clock()
            local Cached = AICCombat.S.CombatGroupCache[TargetMob]
        
            if Cached
                and now - Cached.Time < CONFIG.COMBAT_GROUP_CACHE_INTERVAL
            then
                return Cached.Mobs
            end
        
            local NearbyMobs = {
                [TargetMob] = true,
            }
        
            local TargetPosition = TargetRoot.Position
        
            for Mob in AICCombat.S.ValidMobs do
                if Mob == TargetMob then
                    continue
                end
        
                if not Mob:IsDescendantOf(workspace) then
                    continue
                end
        
                local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
                local MobRoot     = Mob:FindFirstChild("HumanoidRootPart")
        
                if not MobHumanoid
                    or not MobRoot
                    or MobHumanoid.Health <= 0
                then
                    continue
                end
        
                local Distance = AICCombatUtils.GetHorizontalDistance(TargetPosition, MobRoot.Position)
        
                if Distance <= CONFIG.GROUP_DANGER_DISTANCE then
                    NearbyMobs[Mob] = true
                end
            end
        
            --// Also inspect Mobs directly from workspace so a newly spawned
            --// mob that has not entered ValidMobs yet can still be considered.
            local MobFolder = workspace:FindFirstChild("Mobs")
        
            if MobFolder then
                for _, Mob in MobFolder:GetChildren() do
                    if NearbyMobs[Mob] or not Mob:IsA("Model") then
                        continue
                    end
        
                    local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
                    local MobRoot     = Mob:FindFirstChild("HumanoidRootPart")
        
                    if not MobHumanoid
                        or not MobRoot
                        or MobHumanoid.Health <= 0
                    then
                        continue
                    end
        
                    local Config = Mob:FindFirstChild("Config")
                    local Entity = Config and Config:FindFirstChild("Entity")
        
                    if not Entity
                        or not Entity:IsA("StringValue")
                        or not AICCombat.IsEntityInPriority(Entity.Value)
                    then
                        continue
                    end
        
                    local Distance = AICCombatUtils.GetHorizontalDistance(TargetPosition, MobRoot.Position)
        
                    if Distance <= CONFIG.GROUP_DANGER_DISTANCE then
                        NearbyMobs[Mob] = true
                    end
                end
            end
        
            local Result = {}
        
            for Mob in NearbyMobs do
                table.insert(Result, Mob)
            end
        
            AICCombat.S.CombatGroupCache[TargetMob] = {
                Time = now,
                Mobs = Result,
            }
        
            return Result
        end
        
        --// Return cached BladeParts for the entire combat group.
        function AICCombat.GetCombatBladeParts(TargetMob)
            if not TargetMob then
                return {}
            end
        
            local now = os.clock()
            local Cached = AICCombat.S.CombatBladeCache[TargetMob]
        
            if Cached
                and now - Cached.Time < CONFIG.COMBAT_GROUP_CACHE_INTERVAL
            then
                return Cached.Parts
            end
        
            local BladeParts = {}
        
            for _, Mob in AICCombat.GetNearbyCombatMobs(TargetMob) do
                for _, BladePart in AICCombatUtils.GetBladeParts(Mob) do
                    if BladePart:IsDescendantOf(workspace) then
                        table.insert(BladeParts, BladePart)
                    end
                end
            end
        
            AICCombat.S.CombatBladeCache[TargetMob] = {
                Time  = now,
                Parts = BladeParts,
            }
        
            return BladeParts
        end
        
        --// Checks every BladePart in the combat group.
        function AICCombat.GetBladeDangerData(TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetMob then
                return Vector3.zero, math.huge, nil
            end
        
            local PushDirection            = Vector3.zero
            local ClosestEffectiveDistance = math.huge
            local ClosestBlade             = nil
            local DangerDistance           = AICCombatUtils.GetBladeDangerDistance()
        
            for _, BladePart in AICCombat.GetCombatBladeParts(TargetMob) do
                local ClosestPoint, Distance = AICCombatUtils.GetClosestPointOnBlade(BladePart, RootPart.Position)
        
                if not ClosestPoint then
                    continue
                end
        
                local EffectiveDistance = Distance - DangerDistance
        
                if EffectiveDistance < ClosestEffectiveDistance then
                    ClosestEffectiveDistance = EffectiveDistance
                    ClosestBlade = BladePart
                end
        
                if Distance <= DangerDistance then
                    local Offset = RootPart.Position - ClosestPoint
                    local HorizontalOffset = Vector3.new(Offset.X, 0, Offset.Z)
        
                    if HorizontalOffset.Magnitude > 0.01 then
                        local Strength = math.max(DangerDistance - Distance, 0.1)
                        PushDirection += HorizontalOffset.Unit * Strength
                    end
                end
            end
        
            if PushDirection.Magnitude > 0.01 then
                PushDirection = PushDirection.Unit
            end
        
            return PushDirection, ClosestEffectiveDistance, ClosestBlade
        end
        
        --// Check whether a position is safe from every BladePart
        --// in the nearby enemy group.
        function AICCombat.IsPositionSafeFromBladeGroup(Position, TargetMob)
            if not Position or not TargetMob then
                return true
            end
        
            local DangerDistance = AICCombatUtils.GetBladeDangerDistance()
        
            for _, BladePart in AICCombat.GetCombatBladeParts(TargetMob) do
                local _, Distance = AICCombatUtils.GetClosestPointOnBlade(BladePart, Position)
        
                if Distance <= DangerDistance then
                    return false
                end
            end
        
            return true
        end
        
        --// Checks whether a movement line crosses a BladePart danger zone.
        function AICCombat.IsPathThroughBladeGroupDanger(TargetPosition, TargetMob)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart or not TargetPosition or not TargetMob then
                return false
            end
        
            local Origin = RootPart.Position
            local Offset = TargetPosition - Origin
            local Distance = Offset.Magnitude
            local DangerDistance = AICCombatUtils.GetBladeDangerDistance()
            local BladeParts = AICCombat.GetCombatBladeParts(TargetMob)
        
            if Distance <= 0.01 then
                for _, BladePart in BladeParts do
                    local _, BladeDistance = AICCombatUtils.GetClosestPointOnBlade(BladePart, TargetPosition)
        
                    if BladeDistance <= DangerDistance then
                        return true
                    end
                end
        
                return false
            end
        
            local Direction = Offset.Unit
            local SampleDistance = 2
        
            for DistanceTravelled = 0, Distance, SampleDistance do
                local Position = Origin + Direction * DistanceTravelled
        
                for _, BladePart in BladeParts do
                    local _, BladeDistance = AICCombatUtils.GetClosestPointOnBlade(BladePart, Position)
        
                    if BladeDistance <= DangerDistance then
                        return true
                    end
                end
            end
        
            return false
        end
        
        
        ------------------------------------------------------------------------
        --// AICFeature
        --//
        --// standalone behaviours: route, patrol, zones, blocking, upkeep
        --//
        --// 22 function(s). Definitions only; nothing here runs
        --// at load time.
        ------------------------------------------------------------------------
        
        ------------------------------------------------------------------------
        --// AICState  ::  character handle, player stats, shared resets
        --// 9 function(s)
        ------------------------------------------------------------------------
        --// Character
        return Module
    end,
}
