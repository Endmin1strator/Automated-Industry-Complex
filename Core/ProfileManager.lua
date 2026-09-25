-- ProfileManager owns profile storage, serialization, import/export, and profile state.
return {
    Name = "ProfileManager",
    Dependencies = {"Runtime"},
    Start = function(Context)
        local Runtime = Context.Runtime
        local AICProfile = Context.AICProfile
        local AICConfig = Context.AICConfig
        local AICCombat = Context.AICCombat
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICDebug = Context.AICDebug
        local CONFIG = Context.CONFIG
        local Feature = Context.Feature
        local UIRef = Context.UIRef
        local PatrolState = Context.PatrolState
        local HttpService = Context.Services.HttpService
        local BasePlaceConfig = Runtime:GetBasePlaceConfig()
        local PlaceConfig = Runtime:GetPlaceConfig()

        local PROFILE_FOLDER = "AutoFarmProfiles"
        local PROFILE_FILE = PROFILE_FOLDER .. "/" .. tostring(game.PlaceId) .. ".json"
        --// Not keyed by PlaceId: pinned items follow the player between places.
        local PINNED_FILE = PROFILE_FOLDER .. "/PinnedItems.json"

        --// Short keys for feature toggles in exported/imported profile text.
        --// Must match AFV2 so saves move between the two builds.
        local COMPACT_FEATURE_KEYS = {
            AutoFarm = "a",
            AutoBlock = "b",
            SafeCombat = "c",
            AutoFind = "d",
            IgnoreFarmZone = "e",
            AutoPatrol = "f",
            ReturnToFarmZone = "g",
            AutoSkill = "h",
            ResetOnBoostOut = "i",
            ResetStats = "j",
            DebugVisualizer = "k",
        }

        AICProfile.S.ActiveProfileName = nil
        AICProfile.S.ProfileSaveQueued = false
        AICProfile.S.ProfileData = nil
        AICProfile.S.SelectedFarmZoneIndex = 1
        AICProfile.S.SelectedDeadzoneIndex = 1
        AICProfile.S.HasGlobalPinnedState = false
        AICProfile.S.PinnedSaveQueued = false

        function AICProfile.CanUseFileStorage()
            return type(readfile) == "function"
                and type(writefile) == "function"
                and type(isfile) == "function"
        end

        function AICProfile.EnsureProfileFolder()
            if type(makefolder) ~= "function" then
                return
            end

            pcall(function()
                makefolder(PROFILE_FOLDER)
            end)
        end

        function AICProfile.SerializeConfigValue(Value)
            if typeof(Value) == "Vector3" then
                return AICConfig.EncodeVector3(Value)
            end

            if type(Value) ~= "table" then
                return Value
            end

            local Result = {}
            for Key, Item in pairs(Value) do
                Result[Key] = AICProfile.SerializeConfigValue(Item)
            end
            return Result
        end

        function AICProfile.DeserializeConfigValue(Value)
            if type(Value) ~= "table" then
                return Value
            end

            if Value.X ~= nil and Value.Y ~= nil and Value.Z ~= nil
                and type(Value.X) == "number"
                and type(Value.Y) == "number"
                and type(Value.Z) == "number"
            then
                return AICConfig.DecodeVector3(Value)
            end

            local Result = {}
            for Key, Item in pairs(Value) do
                Result[Key] = AICProfile.DeserializeConfigValue(Item)
            end
            return Result
        end

        function AICProfile.MergeConfig(Base, Override)
            local Result = {}

            for Key, Value in pairs(Base or {}) do
                Result[Key] = AICProfile.DeserializeConfigValue(AICProfile.SerializeConfigValue(Value))
            end

            for Key, Value in pairs(Override or {}) do
                if type(Value) == "table" and type(Result[Key]) == "table" then
                    Result[Key] = AICProfile.MergeConfig(Result[Key], Value)
                else
                    Result[Key] = AICProfile.DeserializeConfigValue(Value)
                end
            end

            return Result
        end

        function AICProfile.BuildDefaultProfile()
            return {
                Name = "",
                PlaceId = game.PlaceId,
                --// Keep the complete place_config/default config inside the profile.
                PLACE_CONFIG = AICProfile.SerializeConfigValue(BasePlaceConfig),
                WAYPOINTS = AICConfig.CloneVectorList(BasePlaceConfig.WAYPOINTS),
                FARM_ZONES = AICConfig.CloneZoneList(BasePlaceConfig.FARM_ZONES),
                DEADZONES = AICConfig.CloneZoneList(BasePlaceConfig.DEADZONES),
                DEFAULT_TARGET_PRIORITY = table.clone(
                    BasePlaceConfig.DEFAULT_TARGET_PRIORITY
                        or CONFIG.TARGET_ENTITY_PRIORITY
                        or {}
                ),
                FEATURES = {},
                SETTINGS = {
                    REACH_DISTANCE = BasePlaceConfig.REACH_DISTANCE or 5,
                    AUTOBLOCK = BasePlaceConfig.AUTOBLOCK == true,
                },
            }
        end

        function AICProfile.ReadProfileStore()
            if not AICProfile.CanUseFileStorage() then
                return {
                    Profiles = {},
                    LastUsed = nil,
                }
            end

            AICProfile.EnsureProfileFolder()

            if not isfile(PROFILE_FILE) then
                return {
                    Profiles = {},
                    LastUsed = nil,
                }
            end

            local Success, Raw = pcall(readfile, PROFILE_FILE)

            if not Success or type(Raw) ~= "string" or Raw == "" then
                return {
                    Profiles = {},
                    LastUsed = nil,
                }
            end

            local DecodeSuccess, Data = pcall(function()
                return HttpService:JSONDecode(Raw)
            end)

            if not DecodeSuccess or type(Data) ~= "table" then
                return {
                    Profiles = {},
                    LastUsed = nil,
                }
            end

            Data.Profiles = type(Data.Profiles) == "table" and Data.Profiles or {}
            return Data
        end

        function AICProfile.WriteProfileStore()
            if not AICProfile.CanUseFileStorage() then
                return false
            end

            AICProfile.EnsureProfileFolder()

            local Success, Raw = pcall(function()
                return HttpService:JSONEncode(AICProfile.S.ProfileStore)
            end)

            if not Success then
                warn("AutoFarm profile encode failed:", Raw)
                return false
            end

            local WriteSuccess, WriteError = pcall(writefile, PROFILE_FILE, Raw)

            if not WriteSuccess then
                warn("AutoFarm profile save failed:", WriteError)
                return false
            end

            return true
        end

        function AICProfile.NormalizePinnedState(State)
            if type(State) ~= "table" then
                return {}
            end

            return {
                Items = type(State.Items) == "table" and State.Items or {},
                Floating = State.Floating == true,
                X = tonumber(State.X),
                Y = tonumber(State.Y),
            }
        end

        function AICProfile.ReadPinnedState()
            if not AICProfile.CanUseFileStorage() then
                return nil
            end

            local CheckSuccess, Exists = pcall(isfile, PINNED_FILE)

            if not CheckSuccess or not Exists then
                return nil
            end

            local Success, Decoded = pcall(function()
                return HttpService:JSONDecode(readfile(PINNED_FILE))
            end)

            if not Success or type(Decoded) ~= "table" then
                warn("AutoFarm pinned items read failed:", Decoded)
                return nil
            end

            return AICProfile.NormalizePinnedState(Decoded)
        end

        function AICProfile.WritePinnedState(State)
            if not AICProfile.CanUseFileStorage() then
                return false
            end

            AICProfile.EnsureProfileFolder()

            local Success, Raw = pcall(function()
                return HttpService:JSONEncode(AICProfile.NormalizePinnedState(State))
            end)

            if not Success then
                warn("AutoFarm pinned items encode failed:", Raw)
                return false
            end

            local WriteSuccess, WriteError = pcall(writefile, PINNED_FILE, Raw)

            if not WriteSuccess then
                warn("AutoFarm pinned items save failed:", WriteError)
                return false
            end

            AICProfile.S.HasGlobalPinnedState = true
            return true
        end

        --// Dragging the panel reports a change per move, so writes are
        --// debounced the same way profile saves are.
        function AICProfile.QueuePinnedSave()
            if AICProfile.S.PinnedSaveQueued then
                return
            end

            AICProfile.S.PinnedSaveQueued = true

            task.delay(CONFIG.PROFILE_SAVE_DEBOUNCE, function()
                AICProfile.S.PinnedSaveQueued = false
                AICProfile.WritePinnedState(CONFIG.PINNED_STATE)
            end)
        end

        function AICProfile.CaptureFeatureState()
            local Result = {
                AutoFarm = AICFeature.S.Enabled,
            }

            for Name, Data in pairs(Feature) do
                if type(Data) == "table" and type(Data.Enabled) == "boolean" then
                    Result[Name] = Data.Enabled
                end
            end

            return Result
        end

        function AICProfile.ApplyFeatureState(State)
            if type(State) ~= "table" then
                return
            end

            if type(State.AutoFarm) == "boolean" then
                AICFeature.S.Enabled = State.AutoFarm
            end

            for Name, Data in pairs(Feature) do
                if type(Data) == "table"
                    and type(State[Name]) == "boolean"
                then
                    Data.Enabled = State[Name]
                end
            end

            if type(State.AutoBlock) == "boolean" then
                AICFeature.S.BlockEnabled = State.AutoBlock

                local AutoBlock = Context.Modules.AutoBlock
                if AutoBlock and AutoBlock.SetEnabled then
                    AutoBlock:SetEnabled(State.AutoBlock, false)
                end
            end

            if type(State.SafeCombat) == "boolean" then
                AICCombat.S.SafeCombatPositionEnabled = State.SafeCombat
            end

            if type(State.AutoFind) == "boolean" then
                AICFeature.S.WaypointEnabled = not State.AutoFind
            end
        end

        function AICProfile.CaptureCurrentProfile(Name)
            local FarmConfig = AICConfig.NormalizePlaceConfig(Runtime:GetPlaceConfig())

            return {
                Name = Name or AICProfile.S.ActiveProfileName or "",
                PlaceId = game.PlaceId,
                PLACE_CONFIG = AICProfile.SerializeConfigValue(FarmConfig),
                WAYPOINTS = AICConfig.SerializeVectorList(FarmConfig.WAYPOINTS),
                FARM_ZONES = AICConfig.SerializeZoneList(FarmConfig.FARM_ZONES),
                DEADZONES = AICConfig.SerializeZoneList(FarmConfig.DEADZONES),
                DEFAULT_TARGET_PRIORITY = table.clone(CONFIG.TARGET_ENTITY_PRIORITY or {}),
                FEATURES = AICProfile.CaptureFeatureState(),
                SETTINGS = {
                    REACH_DISTANCE = tonumber(FarmConfig.REACH_DISTANCE) or 5,
                    AUTOBLOCK = AICFeature.S.BlockEnabled == true,
                    RETREAT_HEALTH_PERCENT = math.clamp(tonumber(CONFIG.RETREAT_HEALTH_PERCENT) or 40, 30, 80),
                    AUTO_HEAL_HEALTH_PERCENT = math.clamp(tonumber(CONFIG.AUTO_HEAL_HEALTH_PERCENT) or 65, 30, 80),
                    SAFE_ENEMY_RANGE = math.clamp(tonumber(CONFIG.SAFE_ENEMY_RANGE) or 4, 0, 30),
                    TARGET_HP_MODE = tostring(CONFIG.TARGET_HP_MODE or "Disabled"),
                    EXECUTE_CHARGE_HP_PERCENT = math.clamp(tonumber(CONFIG.EXECUTE_CHARGE_HP_PERCENT) or 0, 0, 90),
                    --// Read from the panel when it exists, so a drag or a pop out is
                    --// captured without the panel having to announce every change.
                    PINNED_STATE = UIRef.PinPanel
                        and UIRef.PinPanel:GetState()
                        or CONFIG.PINNED_STATE,
                    BLOCK_WHITELIST = table.clone(CONFIG.BLOCK_WHITELIST or {}),
                },
            }
        end

        function AICProfile.AreSerializedValuesEqual(A, B)
            local TypeA = type(A)
            local TypeB = type(B)

            if TypeA ~= TypeB then
                return false
            end

            if TypeA ~= "table" then
                return A == B
            end

            for Key, Value in pairs(A) do
                if not AICProfile.AreSerializedValuesEqual(Value, B[Key]) then
                    return false
                end
            end

            for Key in pairs(B) do
                if A[Key] == nil then
                    return false
                end
            end

            return true
        end

        function AICProfile.IsArrayTable(Value)
            if type(Value) ~= "table" then
                return false
            end

            for Key in pairs(Value) do
                if type(Key) ~= "number" then
                    return false
                end
            end

            return true
        end

        function AICProfile.BuildCompactConfig(Base, Current)
            local BaseData = AICProfile.SerializeConfigValue(Base or {})
            local CurrentData = AICProfile.SerializeConfigValue(Current or {})

            local function Diff(BaseValue, CurrentValue)
                if type(CurrentValue) ~= "table" then
                    if AICProfile.AreSerializedValuesEqual(BaseValue, CurrentValue) then
                        return nil
                    end
                    return CurrentValue
                end

                if AICProfile.IsArrayTable(CurrentValue) or AICProfile.IsArrayTable(BaseValue) then
                    if AICProfile.AreSerializedValuesEqual(BaseValue, CurrentValue) then
                        return nil
                    end
                    return CurrentValue
                end

                local Result = {}
                local Changed = false

                for Key, Value in pairs(CurrentValue) do
                    local Difference = Diff(BaseValue and BaseValue[Key], Value)
                    if Difference ~= nil then
                        Result[Key] = Difference
                        Changed = true
                    end
                end

                return Changed and Result or nil
            end

            return Diff(BaseData, CurrentData) or {}
        end

        function AICProfile.BuildCompactProfile(Name)
            local Full = AICProfile.CaptureCurrentProfile(Name)
            local BasePriority = BasePlaceConfig.DEFAULT_TARGET_PRIORITY
                or CONFIG.TARGET_ENTITY_PRIORITY
                or {}

            local Compact = {
                n = Full.Name,
                p = Full.PlaceId,
                c = AICProfile.BuildCompactConfig(BasePlaceConfig, Runtime:GetPlaceConfig()),
                s = Full.SETTINGS,
            }

            if not AICProfile.AreSerializedValuesEqual(Full.DEFAULT_TARGET_PRIORITY, BasePriority) then
                Compact.t = Full.DEFAULT_TARGET_PRIORITY
            end

            local Features = {}
            for NameKey, CompactKey in pairs(COMPACT_FEATURE_KEYS) do
                local Value = Full.FEATURES and Full.FEATURES[NameKey]
                if type(Value) == "boolean" then
                    Features[CompactKey] = Value
                end
            end

            if next(Features) then
                Compact.f = Features
            end

            return Compact
        end

        function AICProfile.ExpandCompactProfile(Data)
            if type(Data) ~= "table" then
                return nil, "IMPORT FAILED: Invalid JSON"
            end

            --// New compact format.
            if Data.n ~= nil or Data.c ~= nil or Data.f ~= nil or Data.t ~= nil then
                local Features = {}
                for NameKey, CompactKey in pairs(COMPACT_FEATURE_KEYS) do
                    if type(Data.f) == "table" and type(Data.f[CompactKey]) == "boolean" then
                        Features[NameKey] = Data.f[CompactKey]
                    end
                end

                local Config = AICProfile.DeserializeConfigValue(Data.c or {})
                local Settings = type(Data.s) == "table" and Data.s or {}
                if Config.REACH_DISTANCE ~= nil then
                    Settings.REACH_DISTANCE = tonumber(Config.REACH_DISTANCE)
                end
                if Config.AUTOBLOCK ~= nil then
                    Settings.AUTOBLOCK = Config.AUTOBLOCK == true
                end

                return {
                    Name = Data.n,
                    PlaceId = Data.p,
                    PLACE_CONFIG = Data.c or {},
                    DEFAULT_TARGET_PRIORITY = Data.t,
                    FEATURES = Features,
                    SETTINGS = Settings,
                }, nil
            end

            --// Backwards compatibility: allow importing the old full JSON format.
            return Data, nil
        end

        function AICProfile.ExportActiveProfile()
            if not AICProfile.S.ActiveProfileName then
                return false, "EXPORT FAILED: No active profile"
            end

            if type(setclipboard) ~= "function" then
                return false, "EXPORT FAILED: setclipboard is unavailable"
            end

            local ExportData = AICProfile.BuildCompactProfile(AICProfile.S.ActiveProfileName)
            local Success, Raw = pcall(function()
                return HttpService:JSONEncode(ExportData)
            end)

            if not Success then
                return false, "EXPORT FAILED: JSON encode error"
            end

            local ClipboardSuccess, ClipboardError = pcall(setclipboard, Raw)
            if not ClipboardSuccess then
                return false, "EXPORT FAILED: " .. tostring(ClipboardError)
            end

            return true, Raw
        end

        function AICProfile.ImportProfileFromText(Raw)
            if type(Raw) ~= "string" or Raw == "" then
                return false, "IMPORT FAILED: Import textbox is empty"
            end

            local DecodeSuccess, Data = pcall(function()
                return HttpService:JSONDecode(Raw)
            end)

            if not DecodeSuccess or type(Data) ~= "table" then
                return false, "IMPORT FAILED: Invalid JSON"
            end

            local ExpandedData, ExpandError = AICProfile.ExpandCompactProfile(Data)
            if not ExpandedData then
                return false, ExpandError or "IMPORT FAILED: Invalid profile data"
            end

            if tonumber(ExpandedData.PlaceId) ~= tonumber(game.PlaceId) then
                return false, "IMPORT FAILED: PlaceId mismatch"
            end

            local Name = tostring(ExpandedData.Name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if Name == "" then
                Name = "Imported Profile"
            end

            local BaseName = Name
            local Suffix = 2
            while AICProfile.S.ProfileStore.Profiles[Name] do
                Name = BaseName .. " " .. tostring(Suffix)
                Suffix += 1
            end

            ExpandedData.Name = Name
            ExpandedData.PlaceId = game.PlaceId
            AICProfile.S.ProfileStore.Profiles[Name] = ExpandedData
            AICProfile.S.ProfileStore.LastUsed = Name

            if not AICProfile.WriteProfileStore() then
                AICProfile.S.ProfileStore.Profiles[Name] = nil
                return false, "IMPORT FAILED: Could not save profile"
            end

            if not AICProfile.LoadProfile(Name) then
                return false, "IMPORT FAILED: Could not load profile"
            end

            return true, Name
        end

        function AICProfile.SaveActiveProfile()
            if not AICProfile.S.ActiveProfileName then
                return false
            end

            AICProfile.S.ProfileData = AICProfile.CaptureCurrentProfile(AICProfile.S.ActiveProfileName)
            AICProfile.S.ProfileStore.Profiles[AICProfile.S.ActiveProfileName] = AICProfile.S.ProfileData
            AICProfile.S.ProfileStore.LastUsed = AICProfile.S.ActiveProfileName

            return AICProfile.WriteProfileStore()
        end

        --// Sliders fire their callback on every step of a drag. Saving straight to
        --// disk from there means dozens of writefile calls for one gesture, so
        --// continuous controls queue a save instead of performing one.
        function AICProfile.QueueProfileSave()
            if not AICProfile.S.ActiveProfileName or AICProfile.S.ProfileSaveQueued then
                return
            end

            AICProfile.S.ProfileSaveQueued = true

            task.delay(CONFIG.PROFILE_SAVE_DEBOUNCE, function()
                AICProfile.S.ProfileSaveQueued = false
                AICProfile.SaveActiveProfile()
            end)
        end

        function AICProfile.ApplyProfileData(Data)
            if type(Data) ~= "table" then
                return false
            end

            local StoredPlaceConfig = AICProfile.DeserializeConfigValue(Data.PLACE_CONFIG)
            local FarmConfig = AICProfile.MergeConfig(BasePlaceConfig, StoredPlaceConfig)

            --// Backwards compatibility for profiles created before PLACE_CONFIG existed.
            FarmConfig.WAYPOINTS = AICConfig.CloneVectorList(Data.WAYPOINTS or FarmConfig.WAYPOINTS)
            FarmConfig.FARM_ZONES = AICConfig.CloneZoneList(Data.FARM_ZONES or FarmConfig.FARM_ZONES)
            FarmConfig.DEADZONES = AICConfig.CloneZoneList(Data.DEADZONES or FarmConfig.DEADZONES)
            FarmConfig.REACH_DISTANCE = tonumber(Data.SETTINGS and Data.SETTINGS.REACH_DISTANCE)
                or tonumber(FarmConfig.REACH_DISTANCE)
                or 5
            if Data.SETTINGS and type(Data.SETTINGS.AUTOBLOCK) == "boolean" then
                FarmConfig.AUTOBLOCK = Data.SETTINGS.AUTOBLOCK
            else
                FarmConfig.AUTOBLOCK = FarmConfig.AUTOBLOCK == true
            end

            CONFIG.RETREAT_HEALTH_PERCENT = math.clamp(
                type(Data.SETTINGS and Data.SETTINGS.RETREAT_HEALTH_PERCENT) == "number"
                    and Data.SETTINGS.RETREAT_HEALTH_PERCENT
                    or 40,
                30,
                80
            )

            CONFIG.AUTO_HEAL_HEALTH_PERCENT = math.clamp(
                type(Data.SETTINGS and Data.SETTINGS.AUTO_HEAL_HEALTH_PERCENT) == "number"
                    and Data.SETTINGS.AUTO_HEAL_HEALTH_PERCENT
                    or 65,
                30,
                80
            )

            CONFIG.SAFE_ENEMY_RANGE = math.clamp(
                type(Data.SETTINGS and Data.SETTINGS.SAFE_ENEMY_RANGE) == "number"
                    and Data.SETTINGS.SAFE_ENEMY_RANGE
                    or 4,
                0,
                30
            )

            --// Anything unrecognised falls back to Disabled rather than leaving the
            --// selector showing a mode the code does not implement.
            local StoredMode = Data.SETTINGS and Data.SETTINGS.TARGET_HP_MODE

            if StoredMode == "Highest HP" or StoredMode == "Lowest HP" then
                CONFIG.TARGET_HP_MODE = StoredMode
            else
                CONFIG.TARGET_HP_MODE = "Disabled"
            end

            CONFIG.EXECUTE_CHARGE_HP_PERCENT = math.clamp(
                type(Data.SETTINGS and Data.SETTINGS.EXECUTE_CHARGE_HP_PERCENT) == "number"
                    and Data.SETTINGS.EXECUTE_CHARGE_HP_PERCENT
                    or 0,
                0,
                90
            )

            --// Pinned items are shared across every PlaceId and live in their
            --// own file. A profile's copy is only used to seed that file once,
            --// for saves made before pins were global.
            local StoredPinned = Data.SETTINGS and Data.SETTINGS.PINNED_STATE

            if not AICProfile.S.HasGlobalPinnedState and type(StoredPinned) == "table" then
                CONFIG.PINNED_STATE = AICProfile.NormalizePinnedState(StoredPinned)
                AICProfile.WritePinnedState(CONFIG.PINNED_STATE)
            end

            local StoredWhitelist = Data.SETTINGS and Data.SETTINGS.BLOCK_WHITELIST
            local Whitelist = {}

            if type(StoredWhitelist) == "table" then
                for _, Entry in ipairs(StoredWhitelist) do
                    local Id = AICFeature.NormalizeUserId(Entry)

                    if Id then
                        table.insert(Whitelist, Id)
                    end
                end
            end

            CONFIG.BLOCK_WHITELIST = Whitelist

                PlaceConfig = AICConfig.NormalizePlaceConfig(FarmConfig)
                Runtime:SetPlaceConfig(PlaceConfig)

            CONFIG.TARGET_ENTITY_PRIORITY = table.clone(
                Data.DEFAULT_TARGET_PRIORITY
                    or BasePlaceConfig.DEFAULT_TARGET_PRIORITY
                    or {}
            )

            Feature.AutoBlock.Enabled = PlaceConfig.AUTOBLOCK
            AICFeature.S.BlockEnabled = PlaceConfig.AUTOBLOCK

            local AutoBlock = Context.Modules.AutoBlock
            if AutoBlock and AutoBlock.SetEnabled then
                AutoBlock:SetEnabled(PlaceConfig.AUTOBLOCK, false)
            end

            AICProfile.ApplyFeatureState(Data.FEATURES)

            local AutoBlock = Context.Modules.AutoBlock
            if AutoBlock and AutoBlock.RefreshUI then
                AutoBlock:RefreshUI()
            end

            CONFIG.CURRENT_WAYPOINT_TARGET = 1
            AICCombat.ResetTargetReposition()
            AICFeature.S.DeadzoneEscapePosition = nil
            PatrolState.PatrolPosition = nil
            AICFeature.S.FarmReturnPosition = nil
            AICProfile.S.SelectedFarmZoneIndex = 1
            AICProfile.S.SelectedDeadzoneIndex = 1
            PatrolState.LastPatrolCalculateTime = 0
            AICFeature.S.LastFarmReturnCalculateTime = 0

            return true
        end

        function AICProfile.LoadProfile(Name)
            local Data = AICProfile.S.ProfileStore.Profiles[Name]

            if type(Data) ~= "table" then
                return false
            end

            if AICProfile.ApplyProfileData(Data) then
                AICProfile.S.ActiveProfileName = Name
                AICProfile.S.ProfileData = Data
                AICProfile.S.ProfileStore.LastUsed = Name
                AICProfile.WriteProfileStore()
                return true
            end

            return false
        end

        function AICProfile.DeleteProfile(Name)
            if not Name or not AICProfile.S.ProfileStore.Profiles[Name] then
                return false
            end

            AICProfile.S.ProfileStore.Profiles[Name] = nil

            if AICProfile.S.ProfileStore.LastUsed == Name then
                AICProfile.S.ProfileStore.LastUsed = nil
            end

            if AICProfile.S.ActiveProfileName == Name then
                AICProfile.S.ActiveProfileName = nil
                AICProfile.S.ProfileData = nil
                PlaceConfig = AICConfig.NormalizePlaceConfig(AICConfig.IsValidPlace(game.PlaceId) or {})
                Runtime:SetPlaceConfig(PlaceConfig)
                CONFIG.TARGET_ENTITY_PRIORITY = table.clone(
                    BasePlaceConfig.DEFAULT_TARGET_PRIORITY
                        or {}
                )
                Feature.AutoBlock.Enabled = BasePlaceConfig.AUTOBLOCK == true
                AICFeature.S.BlockEnabled = BasePlaceConfig.AUTOBLOCK == true
                CONFIG.CURRENT_WAYPOINT_TARGET = 1
            end

            AICProfile.WriteProfileStore()
            return true
        end

        function AICProfile.CreateProfile(Name)
            Name = tostring(Name or ""):gsub("^%s+", ""):gsub("%s+$", "")

            if Name == "" or #Name > 32 then
                return false, "Invalid profile name"
            end

            if Name:find("[/\\:%*%?\"<>|]") then
                return false, "Invalid profile name"
            end

            if AICProfile.S.ProfileStore.Profiles[Name] then
                return false, "Profile already exists"
            end

            AICProfile.S.ActiveProfileName = Name
            AICProfile.S.ProfileData = AICProfile.BuildDefaultProfile()
            AICProfile.S.ProfileData.Name = Name

            AICProfile.ApplyProfileData(AICProfile.S.ProfileData)

            AICProfile.S.ProfileStore.Profiles[Name] = AICProfile.CaptureCurrentProfile(Name)
            AICProfile.S.ProfileStore.LastUsed = Name
            AICProfile.WriteProfileStore()

            return true
        end

        function AICProfile.GetProfileNames()
            local Names = {}

            for Name in pairs(AICProfile.S.ProfileStore.Profiles) do
                table.insert(Names, Name)
            end

            table.sort(Names, function(A, B)
                return string.lower(A) < string.lower(B)
            end)

            return Names
        end

        function AICProfile.ApplyDefaultPlaceConfig()
            AICProfile.S.ActiveProfileName = nil
            AICProfile.S.ProfileData = nil

            --// Never create a fake Vector3.zero farm zone. If the place config
            --// has no zones, NormalizePlaceConfig keeps the lists empty.
                PlaceConfig = AICConfig.NormalizePlaceConfig(AICProfile.DeserializeConfigValue(AICProfile.SerializeConfigValue(BasePlaceConfig)))
                Runtime:SetPlaceConfig(PlaceConfig)

            CONFIG.TARGET_ENTITY_PRIORITY = table.clone(
                BasePlaceConfig.DEFAULT_TARGET_PRIORITY
                    or {}
            )

            Feature.AutoBlock.Enabled = BasePlaceConfig.AUTOBLOCK == true
            AICFeature.S.BlockEnabled = BasePlaceConfig.AUTOBLOCK == true

            local AutoBlock = Context.Modules.AutoBlock
            if AutoBlock and AutoBlock.SetEnabled then
                AutoBlock:SetEnabled(BasePlaceConfig.AUTOBLOCK == true, false)
            end
            CONFIG.CURRENT_WAYPOINT_TARGET = 1
            CONFIG.RETREAT_HEALTH_PERCENT = 40
            CONFIG.AUTO_HEAL_HEALTH_PERCENT = 65
            CONFIG.SAFE_ENEMY_RANGE = 4
            CONFIG.TARGET_HP_MODE = "Disabled"
            CONFIG.BLOCK_WHITELIST = {}
            CONFIG.EXECUTE_CHARGE_HP_PERCENT = 0
            --// PINNED_STATE is global, not part of the place defaults.

            AICCombat.ResetTargetReposition()
            AICFeature.S.DeadzoneEscapePosition = nil
            PatrolState.PatrolPosition = nil
            AICFeature.S.FarmReturnPosition = nil
            PatrolState.LastPatrolCalculateTime = 0
            AICFeature.S.LastFarmReturnCalculateTime = 0

            return true
        end

        AICProfile.S.ProfileStore = AICProfile.ReadProfileStore()

        Context.PROFILE_FOLDER = PROFILE_FOLDER
        Context.PROFILE_FILE = PROFILE_FILE
        return AICProfile
    end,
}
