-- WaypointLoop: after the waypoint route is walked, farm only the farm zones
-- paired with a waypoint, walking the route between them.
--
-- Each waypoint may be paired with one farm zone, and each farm zone may have
-- its own target list (empty = the Enemy Priority list). Once the route
-- reaches its last waypoint the character walks to the nearest paired
-- waypoint and fights in that zone, one zone at a time:
--   * with a single paired zone it stays there for good, waiting inside the
--     zone while nothing is alive;
--   * with two or more, once a zone is cleared it walks on to the next
--     paired zone (route order, wrapping around; a zone already seen to have
--     targets goes first), e.g. zones on #33 and #39 alternate 33 > 39 > 33.
-- The walk only uses the waypoints between paired ones: it never heads back
-- past the first or last paired waypoint.
return {
	Name = "WaypointLoop",
	IsFeature = true,
	Dependencies = {"Runtime", "ProfileManager", "Components", "Targeting", "Waypoints", "Farmzone"},

	Start = function(Context)
		local Runtime = Context.Runtime
		local Players = Context.Services.Players
		local CONFIG = Context.CONFIG
		local FeatureState = Context.Feature
		local AICConfig = Context.AICConfig
		local AICProfile = Context.AICProfile
		local AICCombat = Context.AICCombat
		local AICCombatUtils = Context.AICCombatUtils
		local AICFeature = Context.AICFeature
		local AICUI = Context.AICUI
		local AICDebug = Context.AICDebug
		local UIRef = Context.UIRef
		local NotifyAction = Context.NotifyAction

		--// How often zones are rescanned for targets.
		local ZONE_SCAN_INTERVAL = 0.25
		--// How long a zone must stay empty before it counts as cleared, so a
		--// scan that misses a mob for a moment does not send us away.
		local ZONE_CLEAR_GRACE = 1.5

		local Feature = {
			Name = "WaypointLoop",
			IsFeature = true,
		}

		AICFeature.S.Loop = {
			--// Waypoint the character is at, or nil before the route ends.
			Index = nil,
			--// Paired waypoint being walked to or fought at.
			Goal = nil,
			--// When the goal zone was first seen empty, or nil.
			EmptySince = nil,
			ScanTime = 0,
			ScanResult = {},
		}

		local Loop = AICFeature.S.Loop

		local function ZoneTargetNames(Zone)
			if type(Zone.Targets) == "table" and #Zone.Targets > 0 then
				return Zone.Targets
			end

			return CONFIG.TARGET_ENTITY_PRIORITY or {}
		end

		--// Waypoints paired with an existing farm zone, in route order.
		local function PairedWaypoints(PlaceConfig)
			local List = {}

			for WaypointIndex, ZoneIndex in ipairs(PlaceConfig.WAYPOINT_ZONES or {}) do
				if ZoneIndex > 0 and PlaceConfig.WAYPOINTS[WaypointIndex] and PlaceConfig.FARM_ZONES[ZoneIndex] then
					table.insert(List, WaypointIndex)
				end
			end

			return List
		end

		--// True when a living target of this zone's list stands inside it.
		local function ScanZone(Zone)
			local Names = ZoneTargetNames(Zone)

			if #Names == 0 then
				return false
			end

			local MobFolder = workspace:FindFirstChild("Mobs")
			local Candidates = MobFolder and MobFolder:GetChildren() or {}

			for _, OtherPlayer in ipairs(Players:GetPlayers()) do
				if OtherPlayer.Character then
					table.insert(Candidates, OtherPlayer.Character)
				end
			end

			for _, Mob in ipairs(Candidates) do
				local EntityName = AICCombat.GetTargetEntityName(Mob)

				if EntityName and table.find(Names, EntityName) then
					local MobHumanoid = Mob:FindFirstChildOfClass("Humanoid")
					local MobRoot = Mob:FindFirstChild("HumanoidRootPart")

					if MobHumanoid
						and MobRoot
						and MobHumanoid.Health > 0
						and AICCombatUtils.IsPositionInsideZone(MobRoot.Position, Zone)
						and not AICCombatUtils.IsInsideFarmDeadzone(MobRoot.Position)
					then
						return true
					end
				end
			end

			return false
		end

		local function ZoneHasTargets(PlaceConfig, ZoneIndex, now)
			if now - Loop.ScanTime >= ZONE_SCAN_INTERVAL then
				Loop.ScanTime = now
				table.clear(Loop.ScanResult)
			end

			if Loop.ScanResult[ZoneIndex] == nil then
				local Zone = PlaceConfig.FARM_ZONES[ZoneIndex]
				Loop.ScanResult[ZoneIndex] = Zone ~= nil and ScanZone(Zone)
			end

			return Loop.ScanResult[ZoneIndex]
		end

		--// First goal once the route ends: the nearest paired waypoint (by
		--// route distance), preferring one whose zone already shows targets.
		local function FirstGoal(PlaceConfig, Paired, now)
			local Best, BestScore = nil, math.huge

			for _, WaypointIndex in ipairs(Paired) do
				local Score = math.abs(WaypointIndex - Loop.Index)

				if not ZoneHasTargets(PlaceConfig, PlaceConfig.WAYPOINT_ZONES[WaypointIndex], now) then
					Score += #PlaceConfig.WAYPOINTS
				end

				if Score < BestScore then
					Best, BestScore = WaypointIndex, Score
				end
			end

			return Best
		end

		--// Next paired waypoint after the cleared Goal, in route order and
		--// wrapping around. Waypoints paired with the goal's own zone are
		--// skipped, and a zone already seen to have targets is preferred.
		--// nil when every paired waypoint belongs to the goal's zone.
		local function NextGoal(PlaceConfig, Paired, Goal, now)
			local Position = table.find(Paired, Goal) or 0
			local GoalZone = PlaceConfig.WAYPOINT_ZONES[Goal]
			local FirstOther = nil

			for Step = 1, #Paired - 1 do
				local WaypointIndex = Paired[(Position + Step - 1) % #Paired + 1]
				local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[WaypointIndex]

				if ZoneIndex ~= GoalZone then
					if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
						return WaypointIndex
					end

					FirstOther = FirstOther or WaypointIndex
				end
			end

			return FirstOther
		end

		local function StandStill(Humanoid)
			local FaceOrientation = Runtime:GetFaceOrientation()

			if FaceOrientation then
				FaceOrientation.Enabled = false
			end

			Humanoid.AutoRotate = true
			Humanoid:Move(Vector3.zero)
		end

		--// Walks to the neighbouring waypoint NextIndex; on arrival that becomes
		--// the current waypoint, and its wait time (if any) is honoured.
		local function StepTo(PlaceConfig, NextIndex, Humanoid, RootPart, now)
			local Target = PlaceConfig.WAYPOINTS[NextIndex]
			local Offset = Target - RootPart.Position
			local Horizontal = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
			local Reach = tonumber(PlaceConfig.REACH_DISTANCE) or 5

			if Horizontal <= Reach and math.abs(Offset.Y) <= math.max(Reach, CONFIG.JUMP_HEIGHT + 2) then
				Loop.Index = NextIndex

				local Wait = tonumber(PlaceConfig.WAYPOINT_WAITS and PlaceConfig.WAYPOINT_WAITS[NextIndex]) or 0

				if Wait > 0 then
					AICFeature.S.WaypointWaitUntil = now + Wait
				end

				StandStill(Humanoid)
				return
			end

			local FaceOrientation = Runtime:GetFaceOrientation()

			if FaceOrientation then
				FaceOrientation.Enabled = false
			end

			Humanoid.AutoRotate = true
			Humanoid:MoveTo(Target)
			AICCombatUtils.DoJumpIfObstacle(Target)
		end

		function AICFeature.ResetWaypointLoop()
			Loop.Index = nil
			Loop.Goal = nil
			Loop.EmptySince = nil
			table.clear(Loop.ScanResult)
			AICCombatUtils.S.ActiveZoneIndex = nil
		end

		--// Called by the farm loop once the route has been walked.
		--//   nil     the loop does not apply; farm as before
		--//   "fight" fight (or wait) inside the active paired zone
		--//   "move"  the loop moved the character this frame
		function AICFeature.WaypointLoopStep(now)
			local PlaceConfig = Runtime:GetPlaceConfig()
			local _, Humanoid, RootPart = Runtime:GetCharacter()
			local Paired = PlaceConfig and PairedWaypoints(PlaceConfig) or {}

			if not FeatureState.WaypointLoop.Enabled
				or FeatureState.AutoFind.Enabled
				or FeatureState.IgnoreFarmZone.Enabled
				or not PlaceConfig
				or not Humanoid
				or not RootPart
				or #PlaceConfig.WAYPOINTS == 0
				or #Paired == 0
			then
				if Loop.Index then
					AICFeature.ResetWaypointLoop()
				end

				return nil
			end

			if not Loop.Index or not PlaceConfig.WAYPOINTS[Loop.Index] then
				Loop.Index = #PlaceConfig.WAYPOINTS
				Loop.Goal = nil
			end

			--// No goal yet, or its pair was removed: pick from where we stand.
			if not Loop.Goal or not table.find(Paired, Loop.Goal) then
				Loop.Goal = FirstGoal(PlaceConfig, Paired, now)
				Loop.EmptySince = nil
			end

			local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[Loop.Goal]
			AICCombatUtils.S.ActiveZoneIndex = ZoneIndex

			if not ZoneHasTargets(PlaceConfig, ZoneIndex, now) and Loop.Goal ~= Loop.Index then
				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil
				StepTo(PlaceConfig, Loop.Index + (Loop.Goal > Loop.Index and 1 or -1), Humanoid, RootPart, now)
				return "move"
			end

			if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
				Loop.EmptySince = nil
				return "fight"
			end

			Loop.EmptySince = Loop.EmptySince or now

			--// Zone cleared: head for the next paired zone. With a single
			--// zone there is nowhere else to go, so keep waiting inside it.
			if now - Loop.EmptySince >= ZONE_CLEAR_GRACE then
				local Next = NextGoal(PlaceConfig, Paired, Loop.Goal, now)

				if Next then
					Loop.Goal = Next
					Loop.EmptySince = nil
				end
			end

			return "fight"
		end

		function Feature:Update()
		end

		------------------------------------------------------------------------
		--// UI: waypoint pairing (Waypoints section) and zone targets (Farmzone)
		------------------------------------------------------------------------
		local SelectedPairWaypoint = 1

		local function DestroyDropdown(Dropdown)
			if Dropdown then
				if Dropdown.Popup then Dropdown.Popup:Destroy() end
				if Dropdown.Frame then Dropdown.Frame:Destroy() end
			end
		end

		local function ZoneOptionLabel(ZoneIndex)
			return ZoneIndex > 0 and ("Farm Zone #" .. ZoneIndex) or "None"
		end

		function AICUI.RefreshWaypointPairPickers()
			local Section = UIRef.WaypointSection

			if not Section then
				return
			end

			local PlaceConfig = Runtime:GetPlaceConfig()
			local WaypointOptions = {}
			local ZoneOptions = { "None" }

			for Index in ipairs(PlaceConfig.WAYPOINTS) do
				table.insert(WaypointOptions, "Waypoint #" .. Index)
			end

			for Index in ipairs(PlaceConfig.FARM_ZONES) do
				table.insert(ZoneOptions, ZoneOptionLabel(Index))
			end

			if #WaypointOptions == 0 then
				WaypointOptions = { "No Waypoints" }
			end

			SelectedPairWaypoint = math.clamp(SelectedPairWaypoint, 1, math.max(1, #PlaceConfig.WAYPOINTS))

			DestroyDropdown(UIRef.PairWaypointPicker)
			DestroyDropdown(UIRef.PairZonePicker)

			UIRef.PairWaypointPicker = Section:AddDropdown("Pair Waypoint", WaypointOptions, function(Value)
				local Index = table.find(WaypointOptions, Value)

				if Index and PlaceConfig.WAYPOINTS[Index] then
					SelectedPairWaypoint = Index

					if UIRef.PairZonePicker then
						UIRef.PairZonePicker:Set(ZoneOptionLabel(PlaceConfig.WAYPOINT_ZONES[Index] or 0), false)
					end
				end
			end)

			UIRef.PairZonePicker = Section:AddDropdown("Paired Farm Zone", ZoneOptions, function(Value)
				local Current = Runtime:GetPlaceConfig()

				if not Current.WAYPOINTS[SelectedPairWaypoint] then
					return
				end

				if not AICProfile.S.ActiveProfileName then
					AICUI.SetProfileStatus("CREATE / LOAD PROFILE FIRST")
					return
				end

				local ZoneIndex = (table.find(ZoneOptions, Value) or 1) - 1

				Current.WAYPOINT_ZONES = AICConfig.NormalizeZonePairs(Current.WAYPOINT_ZONES, #Current.WAYPOINTS, #Current.FARM_ZONES)

				--// Nothing changed: do not save or rebuild. Rebuilding recreates
				--// this dropdown, which is how the startup freeze looped.
				if Current.WAYPOINT_ZONES[SelectedPairWaypoint] == ZoneIndex then
					return
				end

				Current.WAYPOINT_ZONES[SelectedPairWaypoint] = ZoneIndex
				AICFeature.ResetWaypointLoop()
				AICProfile.SaveActiveProfile()
				AICUI.RefreshWaypointList()
				AICUI.SetProfileStatus("WAYPOINT #" .. SelectedPairWaypoint .. " -> " .. ZoneOptionLabel(ZoneIndex):upper())
			end)

			if PlaceConfig.WAYPOINTS[SelectedPairWaypoint] then
				UIRef.PairWaypointPicker:Set(WaypointOptions[SelectedPairWaypoint], false)
				UIRef.PairZonePicker:Set(ZoneOptionLabel(PlaceConfig.WAYPOINT_ZONES[SelectedPairWaypoint] or 0), false)
			end
		end

		--// Targets of the farm zone picked in "Edit Farm Zone".
		local function SelectedZone()
			local PlaceConfig = Runtime:GetPlaceConfig()
			return PlaceConfig.FARM_ZONES[AICProfile.S.SelectedFarmZoneIndex]
		end

		function AICUI.RefreshZoneTargets()
			local Section = UIRef.FarmzoneSection

			if not Section or not UIRef.ZoneTargetsComponent then
				return
			end

			local Zone = SelectedZone()
			UIRef.ZoneTargetsComponent:SetPriority(table.clone(Zone and Zone.Targets or {}))

			--// Choices: everything detected nearby plus the Enemy Priority list.
			local Options = {}

			for _, Name in ipairs(AICCombat.GetDetectedEnemyEntities()) do
				table.insert(Options, Name)
			end

			for _, Name in ipairs(CONFIG.TARGET_ENTITY_PRIORITY or {}) do
				if not table.find(Options, Name) then
					table.insert(Options, Name)
				end
			end

			for Index = #Options, 1, -1 do
				if Zone and table.find(Zone.Targets or {}, Options[Index]) then
					table.remove(Options, Index)
				end
			end

			if #Options == 0 then
				Options = { "No detected enemies" }
			end

			DestroyDropdown(UIRef.ZoneTargetDropdown)

			UIRef.ZoneTargetDropdown = Section:AddDropdown("Add Zone Target", Options, function(Value)
				local Current = SelectedZone()

				if not Current or Value == "No detected enemies" then
					return
				end

				if not AICProfile.S.ActiveProfileName then
					AICUI.SetProfileStatus("CREATE / LOAD PROFILE FIRST")
					return
				end

				Current.Targets = Current.Targets or {}

				if not table.find(Current.Targets, Value) then
					table.insert(Current.Targets, Value)
					AICProfile.SaveActiveProfile()
					NotifyAction("Zone Targets", "Added " .. Value)
				end

				AICUI.RefreshZoneTargets()
			end)
		end

		if UIRef.WaypointSection then
			FeatureState.WaypointLoop.Button = UIRef.WaypointSection:AddToggle(
				"Waypoint Loop",
				FeatureState.WaypointLoop.Enabled,
				function(Value)
					FeatureState.WaypointLoop.Enabled = Value
					AICFeature.ResetWaypointLoop()
					AICProfile.SaveActiveProfile()
				end
			)

			AICUI.RefreshWaypointPairPickers()
		end

		if UIRef.FarmzoneSection then
			UIRef.ZoneTargetsComponent = UIRef.FarmzoneSection:AddPriority("Zone Targets", {})

			--// The list mirrors the selected zone's Targets; every edit is
			--// written back to the zone and saved.
			local Component = UIRef.ZoneTargetsComponent
			local OriginalRemove = Component.Remove
			local OriginalMoveUp = Component.MoveUp
			local OriginalMoveDown = Component.MoveDown

			local function Commit(Component)
				local Zone = SelectedZone()

				if Zone then
					Zone.Targets = table.clone(Component.Priority)
					AICProfile.SaveActiveProfile()
				end

				AICUI.RefreshZoneTargets()
			end

			local function Guard()
				if AICProfile.S.ActiveProfileName and SelectedZone() then
					return true
				end

				AICUI.SetProfileStatus("CREATE / LOAD PROFILE FIRST")
				return false
			end

			function Component:Remove(Value)
				if not Guard() then return false end
				local Changed = OriginalRemove(self, Value)
				Commit(self)
				return Changed
			end

			function Component:MoveUp(Value)
				if not Guard() then return end
				OriginalMoveUp(self, Value)
				Commit(self)
			end

			function Component:MoveDown(Value)
				if not Guard() then return end
				OriginalMoveDown(self, Value)
				Commit(self)
			end

			AICUI.RefreshZoneTargets()
		end

		return Feature
	end,
}
