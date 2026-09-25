-- WaypointLoop:
-- Walk the waypoint route from the first waypoint to the last waypoint.
--
-- A waypoint may be paired with a farm zone.
-- When the character reaches a paired waypoint:
--   * if the paired zone has targets, stop and fight there;
--   * if the paired zone is empty, continue to the next waypoint.
--
-- The first farm zone that is actually found with a target is remembered.
-- After the route reaches its last waypoint, if all paired zones are empty,
-- the character returns to that first farm zone and waits there for respawn.
--
-- Example:
--   WP34 -> Farm Zone #1
--   WP39 -> Farm Zone #2
--
-- Route:
--   WP1 -> ... -> WP34
--          -> fight Zone #1 if targets exist
--   WP35 -> ... -> WP39
--          -> fight Zone #2 if targets exist
--
-- If both zones are empty after reaching WP39:
--   WP39 -> WP38 -> ... -> WP34
--       -> wait at Zone #1 until targets respawn
--       -> fight
--       -> continue WP35 -> ... -> WP39 again.

return {
	Name = "WaypointLoop",
	IsFeature = true,
	Dependencies = {"Runtime", "ProfileManager", "Components", "Targeting", "Waypoints", "Farmzone"},

	Start = function(Context)
		local Runtime           = Context.Runtime
		local Players           = Context.Services.Players
		local CONFIG            = Context.CONFIG
		local FeatureState      = Context.Feature
		local AICConfig         = Context.AICConfig
		local AICProfile        = Context.AICProfile
		local AICCombat         = Context.AICCombat
		local AICCombatUtils    = Context.AICCombatUtils
		local AICFeature        = Context.AICFeature
		local AICUI             = Context.AICUI
		local UIRef             = Context.UIRef
		local NotifyAction      = Context.NotifyAction

		--// How often zones are rescanned for targets.
		local ZONE_SCAN_INTERVAL = 0.25

		--// How long a zone must stay empty before it is considered cleared.
		local ZONE_CLEAR_GRACE = 1.5

		local Feature = {
			Name = "WaypointLoop",
			IsFeature = true,
		}

		------------------------------------------------------------------------
		--// Runtime state
		------------------------------------------------------------------------

		AICFeature.S.Loop = {
			--// Current waypoint index.
			Index = nil,

			--// ROUTE  = walking forward through the waypoint route.
			--// FIGHT  = fighting/waiting at a paired farm zone.
			--// RETURN = walking backwards to the first farm zone that
			--//          previously had a target.
			Mode = "ROUTE",

			--// Farm waypoint currently being handled.
			FarmWaypoint = nil,

			--// Farm zone currently being handled.
			FarmZone = nil,

			--// First paired farm waypoint that was actually found with
			--// a living target during this route pass.
			FirstFarmWaypoint = nil,

			--// Zone index belonging to FirstFarmWaypoint.
			FirstFarmZone = nil,

			--// Time when the current farm zone was first seen empty.
			EmptySince = nil,

			--// Zone scan cache.
			ScanTime = 0,
			ScanResult = {},
		}

		local Loop = AICFeature.S.Loop

		------------------------------------------------------------------------
		--// Zone target helpers
		------------------------------------------------------------------------

		local function ZoneTargetNames(Zone)
			if type(Zone.Targets) == "table" and #Zone.Targets > 0 then
				return Zone.Targets
			end

			return CONFIG.TARGET_ENTITY_PRIORITY or {}
		end

		------------------------------------------------------------------------
		--// Waypoints paired with a valid farm zone, in route order.
		------------------------------------------------------------------------

		local function PairedWaypoints(PlaceConfig)
			local List = {}

			for WaypointIndex, ZoneIndex in ipairs(PlaceConfig.WAYPOINT_ZONES or {}) do
				if ZoneIndex > 0
					and PlaceConfig.WAYPOINTS[WaypointIndex]
					and PlaceConfig.FARM_ZONES[ZoneIndex]
				then
					table.insert(List, WaypointIndex)
				end
			end

			return List
		end

		------------------------------------------------------------------------
		--// True when a living target belonging to the zone exists inside it.
		------------------------------------------------------------------------

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

		------------------------------------------------------------------------
		--// Cached zone scan.
		------------------------------------------------------------------------

		local function ZoneHasTargets(PlaceConfig, ZoneIndex, now)
			if not ZoneIndex or ZoneIndex <= 0 then
				return false
			end

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

		local function ResetZoneScan()
			Loop.ScanTime = 0
			table.clear(Loop.ScanResult)
		end

		------------------------------------------------------------------------
		--// Stop movement.
		------------------------------------------------------------------------

		local function StandStill(Humanoid)
			local FaceOrientation = Runtime:GetFaceOrientation()

			if FaceOrientation then
				FaceOrientation.Enabled = false
			end

			Humanoid.AutoRotate = true
			Humanoid:Move(Vector3.zero)
		end

		------------------------------------------------------------------------
		--// Walk to a waypoint.
		------------------------------------------------------------------------

		local function StepTo(PlaceConfig, NextIndex, Humanoid, RootPart, now)
			local Target = PlaceConfig.WAYPOINTS[NextIndex]

			if not Target then
				return false
			end

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
				return true
			end

			local FaceOrientation = Runtime:GetFaceOrientation()

			if FaceOrientation then
				FaceOrientation.Enabled = false
			end

			Humanoid.AutoRotate = true
			Humanoid:MoveTo(Target)
			AICCombatUtils.DoJumpIfObstacle(Target)

			return false
		end

		------------------------------------------------------------------------
		--// Remember the first farm zone that actually contained a target.
		------------------------------------------------------------------------

		local function RememberFirstFarmZone(WaypointIndex, ZoneIndex)
			if Loop.FirstFarmWaypoint ~= nil then
				return
			end

			Loop.FirstFarmWaypoint = WaypointIndex
			Loop.FirstFarmZone = ZoneIndex
		end

		------------------------------------------------------------------------
		--// Enter the farm zone paired with a waypoint.
		------------------------------------------------------------------------

		local function EnterFarmZone(PlaceConfig, WaypointIndex)
			local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[WaypointIndex]

			if not ZoneIndex
				or ZoneIndex <= 0
				or not PlaceConfig.FARM_ZONES[ZoneIndex]
			then
				return false
			end

			Loop.FarmWaypoint = WaypointIndex
			Loop.FarmZone = ZoneIndex
			Loop.Mode = "FIGHT"
			Loop.EmptySince = nil

			AICCombatUtils.S.ActiveZoneIndex = ZoneIndex
			AICCombat.S.ClosestTarget = nil

			return true
		end

		------------------------------------------------------------------------
		--// Find the first paired zone that currently has targets.
		------------------------------------------------------------------------

		local function FindAnyActiveFarmZone(PlaceConfig, now)
			for Index = 1, #PlaceConfig.WAYPOINTS do
				local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[Index]

				if ZoneIndex
					and ZoneIndex > 0
					and PlaceConfig.FARM_ZONES[ZoneIndex]
					and ZoneHasTargets(PlaceConfig, ZoneIndex, now)
				then
					return Index, ZoneIndex
				end
			end

			return nil, nil
		end

		------------------------------------------------------------------------
		--// Find the first valid paired farm zone in route order.
		------------------------------------------------------------------------

		local function FindFirstPairedWaypoint(PlaceConfig)
			for Index = 1, #PlaceConfig.WAYPOINTS do
				local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[Index]

				if ZoneIndex
					and ZoneIndex > 0
					and PlaceConfig.FARM_ZONES[ZoneIndex]
				then
					return Index, ZoneIndex
				end
			end

			return nil, nil
		end

		------------------------------------------------------------------------
		--// Begin returning to the first farm zone that previously had a mob.
		--
		--// If no farm zone has ever been found with a mob, use the first
		--// paired farm zone as the fallback waiting location.
		------------------------------------------------------------------------

		local function BeginReturnToFarm(PlaceConfig)
			local WaypointIndex = Loop.FirstFarmWaypoint
			local ZoneIndex = Loop.FirstFarmZone

			if not WaypointIndex or not PlaceConfig.WAYPOINTS[WaypointIndex] then
				WaypointIndex, ZoneIndex = FindFirstPairedWaypoint(PlaceConfig)
			end

			if not WaypointIndex then
				return false
			end

			Loop.FarmWaypoint = WaypointIndex
			Loop.FarmZone = ZoneIndex
			Loop.Mode = "RETURN"
			Loop.EmptySince = nil

			return true
		end

		------------------------------------------------------------------------
		--// Reset the entire waypoint loop state.
		------------------------------------------------------------------------

		function AICFeature.ResetWaypointLoop()
			Loop.Index = nil
			Loop.Mode = "ROUTE"

			Loop.FarmWaypoint = nil
			Loop.FarmZone = nil

			Loop.FirstFarmWaypoint = nil
			Loop.FirstFarmZone = nil

			Loop.EmptySince = nil

			ResetZoneScan()

			AICCombatUtils.S.ActiveZoneIndex = nil
			AICCombat.S.ClosestTarget = nil
		end

		------------------------------------------------------------------------
		--// Called by the farm loop once per update.
		--
		--// nil     = loop does not apply
		--// "move" = waypoint movement is being handled
		--// "fight" = farm/combat logic should handle the current zone
		------------------------------------------------------------------------

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

			--------------------------------------------------------------------
			--// Initialize at WP1.
			--------------------------------------------------------------------

			if not Loop.Index or not PlaceConfig.WAYPOINTS[Loop.Index] then
				Loop.Index = 1
				Loop.Mode = "ROUTE"

				Loop.FarmWaypoint = nil
				Loop.FarmZone = nil

				Loop.FirstFarmWaypoint = nil
				Loop.FirstFarmZone = nil

				Loop.EmptySince = nil

				ResetZoneScan()

				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				StandStill(Humanoid)
			end

			--------------------------------------------------------------------
			--// ROUTE
			--
			--// Walk WP1 -> WP2 -> ... -> last waypoint.
			--------------------------------------------------------------------

			if Loop.Mode == "ROUTE" then
				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				local WaypointIndex = Loop.Index
				local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[WaypointIndex]

				----------------------------------------------------------------
				--// Check the farm zone paired with the current waypoint.
				----------------------------------------------------------------

				if ZoneIndex
					and ZoneIndex > 0
					and PlaceConfig.FARM_ZONES[ZoneIndex]
				then
					if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
						RememberFirstFarmZone(WaypointIndex, ZoneIndex)
						EnterFarmZone(PlaceConfig, WaypointIndex)

						return "fight"
					end
				end

				----------------------------------------------------------------
				--// Route reached the final waypoint.
				----------------------------------------------------------------

				if WaypointIndex >= #PlaceConfig.WAYPOINTS then
					----------------------------------------------------------------
					--// A different paired zone may currently have mobs.
					--// If so, handle it before returning.
					----------------------------------------------------------------

					local ActiveWaypoint, ActiveZone = FindAnyActiveFarmZone(PlaceConfig, now)

					if ActiveWaypoint then
						RememberFirstFarmZone(ActiveWaypoint, ActiveZone)
						EnterFarmZone(PlaceConfig, ActiveWaypoint)

						return "fight"
					end

					----------------------------------------------------------------
					--// Every paired zone is empty.
					--
					--// Return to the first farm zone that previously had mobs.
					----------------------------------------------------------------

					if BeginReturnToFarm(PlaceConfig) then
						return "move"
					end

					return "fight"
				end

				----------------------------------------------------------------
				--// Continue forward one waypoint.
				----------------------------------------------------------------

				StepTo(PlaceConfig, WaypointIndex + 1, Humanoid, RootPart, now)

				return "move"
			end

			--------------------------------------------------------------------
			--// FIGHT
			--
			--// Stay at the current paired zone while targets exist.
			--------------------------------------------------------------------

			if Loop.Mode == "FIGHT" then
				local WaypointIndex = Loop.FarmWaypoint
				local ZoneIndex = Loop.FarmZone

				if not WaypointIndex
					or not ZoneIndex
					or not PlaceConfig.WAYPOINTS[WaypointIndex]
					or not PlaceConfig.FARM_ZONES[ZoneIndex]
				then
					Loop.Mode = "ROUTE"
					Loop.FarmWaypoint = nil
					Loop.FarmZone = nil
					Loop.EmptySince = nil

					ResetZoneScan()

					return "move"
				end

				AICCombatUtils.S.ActiveZoneIndex = ZoneIndex

				if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
					Loop.EmptySince = nil
					return "fight"
				end

				Loop.EmptySince = Loop.EmptySince or now

				----------------------------------------------------------------
				--// Keep fighting/waiting briefly in case the scan temporarily
				--// misses a mob.
				----------------------------------------------------------------

				if now - Loop.EmptySince < ZONE_CLEAR_GRACE then
					return "fight"
				end

				----------------------------------------------------------------
				--// Zone is genuinely clear. Continue the forward route.
				----------------------------------------------------------------

				Loop.Mode = "ROUTE"
				Loop.EmptySince = nil

				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				ResetZoneScan()

				return "move"
			end

			--------------------------------------------------------------------
			--// RETURN
			--
			--// Walk backwards until the first farm zone that previously had
			--// a mob is reached.
			--------------------------------------------------------------------

			if Loop.Mode == "RETURN" then
				local TargetWaypoint = Loop.FarmWaypoint
				local TargetZone = Loop.FarmZone

				if not TargetWaypoint
					or not TargetZone
					or not PlaceConfig.WAYPOINTS[TargetWaypoint]
					or not PlaceConfig.FARM_ZONES[TargetZone]
				then
					Loop.Mode = "ROUTE"
					Loop.FarmWaypoint = nil
					Loop.FarmZone = nil
					Loop.EmptySince = nil

					ResetZoneScan()

					return "move"
				end

				----------------------------------------------------------------
				--// Reached the farm waypoint.
				----------------------------------------------------------------

				if Loop.Index == TargetWaypoint then
					Loop.Mode = "FIGHT"
					Loop.EmptySince = nil

					AICCombatUtils.S.ActiveZoneIndex = TargetZone
					AICCombat.S.ClosestTarget = nil

					ResetZoneScan()

					return "fight"
				end

				----------------------------------------------------------------
				--// Move backwards one waypoint.
				----------------------------------------------------------------

				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				StepTo(PlaceConfig, Loop.Index - 1, Humanoid, RootPart, now)

				return "move"
			end

			--------------------------------------------------------------------
			--// Safety fallback.
			--------------------------------------------------------------------

			Loop.Mode = "ROUTE"
			Loop.FarmWaypoint = nil
			Loop.FarmZone = nil
			Loop.EmptySince = nil

			ResetZoneScan()

			return "move"
		end

		function Feature:Update()
		end

		------------------------------------------------------------------------
		--// UI: waypoint pairing
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
			local ZoneOptions = {"None"}

			for Index in ipairs(PlaceConfig.WAYPOINTS) do
				table.insert(WaypointOptions, "Waypoint #" .. Index)
			end

			for Index in ipairs(PlaceConfig.FARM_ZONES) do
				table.insert(ZoneOptions, ZoneOptionLabel(Index))
			end

			if #WaypointOptions == 0 then
				WaypointOptions = {"No Waypoints"}
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

				Current.WAYPOINT_ZONES = AICConfig.NormalizeZonePairs(
					Current.WAYPOINT_ZONES,
					#Current.WAYPOINTS,
					#Current.FARM_ZONES
				)

				--// Nothing changed: do not save or rebuild.
				if Current.WAYPOINT_ZONES[SelectedPairWaypoint] == ZoneIndex then
					return
				end

				Current.WAYPOINT_ZONES[SelectedPairWaypoint] = ZoneIndex

				AICFeature.ResetWaypointLoop()
				AICProfile.SaveActiveProfile()
				AICUI.RefreshWaypointList()

				AICUI.SetProfileStatus(
					"WAYPOINT #" .. SelectedPairWaypoint .. " -> " .. ZoneOptionLabel(ZoneIndex):upper()
				)
			end)

			if PlaceConfig.WAYPOINTS[SelectedPairWaypoint] then
				UIRef.PairWaypointPicker:Set(WaypointOptions[SelectedPairWaypoint], false)
				UIRef.PairZonePicker:Set(
					ZoneOptionLabel(PlaceConfig.WAYPOINT_ZONES[SelectedPairWaypoint] or 0),
					false
				)
			end
		end

		------------------------------------------------------------------------
		--// Targets of the farm zone picked in "Edit Farm Zone".
		------------------------------------------------------------------------

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
				Options = {"No detected enemies"}
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

		------------------------------------------------------------------------
		--// Waypoint Loop toggle
		------------------------------------------------------------------------

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

		------------------------------------------------------------------------
		--// Farm Zone Target component
		------------------------------------------------------------------------

		if UIRef.FarmzoneSection then
			UIRef.ZoneTargetsComponent = UIRef.FarmzoneSection:AddPriority("Zone Targets", {})

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
				if not Guard() then
					return false
				end

				local Changed = OriginalRemove(self, Value)

				Commit(self)

				return Changed
			end

			function Component:MoveUp(Value)
				if not Guard() then
					return
				end

				OriginalMoveUp(self, Value)
				Commit(self)
			end

			function Component:MoveDown(Value)
				if not Guard() then
					return
				end

				OriginalMoveDown(self, Value)
				Commit(self)
			end

			AICUI.RefreshZoneTargets()
		end

		return Feature
	end,
}
