-- SaveConfig is the single list of everything a profile saves.
--
-- Adding a saved feature toggle is one line in Features; adding a saved
-- setting is one line in Settings. Runtime builds its feature state and
-- CONFIG defaults from here, ProfileManager saves, loads, exports and
-- resets from here, and Components refreshes every toggle from here.
return {
    Name = "SaveConfig",
    Dependencies = {},

    Start = function()
        local SaveConfig = {}

        --// Feature toggles, saved in the profile's FEATURES table.
        --//   Name    : key in Context.Feature and in the save file
        --//   Default : value before any profile is loaded
        --//   Key     : short key in exported profile text. Must never change
        --//             or be reused, or old exports load into the wrong toggle.
        --//             Toggles without one are saved but not exported.
        SaveConfig.Features = {
            { Name = "AutoFarm",          Default = true,  Key = "a" },
            { Name = "AutoBlock",         Default = true,  Key = "b" },
            { Name = "SafeCombat",        Default = true,  Key = "c" },
            { Name = "AutoFind",          Default = false, Key = "d" },
            { Name = "IgnoreFarmZone",    Default = false, Key = "e" },
            { Name = "AutoPatrol",        Default = false, Key = "f" },
            { Name = "ReturnToFarmZone",  Default = true,  Key = "g" },
            { Name = "AutoSkill",         Default = true,  Key = "h" },
            --// Shown as "Refill Booster": resets the character when a boost
            --// runs out so the game refills it. Owned by AutoRefill.
            { Name = "ResetOnBoostOut",   Default = true,  Key = "i" },
            { Name = "ResetStats",        Default = true,  Key = "j" },
            { Name = "DebugVisualizer",   Default = true,  Key = "k" },
            { Name = "PartySystem",       Default = false, Key = "l" },
            { Name = "WaypointLoop",      Default = false, Key = "m" },
            { Name = "SafeBoosterReset",  Default = false, Key = "n" },
            { Name = "DebugWaypoints",    Default = true },
            { Name = "DebugFarmZones",    Default = true },
            { Name = "DebugDeadzones",    Default = true },
            { Name = "DebugRadiusLabels", Default = true },
        }

        --// Normalizers turn whatever a save file holds into a valid value.
        --// They receive nil for a missing entry and must return the default.
        local function NormalizeUserIdList(Value)
            local Result = {}

            for _, Entry in ipairs(type(Value) == "table" and Value or {}) do
                local Text = tostring(Entry or ""):gsub("%s+", "")

                if Text:match("^%d+$") and not table.find(Result, Text) then
                    table.insert(Result, Text)
                end
            end

            return Result
        end

        --// { Name, UserId } of the party Leader, or {} when none is set.
        local function NormalizePartyLeader(Value)
            if type(Value) ~= "table" or type(Value.Name) ~= "string" or Value.Name == "" then
                return {}
            end

            return {
                Name = Value.Name,
                UserId = tonumber(Value.UserId),
            }
        end

        local function NormalizePinnedState(Value)
            if type(Value) ~= "table" then
                return {}
            end

            return {
                Items = type(Value.Items) == "table" and Value.Items or {},
                Floating = Value.Floating == true,
                X = tonumber(Value.X),
                Y = tonumber(Value.Y),
            }
        end

        --// Settings, saved in the profile's SETTINGS table.
        --//   Key       : key in CONFIG (or the place config) and in the save
        --//   Default   : value before any profile is loaded
        --//   Min / Max : clamp for numbers
        --//   Options   : allowed values for a choice; anything else -> Default
        --//   Normalize : custom cleanup for structured values
        --//   Scope     : "Place" lives on the place config instead of CONFIG,
        --//               and defaults to that place's preset
        --//   Global    : stored outside profiles; a profile copy only seeds it
        SaveConfig.Settings = {
            { Key = "REACH_DISTANCE", Scope = "Place", Default = 5 },
            { Key = "AUTOBLOCK", Scope = "Place", Default = false },

            --// Retreat below this share of health, and drink at or below the
            --// heal share.
            { Key = "RETREAT_HEALTH_PERCENT", Default = 40, Min = 30, Max = 80 },
            { Key = "AUTO_HEAL_HEALTH_PERCENT", Default = 65, Min = 30, Max = 80 },
            { Key = "SAFE_ENEMY_RANGE", Default = 4, Min = 0, Max = 30 },

            --// Tie break between mobs of equal priority.
            --// "Disabled" keeps the original nearest-first behaviour.
            { Key = "TARGET_HP_MODE", Default = "Disabled", Options = { "Disabled", "Highest HP", "Lowest HP" } },

            --// Below this share of its health a target is finished off instead
            --// of retreated from. An enemy skill still overrides it.
            { Key = "EXECUTE_CHARGE_HP_PERCENT", Default = 0, Min = 0, Max = 90 },

            --// UserIds allowed to share the server. Auto Block ignores these.
            { Key = "BLOCK_WHITELIST", Default = {}, Normalize = NormalizeUserIdList },

            --// Party System Leader, followed between servers with the game's
            --// "tp friend <Name>" chat command. Empty table = no Leader.
            { Key = "PARTY_LEADER", Default = {}, Normalize = NormalizePartyLeader },

            --// Pinned item panel: items, popped out or not, and position.
            --// Shared by every PlaceId, so it lives in its own file.
            { Key = "PINNED_STATE", Default = {}, Normalize = NormalizePinnedState, Global = true },
        }

        local FeatureByName = {}
        for _, Entry in ipairs(SaveConfig.Features) do
            FeatureByName[Entry.Name] = Entry
        end

        local SettingByKey = {}
        for _, Entry in ipairs(SaveConfig.Settings) do
            SettingByKey[Entry.Key] = Entry
        end

        local function DeepCopy(Value)
            if type(Value) ~= "table" then
                return Value
            end

            local Result = {}
            for Key, Item in pairs(Value) do
                Result[Key] = DeepCopy(Item)
            end
            return Result
        end

        function SaveConfig.GetFeature(Name)
            return FeatureByName[Name]
        end

        function SaveConfig.GetSetting(Key)
            return SettingByKey[Key]
        end

        --// Fallback is used instead of Default when given, which is how a
        --// place-scoped setting falls back to that place's preset.
        function SaveConfig.NormalizeSetting(Entry, Value, Fallback)
            local Default = DeepCopy(Fallback ~= nil and Fallback or Entry.Default)

            if Entry.Normalize then
                return Entry.Normalize(Value ~= nil and Value or Default)
            end

            if type(Entry.Default) == "number" then
                local Number = tonumber(Value)

                if Number == nil then
                    Number = tonumber(Default) or Entry.Default
                end

                if Entry.Min and Entry.Max then
                    Number = math.clamp(Number, Entry.Min, Entry.Max)
                end

                return Number
            end

            if type(Entry.Default) == "boolean" then
                if type(Value) == "boolean" then
                    return Value
                end

                return Default == true
            end

            if Entry.Options then
                return table.find(Entry.Options, Value) and Value or Entry.Default
            end

            if Value == nil then
                return Default
            end

            return DeepCopy(Value)
        end

        function SaveConfig.GetSettingDefault(Entry, Fallback)
            return SaveConfig.NormalizeSetting(Entry, nil, Fallback)
        end

        return SaveConfig
    end,
}
