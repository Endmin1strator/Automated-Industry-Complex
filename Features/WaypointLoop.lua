-- WaypointLoop:
-- Walk the waypoint route from WP1 to the last waypoint.
--
-- Every waypoint paired with a farm zone is checked when reached:
--   * targets found -> fight until the zone is clear;
--   * no targets    -> continue to the next waypoint.
--
-- The first farm zone that actually gets fought is remembered.
-- After reaching the last waypoint:
--   * if a paired zone has targets, fight it;
--   * if all paired zones are empty, walk backwards to the first farm zone
--     that was previously fought and wait there for respawn;
--   * if no farm zone has ever been fought, return to the first paired zone
--     and wait there.
--
-- After a fight is finished, the route continues forward again.

return {
	Name = "WaypointLoop",
	IsFeature = true,
	Dependencies = {"Runtime", "ProfileManager", "Components", "Targeting", "Waypoints", "Farmzone"},

	Start = function(Context)
		local Runtime        = Context.Runtime
		local Players        = Context.Services.Players
		local CONFIG         = Context.CONFIG
		local FeatureState   = Context.Feature
		local AICConfig      = Context.AICConfig
		local AICProfile     = Context.AICProfile
		local AICCombat      = Context.AICCombat
		local AICCombatUtils = Context.AICCombatUtils
		local AICFeature     = Context.AICFeature
		local AICUI          = Context.AICUI
		local NotifyAction   = Context.NotifyAction
		local UIRef          = Context.UIRef

		local ZONE_SCAN_INTERVAL = 0.25
		local ZONE_CLEAR_GRACE   = 1.5

		local Feature = {
			Name = "WaypointLoop",
			IsFeature = true,
		}

		AICFeature.S.Loop = {
			--// Current waypoint.
			--// 0 means the character has not reached WP1 yet.
			Index = 0,

			--// ROUTE   = walking forward through waypoints.
			--// FIGHT   = fighting/waiting at a paired farm zone.
			--// RETURN  = walking backwards to the first farm zone.
			Mode = "ROUTE",

			--// Farm zone currently being handled.
			FarmWaypoint = nil,
			FarmZone = nil,

			--// First farm zone that actually had a target and was fought.
			FirstFarmWaypoint = nil,
			FirstFarmZone = nil,

			--// Used when deciding whether a zone has really cleared.
			EmptySince = nil,

			--// Zone scan cache.
			ScanTime = 0,
			ScanResult = {},
		}

		local Loop = AICFeature.S.Loop

		------------------------------------------------------------------------
		--// Farm Zone target list
		------------------------------------------------------------------------

		local function ZoneTargetNames(Zone)
			if type(Zone.Targets) == "table" and #Zone.Targets > 0 then
				return Zone.Targets
			end

			return CONFIG.TARGET_ENTITY_PRIORITY or {}
		end

		------------------------------------------------------------------------
		--// Waypoints paired with valid Farm Zones.
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
		--// Check whether the specified Farm Zone currently contains a target.
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
		--// Remember the first Farm Zone that actually had a target.
		------------------------------------------------------------------------

		local function RememberFirstFarmZone(WaypointIndex, ZoneIndex)
			if Loop.FirstFarmWaypoint then
				return
			end

			Loop.FirstFarmWaypoint = WaypointIndex
			Loop.FirstFarmZone = ZoneIndex
		end

		------------------------------------------------------------------------
		--// Find the first paired Farm Zone in waypoint order.
		------------------------------------------------------------------------

		local function FindFirstPairedWaypoint(PlaceConfig, Paired)
			return Paired[1], Paired[1] and PlaceConfig.WAYPOINT_ZONES[Paired[1]]
		end

		------------------------------------------------------------------------
		--// Find a paired Farm Zone that currently has a target.
		--
		--// Used only after reaching the final waypoint.
		--// Route order is preserved.
		------------------------------------------------------------------------

		local function FindActiveFarmZone(PlaceConfig, Paired, now)
			for _, WaypointIndex in ipairs(Paired) do
				local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[WaypointIndex]

				if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
					return WaypointIndex, ZoneIndex
				end
			end

			return nil, nil
		end

		------------------------------------------------------------------------
		--// Start fighting a paired Farm Zone.
		------------------------------------------------------------------------

		local function EnterFarmZone(WaypointIndex, ZoneIndex)
			Loop.FarmWaypoint = WaypointIndex
			Loop.FarmZone = ZoneIndex
			Loop.Mode = "FIGHT"
			Loop.EmptySince = nil

			AICCombatUtils.S.ActiveZoneIndex = ZoneIndex
			AICCombat.S.ClosestTarget = nil
		end

		------------------------------------------------------------------------
		--// Stand still while waiting/fighting inside a Farm Zone.
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
		--// Walk to a neighbouring waypoint.
		------------------------------------------------------------------------

		local function StepTo(PlaceConfig, NextIndex, Humanoid, RootPart, now)
			local Target = PlaceConfig.WAYPOINTS[NextIndex]

			if not Target then
				return
			end

			local Offset = Target - RootPart.Position
			local Horizontal = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
			local Reach = tonumber(PlaceConfig.REACH_DISTANCE) or 5

			if Horizontal <= Reach
				and math.abs(Offset.Y) <= math.max(Reach, CONFIG.JUMP_HEIGHT + 2)
			then
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

		------------------------------------------------------------------------
		--// Reset Waypoint Loop.
		------------------------------------------------------------------------

		function AICFeature.ResetWaypointLoop()
			Loop.Index = 0
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
		--// Waypoint Loop
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
				if Loop.Index ~= 0 then
					AICFeature.ResetWaypointLoop()
				end

				return nil
			end

			------------------------------------------------------------------------
			--// ROUTE
			--
			--// Walk WP1 -> WP2 -> ... -> last WP.
			--// Every paired waypoint is checked before moving onward.
			------------------------------------------------------------------------

			if Loop.Mode == "ROUTE" then
				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				------------------------------------------------------------------------
				--// Start by actually reaching WP1.
				------------------------------------------------------------------------

				if Loop.Index == 0 then
					StepTo(PlaceConfig, 1, Humanoid, RootPart, now)
					return "move"
				end

				local CurrentWaypoint = Loop.Index
				local ZoneIndex = PlaceConfig.WAYPOINT_ZONES[CurrentWaypoint]

				------------------------------------------------------------------------
				--// This waypoint is paired with a Farm Zone.
				--// Check the Farm Zone BEFORE moving to the next waypoint.
				------------------------------------------------------------------------

				if ZoneIndex
					and ZoneIndex > 0
					and PlaceConfig.FARM_ZONES[ZoneIndex]
				then
					if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
						RememberFirstFarmZone(CurrentWaypoint, ZoneIndex)
						EnterFarmZone(CurrentWaypoint, ZoneIndex)

						return "fight"
					end
				end

				------------------------------------------------------------------------
				--// Reached the final waypoint.
				------------------------------------------------------------------------

				if CurrentWaypoint >= #PlaceConfig.WAYPOINTS then
					local ActiveWaypoint, ActiveZone = FindActiveFarmZone(PlaceConfig, Paired, now)

					------------------------------------------------------------------------
					--// If any paired zone currently has a mob, go there.
					------------------------------------------------------------------------

					if ActiveWaypoint then
						RememberFirstFarmZone(ActiveWaypoint, ActiveZone)
						Loop.Mode = "RETURN"
						Loop.FarmWaypoint = ActiveWaypoint
						Loop.FarmZone = ActiveZone
						Loop.EmptySince = nil

						return "move"
					end

					------------------------------------------------------------------------
					--// Every paired Farm Zone is empty.
					--
					--// Return to the first zone that was actually fought.
					--// If nothing has ever been fought, use the first paired zone.
					------------------------------------------------------------------------

					local ReturnWaypoint = Loop.FirstFarmWaypoint
					local ReturnZone = Loop.FirstFarmZone

					if not ReturnWaypoint then
						ReturnWaypoint, ReturnZone = FindFirstPairedWaypoint(PlaceConfig, Paired)
					end

					if ReturnWaypoint then
						Loop.Mode = "RETURN"
						Loop.FarmWaypoint = ReturnWaypoint
						Loop.FarmZone = ReturnZone
						Loop.EmptySince = nil

						return "move"
					end

					return "fight"
				end

				------------------------------------------------------------------------
				--// Continue forward one waypoint.
				------------------------------------------------------------------------

				StepTo(PlaceConfig, CurrentWaypoint + 1, Humanoid, RootPart, now)

				return "move"
			end

			------------------------------------------------------------------------
			--// RETURN
			--
			--// Walk backwards through the actual waypoints to the selected
			--// Farm Zone.
			------------------------------------------------------------------------

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

				------------------------------------------------------------------------
				--// Reached the Farm Zone's paired waypoint.
				------------------------------------------------------------------------

				if Loop.Index == TargetWaypoint then
					EnterFarmZone(TargetWaypoint, TargetZone)

					return "fight"
				end

				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				------------------------------------------------------------------------
				--// Move backwards one waypoint.
				------------------------------------------------------------------------

				local PreviousWaypoint = math.max(1, Loop.Index - 1)

				StepTo(PlaceConfig, PreviousWaypoint, Humanoid, RootPart, now)

				return "move"
			end

			------------------------------------------------------------------------
			--// FIGHT
			--
			--// Stay at this Farm Zone until it is genuinely clear.
			------------------------------------------------------------------------

			if Loop.Mode == "FIGHT" then
				local FarmWaypoint = Loop.FarmWaypoint
				local ZoneIndex = Loop.FarmZone

				if not FarmWaypoint
					or not ZoneIndex
					or not PlaceConfig.WAYPOINTS[FarmWaypoint]
					or not PlaceConfig.FARM_ZONES[ZoneIndex]
				then
					Loop.Mode = "ROUTE"
					Loop.FarmWaypoint = nil
					Loop.FarmZone = nil
					Loop.EmptySince = nil

					ResetZoneScan()

					AICCombatUtils.S.ActiveZoneIndex = nil
					AICCombat.S.ClosestTarget = nil

					return "move"
				end

				AICCombatUtils.S.ActiveZoneIndex = ZoneIndex

				------------------------------------------------------------------------
				--// Mob exists -> keep fighting.
				------------------------------------------------------------------------

				if ZoneHasTargets(PlaceConfig, ZoneIndex, now) then
					Loop.EmptySince = nil
					return "fight"
				end

				------------------------------------------------------------------------
				--// No mob.
				------------------------------------------------------------------------

				Loop.EmptySince = Loop.EmptySince or now

				------------------------------------------------------------------------
				--// If this is a return-to-zone with no mob, we still wait here.
				--// Once a mob appears, combat resumes normally.
				------------------------------------------------------------------------

				if Loop.Index == FarmWaypoint
					and not Loop.FirstFarmWaypoint
				then
					return "fight"
				end

				if now - Loop.EmptySince < ZONE_CLEAR_GRACE then
					return "fight"
				end

				------------------------------------------------------------------------
				--// Zone has genuinely cleared.
				------------------------------------------------------------------------

				Loop.Mode = "ROUTE"
				Loop.EmptySince = nil

				AICCombatUtils.S.ActiveZoneIndex = nil
				AICCombat.S.ClosestTarget = nil

				ResetZoneScan()

				------------------------------------------------------------------------
				--// If this Farm Zone was the first one we ever fought,
				--// FirstFarmWaypoint remains saved for the next full route.
				------------------------------------------------------------------------

				return "move"
			end

			------------------------------------------------------------------------
			--// Safety fallback.
			------------------------------------------------------------------------

			Loop.Mode = "ROUTE"
			Loop.FarmWaypoint = nil
			Loop.FarmZone = nil
			Loop.EmptySince = nil

			ResetZoneScan()

			AICCombatUtils.S.ActiveZoneIndex = nil
			AICCombat.S.ClosestTarget = nil

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
		--// Farm Zone Target UI
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
		--// Waypoint Loop UI
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
		--// Farm Zone Targets UI
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
