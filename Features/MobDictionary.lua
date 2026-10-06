-- MobDictionary reads the game's mob dictionary (ReplicatedStorage.BuildAssets
-- invoked with "MobDict": every model in ServerStorage Mobs and Bosses, with
-- its Value children, its Configuration values and its Humanoid's MaxHealth
-- and WalkSpeed) and turns it into one entry per mob for the Mob Dictionary
-- window (MobBrowser):
--
--   Entry = {
--       Name, Kind ("Mob" / "Boss"),
--       Stats = { { Key, Label, Value, Group, Numeric } ... },
--       Status = { Name, Props = { { Label, Value } ... } } or nil,
--   }
--
-- Numeric stats are also ranked against the other mobs of the same kind
-- (GetScale), so the window can show each one as a share of the strongest's,
-- and GetThreat rates a mob by where its health and damage rank among all.
return {
    Name = "MobDictionary",
    Dependencies = {"Runtime"},

    Start = function(Context)
        local Replicated = Context.Services.Replicated

        local REMOTE_NAME = "BuildAssets"
        local REMOTE_ARGUMENT = "MobDict"
        --// The server's folder names, and what each is shown as.
        local KIND_BY_FOLDER = { Mobs = "Mob", Bosses = "Boss" }
        --// Values already shown elsewhere (the mob's name).
        local HIDDEN_KEYS = { Entity = true }
        --// A stat whose name holds one of these words is grouped under it.
        --// Checked in order; the first match wins.
        local GROUP_WORDS = {
            { Group = "Rewards", Words = { "xp", "exp", "gold", "coin", "money", "cash", "drop", "loot", "reward", "chance" } },
            { Group = "Combat", Words = { "damage", "dmg", "attack", "atk", "range", "aggro", "cooldown", "crit", "defense", "armor", "hit", "power", "strength" } },
        }
        --// Stats that make a mob dangerous, for the threat meter.
        local THREAT_WORDS = { "damage", "dmg", "attack", "atk", "power", "strength" }

        local Dictionary = {
            Name = "MobDictionary",
            KIND_BY_FOLDER = KIND_BY_FOLDER,
            S = {
                Entries = {},
                ByName = {},
                --// Stat key -> { Max, Sorted (descending values) }, over
                --// every mob; KindScales[Kind] is the same per kind.
                Scales = {},
                KindScales = {},
                Loading = false,
                Loaded = false,
                Error = nil,
                --// Called after every load, whether it worked or not.
                OnLoaded = nil,
            },
        }

        local S = Dictionary.S

        local function HasWord(Text, Words)
            local Lower = string.lower(Text)

            for _, Word in ipairs(Words) do
                if string.find(Lower, Word, 1, true) then
                    return true
                end
            end

            return false
        end

        local function GetGroup(Name)
            for _, Rule in ipairs(GROUP_WORDS) do
                if HasWord(Name, Rule.Words) then
                    return Rule.Group
                end
            end

            return "Other"
        end

        function Dictionary.IsThreatStat(Stat)
            return Stat.Key == "Humanoid.MaxHealth" or HasWord(Stat.Label, THREAT_WORDS)
        end

        --// "AttackRange" -> "ATTACK RANGE".
        function Dictionary.Prettify(Name)
            local Spaced = string.gsub(Name, "(%l)(%u)", "%1 %2")
            Spaced = string.gsub(Spaced, "_", " ")
            return string.upper(Spaced)
        end

        --// The server sends each value as { Value = x }; anything else is
        --// passed through as it is.
        local function Unwrap(Raw)
            if type(Raw) == "table" then
                return Raw.Value
            end

            return Raw
        end

        local function AddStat(Stats, Key, Name, Value, Group)
            if Value == nil or HIDDEN_KEYS[Name] then
                return
            end

            table.insert(Stats, {
                Key = Key,
                Label = Dictionary.Prettify(Name),
                Value = Value,
                Group = Group or GetGroup(Name),
                Numeric = type(Value) == "number",
            })
        end

        local function ReadStatus(Raw)
            if type(Raw) ~= "table" then
                return nil
            end

            local Status = { Name = tostring(Raw.Value or "Unknown"), Props = {} }

            for Name, Child in pairs(Raw) do
                if Name ~= "Value" then
                    table.insert(Status.Props, { Label = Dictionary.Prettify(Name), Value = Unwrap(Child) })
                end
            end

            table.sort(Status.Props, function(A, B)
                return A.Label < B.Label
            end)

            return Status
        end

        local function ReadEntry(Name, Raw)
            local Entry = {
                Name = Name,
                Kind = KIND_BY_FOLDER[Raw.Value] or tostring(Raw.Value or "Mob"),
                Stats = {},
                Status = nil,
            }

            local Humanoid = Raw.Humanoid

            if type(Humanoid) == "table" then
                AddStat(Entry.Stats, "Humanoid.MaxHealth", "Health", tonumber(Humanoid.MaxHealth), "Core")
                AddStat(Entry.Stats, "Humanoid.WalkSpeed", "WalkSpeed", tonumber(Humanoid.WalkSpeed), "Core")
            end

            for Key, Child in pairs(Raw) do
                if Key == "Config" and type(Child) == "table" then
                    for ConfigKey, ConfigChild in pairs(Child) do
                        if ConfigKey == "StatusEffect" then
                            Entry.Status = ReadStatus(ConfigChild)
                        else
                            AddStat(Entry.Stats, "Config." .. ConfigKey, ConfigKey, Unwrap(ConfigChild))
                        end
                    end
                elseif Key ~= "Value" and Key ~= "Humanoid" then
                    AddStat(Entry.Stats, "Value." .. Key, Key, Unwrap(Child))
                end
            end

            --// Health and speed first, then by name.
            table.sort(Entry.Stats, function(A, B)
                if (A.Group == "Core") ~= (B.Group == "Core") then
                    return A.Group == "Core"
                end

                return A.Label < B.Label
            end)

            return Entry
        end

        function Dictionary.GetStat(Entry, Key)
            for _, Stat in ipairs(Entry.Stats) do
                if Stat.Key == Key then
                    return Stat.Value
                end
            end

            return nil
        end

        local function CollectScales(Entries)
            local Values = {}

            for _, Entry in ipairs(Entries) do
                for _, Stat in ipairs(Entry.Stats) do
                    if Stat.Numeric then
                        Values[Stat.Key] = Values[Stat.Key] or {}
                        table.insert(Values[Stat.Key], Stat.Value)
                    end
                end
            end

            local Scales = {}

            for Key, List in pairs(Values) do
                table.sort(List, function(A, B)
                    return A > B
                end)

                Scales[Key] = { Max = List[1], Sorted = List }
            end

            return Scales
        end

        --// One scale over every mob, and one per kind, so a mob's bars are
        --// measured against other mobs and a boss's against other bosses.
        local function BuildScales()
            local ByKind = {}

            for _, Entry in ipairs(S.Entries) do
                ByKind[Entry.Kind] = ByKind[Entry.Kind] or {}
                table.insert(ByKind[Entry.Kind], Entry)
            end

            S.Scales = CollectScales(S.Entries)
            S.KindScales = {}

            for Kind, Entries in pairs(ByKind) do
                S.KindScales[Kind] = CollectScales(Entries)
            end
        end

        local function FindScale(Stat, Kind)
            if not Stat.Numeric then
                return nil
            end

            if Kind then
                local Scales = S.KindScales[Kind]
                return Scales and Scales[Stat.Key]
            end

            return S.Scales[Stat.Key]
        end

        --// Fraction of the strongest value (0..1) and the rank (1 = highest)
        --// among the mobs of Kind that have this stat, or among every mob
        --// when Kind is nil.
        function Dictionary.GetScale(Stat, Kind)
            local Scale = FindScale(Stat, Kind)

            if not Scale then
                return 0, nil, 0
            end

            local Fraction = Scale.Max > 0 and math.clamp(Stat.Value / Scale.Max, 0, 1) or 0
            local Rank = table.find(Scale.Sorted, Stat.Value)
            return Fraction, Rank, #Scale.Sorted
        end

        --// 0..1: the mean of where each threat stat ranks among every mob
        --// (1 = the highest of all). Ranks rather than values, so one huge
        --// boss does not make every other mob look harmless.
        function Dictionary.GetThreat(Entry)
            local Total, Count = 0, 0

            for _, Stat in ipairs(Entry.Stats) do
                if Stat.Numeric and Dictionary.IsThreatStat(Stat) then
                    local _, Rank, Size = Dictionary.GetScale(Stat)

                    if Rank then
                        Total += Size > 1 and (Size - Rank) / (Size - 1) or 1
                        Count += 1
                    end
                end
            end

            return Count > 0 and Total / Count or 0
        end

        local function Apply(Raw)
            local Entries, ByName = {}, {}

            for Name, Data in pairs(Raw) do
                if type(Name) == "string" and type(Data) == "table" then
                    local Entry = ReadEntry(Name, Data)
                    table.insert(Entries, Entry)
                    ByName[Name] = Entry
                end
            end

            table.sort(Entries, function(A, B)
                local HealthA = Dictionary.GetStat(A, "Humanoid.MaxHealth") or 0
                local HealthB = Dictionary.GetStat(B, "Humanoid.MaxHealth") or 0

                if HealthA ~= HealthB then
                    return HealthA < HealthB
                end

                return A.Name < B.Name
            end)

            S.Entries = Entries
            S.ByName = ByName
            BuildScales()
        end

        local function Finish(ErrorMessage)
            S.Loading = false
            S.Error = ErrorMessage

            if S.OnLoaded then
                S.OnLoaded()
            end
        end

        --// Asks the server for the dictionary in the background. The server
        --// builds it once and keeps it, so asking again is cheap.
        function Dictionary:Load()
            if S.Loading then
                return
            end

            local Remote = Replicated:FindFirstChild(REMOTE_NAME)

            if not Remote or not Remote:IsA("RemoteFunction") then
                Finish("Mob dictionary is not available in this place")
                return
            end

            S.Loading = true
            S.Error = nil

            task.spawn(function()
                local Ok, Result = pcall(Remote.InvokeServer, Remote, REMOTE_ARGUMENT)

                if not Context.Lifetime.Alive then
                    return
                end

                if not Ok then
                    Finish("Could not read the mob dictionary: " .. tostring(Result))
                    return
                end

                if type(Result) ~= "table" then
                    Finish("The server sent no mob dictionary")
                    return
                end

                Apply(Result)
                S.Loaded = true
                Finish(nil)
            end)
        end

        function Dictionary:GetAll()
            return S.Entries
        end

        function Dictionary:Get(Name)
            return S.ByName[Name]
        end

        --// Mobs alive in workspace.Mobs, counted by model name and by their
        --// Config.Entity, plus the Entity each name is targeted by.
        function Dictionary:CountLive()
            local Counts, Entities = {}, {}
            local Folder = workspace:FindFirstChild("Mobs")

            for _, Mob in (Folder and Folder:GetChildren() or {}) do
                if not Mob:IsA("Model") then
                    continue
                end

                local Config = Mob:FindFirstChild("Config")
                local Entity = Config and Config:FindFirstChild("Entity")
                local EntityName = Entity and Entity:IsA("StringValue") and Entity.Value ~= "" and Entity.Value or nil

                Counts[Mob.Name] = (Counts[Mob.Name] or 0) + 1

                if EntityName then
                    Entities[Mob.Name] = EntityName

                    if EntityName ~= Mob.Name then
                        Counts[EntityName] = (Counts[EntityName] or 0) + 1
                    end
                end
            end

            return Counts, Entities
        end

        return Dictionary
    end,
}
