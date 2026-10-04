-- MiningMovement walks Auto Mining to a spot. It walks straight while that
-- is safe and switches to pathfinding when the straight line is not: a wall
-- a hop cannot clear, a hole too wide to jump, a climb higher than a jump,
-- a deadzone in the way, or leaving the mine zone. A hole that can be jumped
-- is jumped at its edge. Paths are solved off the heartbeat, so a slow solve
-- never stalls a frame, and a path that enters a deadzone (or leaves the
-- mine zone, once inside it) is refused.
return {
    Name = "MiningMovement",
    Dependencies = {"Runtime", "CombatUtils"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local Services = Context.Services
        local Players = Services.Players
        local PathfindingService = Services.PathfindingService
        local FeatureState = Context.Feature
        local AICCombatUtils = Context.AICCombatUtils

        --// How often the straight line is re-tested; holes need this often
        --// enough to jump at the edge rather than past it.
        local DIRECT_CHECK_INTERVAL = 0.1
        --// Taller than this above the feet needs a path, not a straight walk.
        local MAX_DIRECT_RISE = 6
        local WALL_PROBE_DISTANCE = 12
        --// Jump once the hole edge is this close.
        local HOLE_JUMP_EDGE = 2.5
        --// Once on a path, stay on it at least this long so a borderline
        --// straight line does not flip the mode every frame.
        local PATH_HOLD_SECONDS = 4
        local PATH_RECALCULATE_INTERVAL = 3
        local PATH_RETRY_INTERVAL = 2
        local PATH_WAYPOINT_REACH = 3
        local PATH_DESTINATION_TOLERANCE = 4
        --// Jumping has not freed the character for this long: take a path.
        local STUCK_PATH_SECONDS = 1.5
        local ZONE_SAMPLE_DISTANCE = 4

        local Movement = {
            Name = "MiningMovement",
            S = {
                Holding = false,
                PathUntil = 0,
                StuckSince = nil,
                LastDirectCheck = 0,
                DirectBlocked = false,
                HoleCanJump = false,
                HoleEdge = nil,
                PathToken = 0,
                Path = {},
            },
        }

        local S = Movement.S

        local function CanUseGround(Position, KeepInsideMine)
            if not FeatureState.IgnoreFarmZone.Enabled and AICCombatUtils.IsInsideFarmDeadzone(Position) then
                return false
            end

            return not KeepInsideMine or AICCombatUtils.IsInsideMineZone(Position)
        end

        local function SegmentStaysInMine(From, To)
            local Offset = To - From
            local Distance = Offset.Magnitude

            if Distance <= 0 then
                return AICCombatUtils.IsInsideMineZone(To)
            end

            for Travelled = ZONE_SAMPLE_DISTANCE, Distance, ZONE_SAMPLE_DISTANCE do
                if not AICCombatUtils.IsInsideMineZone(From + Offset.Unit * Travelled) then
                    return false
                end
            end

            return AICCombatUtils.IsInsideMineZone(To)
        end

        local function BuildWallParams(Character, IgnoreModel)
            local Filter = { Character }

            if IgnoreModel then
                table.insert(Filter, IgnoreModel)
            end

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

            local Params = RaycastParams.new()
            Params.FilterType = Enum.RaycastFilterType.Exclude
            Params.FilterDescendantsInstances = Filter
            return Params
        end

        --// A wall straight ahead that a hop will not clear.
        local function IsWallAhead(RootPart, Character, Destination, IgnoreModel)
            local Offset = Destination - RootPart.Position
            local Flat = Vector3.new(Offset.X, 0, Offset.Z)

            if Flat.Magnitude <= 0.5 then
                return false
            end

            local Hit = workspace:Raycast(
                RootPart.Position,
                Flat.Unit * math.min(Flat.Magnitude, WALL_PROBE_DISTANCE),
                BuildWallParams(Character, IgnoreModel)
            )

            return Hit ~= nil and not AICCombatUtils.IsJumpableObstacleAhead(Destination)
        end

        --// Re-tests the straight line at most every DIRECT_CHECK_INTERVAL.
        local function UpdateDirectCheck(now, RootPart, Character, Destination, Options)
            if now - S.LastDirectCheck < DIRECT_CHECK_INTERVAL then
                return
            end

            S.LastDirectCheck = now

            local IsHole, CanJump, Edge = AICCombatUtils.IsHoleAhead(Destination)
            S.HoleCanJump = IsHole and CanJump
            S.HoleEdge = Edge

            S.DirectBlocked = (IsHole and not CanJump)
                or Destination.Y - RootPart.Position.Y > MAX_DIRECT_RISE
                or AICCombatUtils.IsPathThroughDeadzone(Destination)
                or (Options.KeepInsideMine and not SegmentStaysInMine(RootPart.Position, Destination))
                or IsWallAhead(RootPart, Character, Destination, Options.Ignore)
        end

        local function JumpHoleIfClose()
            if S.HoleCanJump and S.HoleEdge and S.HoleEdge <= HOLE_JUMP_EDGE then
                AICCombatUtils.DoJump()
            end
        end

        local function IsRouteAllowed(Waypoints, KeepInsideMine)
            for Index = 2, #Waypoints do
                if not CanUseGround(Waypoints[Index].Position, KeepInsideMine) then
                    return false
                end
            end

            return true
        end

        local function RequestPath(RootPart, Destination, KeepInsideMine)
            local Path = S.Path
            local From = RootPart.Position
            local AgentRadius = math.max(RootPart.Size.X * 0.5, 2)
            local AgentHeight = math.max(RootPart.Size.Y, 5)

            S.PathToken += 1
            local Token = S.PathToken
            Path.Computing = true

            task.spawn(function()
                local Solver = PathfindingService:CreatePath({
                    AgentRadius = AgentRadius,
                    AgentHeight = AgentHeight,
                    AgentCanJump = true,
                    WaypointSpacing = 4,
                })

                local Ok = pcall(function()
                    Solver:ComputeAsync(From, Destination)
                end)

                --// Reset or superseded while solving.
                if Token ~= S.PathToken then
                    return
                end

                Path.Computing = false

                local Waypoints = Ok and Solver.Status == Enum.PathStatus.Success and Solver:GetWaypoints()

                if not Waypoints or #Waypoints < 2 or not IsRouteAllowed(Waypoints, KeepInsideMine) then
                    Path.Waypoints = nil
                    Path.FailedAt = os.clock()
                    return
                end

                Path.Waypoints = Waypoints
                Path.Index = 2
                Path.Destination = Destination
                Path.Time = os.clock()
                Path.FailedAt = nil
            end)
        end

        --// "moving", "waiting" while a path is being solved, "failed" when
        --// no allowed path exists, or "done" once the path is walked.
        local function FollowPath(now, RootPart, Humanoid, Destination, KeepInsideMine)
            local Path = S.Path
            local Stale = not Path.Waypoints
                or (Path.Destination - Destination).Magnitude > PATH_DESTINATION_TOLERANCE
                or now - Path.Time >= PATH_RECALCULATE_INTERVAL
            local MayRetry = not Path.FailedAt or now - Path.FailedAt >= PATH_RETRY_INTERVAL

            if Stale and not Path.Computing and MayRetry then
                RequestPath(RootPart, Destination, KeepInsideMine)
            end

            if not Path.Waypoints then
                return Path.Computing and "waiting" or "failed"
            end

            while Path.Index <= #Path.Waypoints do
                local Waypoint = Path.Waypoints[Path.Index]

                if AICCombatUtils.GetHorizontalDistance(Waypoint.Position, RootPart.Position) <= PATH_WAYPOINT_REACH then
                    Path.Index += 1
                    continue
                end

                --// The solver marks jumps generously; only take one when
                --// something is in the way or the character has stalled.
                if Waypoint.Action == Enum.PathWaypointAction.Jump
                    and (AICCombatUtils.IsJumpableObstacleAhead(Waypoint.Position) or AICCombatUtils.IsStuck())
                then
                    AICCombatUtils.DoJump()
                end

                JumpHoleIfClose()
                Humanoid:MoveTo(Waypoint.Position)
                return "moving"
            end

            Path.Waypoints = nil
            S.PathUntil = 0
            return "done"
        end

        local function UpdateStuck(now)
            if not AICCombatUtils.IsStuck() then
                S.StuckSince = nil
                return
            end

            S.StuckSince = S.StuckSince or now
            AICCombatUtils.DoJump()

            if now - S.StuckSince >= STUCK_PATH_SECONDS then
                S.PathUntil = now + PATH_HOLD_SECONDS
                S.StuckSince = nil
                AICCombatUtils.ResetStuckTracker()
            end
        end

        --// Stands still. A MoveTo stays active until reached, so it is
        --// cancelled once by moving to where we already are.
        function Movement:Hold()
            local _, Humanoid, RootPart = Runtime:GetCharacter()

            if not Humanoid or not RootPart then
                return
            end

            if not S.Holding then
                S.Holding = true
                Humanoid:MoveTo(RootPart.Position)
            end

            Humanoid:Move(Vector3.zero)
        end

        --// Options:
        --//   Ignore          model the walls probe looks through (the ore)
        --//   KeepInsideMine  never step outside the mine zones
        --// Returns "moving", "waiting" (standing while a path is solved) or
        --// "failed" (no allowed way there).
        function Movement:MoveTo(Destination, Options)
            local Character, Humanoid, RootPart = Runtime:GetCharacter()

            if not Humanoid or not RootPart then
                return "failed"
            end

            Options = Options or {}

            local now = os.clock()
            local FaceOrientation = Runtime:GetFaceOrientation()

            if FaceOrientation then
                FaceOrientation.Enabled = false
            end

            Humanoid.AutoRotate = true
            S.Holding = false

            UpdateStuck(now)
            UpdateDirectCheck(now, RootPart, Character, Destination, Options)

            if S.DirectBlocked and now >= S.PathUntil then
                S.PathUntil = now + PATH_HOLD_SECONDS
            end

            if now < S.PathUntil then
                local Result = FollowPath(now, RootPart, Humanoid, Destination, Options.KeepInsideMine)

                if Result == "moving" then
                    return Result
                end

                --// Never walk the blocked straight line meanwhile; that is
                --// the hole or the deadzone the path is going around.
                if Result == "waiting" or (Result == "failed" and S.DirectBlocked) then
                    self:Hold()
                    return Result
                end
            end

            JumpHoleIfClose()
            AICCombatUtils.DoJumpIfObstacle(Destination)
            Humanoid:MoveTo(Destination)
            return "moving"
        end

        function Movement:Reset()
            S.PathToken += 1
            S.Holding = false
            S.PathUntil = 0
            S.StuckSince = nil
            S.LastDirectCheck = 0
            S.DirectBlocked = false
            S.HoleCanJump = false
            S.HoleEdge = nil
            table.clear(S.Path)
        end

        return Movement
    end,
}
