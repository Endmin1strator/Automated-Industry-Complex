-- PartySystem follows a Leader between servers.
--
-- A Leader is picked from the players in the server. Whenever someone who is
-- not whitelisted (and is not the Leader) is in the server, or the Leader is
-- not, the character is reset and held still, and the game's
-- "Tp friend <Leader>" chat command is sent. A try succeeds once the Leader
-- is in the same server; after PARTY_TP_ATTEMPTS failed tries it gives up for
-- PARTY_FAILED_COOLDOWN seconds, during which Auto Block handles intruders.
return {
    Name = "PartySystem",
    IsFeature = true,
    Dependencies = {"Runtime", "ProfileManager", "Components", "AutoBlock"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local Services = Context.Services
        local Players = Services.Players
        local Replicated = Services.Replicated
        local Player = Context.Player
        local CONFIG = Context.CONFIG
        local FeatureState = Context.Feature
        local AICFeature = Context.AICFeature
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI
        local UIRef = Context.UIRef
        local NotifyAction = Context.NotifyAction

        local Feature = {
            Name = "PartySystem",
            IsFeature = true,
        }

        AICFeature.S.Party = {
            --// True while the farm loop must stand still.
            Holding = false,
            --// True while a reset / Tp sequence is running.
            Busy = false,
            CooldownUntil = 0,
            LastCheck = 0,
        }

        local State = AICFeature.S.Party

        local function GetLeader()
            local Leader = CONFIG.PARTY_LEADER

            if type(Leader) == "table" and type(Leader.Name) == "string" and Leader.Name ~= "" then
                return Leader
            end

            return nil
        end

        local function IsActive()
            return FeatureState.PartySystem.Enabled == true and GetLeader() ~= nil
        end

        local function IsLeaderPlayer(OtherPlayer)
            local Leader = GetLeader()

            if not Leader or not OtherPlayer then
                return false
            end

            if Leader.UserId then
                return OtherPlayer.UserId == Leader.UserId
            end

            return OtherPlayer.Name == Leader.Name
        end

        local function IsLeaderInServer()
            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                if IsLeaderPlayer(OtherPlayer) then
                    return true
                end
            end

            return false
        end

        --// Anyone other than us and the Leader who is not on the whitelist.
        local function GetIntruder()
            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                if OtherPlayer ~= Player
                    and not IsLeaderPlayer(OtherPlayer)
                    and not (AICFeature.IsWhitelisted and AICFeature.IsWhitelisted(OtherPlayer.UserId))
                then
                    return OtherPlayer
                end
            end

            return nil
        end

        local function SetStatus(Text)
            State.Status = Text

            if UIRef.PartyStatusLabel then
                UIRef.PartyStatusLabel.Text = "STATUS:  " .. tostring(Text)
            end
        end

        --// Sends a message on whichever chat system the game uses.
        local function SendChat(Message)
            local TextChatService = game:GetService("TextChatService")

            local Sent = pcall(function()
                local Channels = TextChatService:FindFirstChild("TextChannels")
                local General = Channels and Channels:FindFirstChild("RBXGeneral")

                assert(General, "no RBXGeneral channel")
                General:SendAsync(Message)
            end)

            if Sent then
                return true
            end

            return pcall(function()
                local Events = Replicated:FindFirstChild("DefaultChatSystemChatEvents")
                local Say = Events and Events:FindFirstChild("SayMessageRequest")

                assert(Say, "no legacy chat")
                Say:FireServer(Message, "All")
            end)
        end

        local function ResetCharacter()
            local _, Humanoid = Runtime:GetCharacter()

            if not Humanoid or Humanoid.Health <= 0 then
                return
            end

            local Respawned = false
            local Connection = Player.CharacterAdded:Connect(function()
                Respawned = true
            end)

            Humanoid.Health = 0

            local Deadline = os.clock() + (tonumber(CONFIG.PARTY_RESPAWN_TIMEOUT) or 10)

            repeat
                task.wait(0.25)
            until Respawned or os.clock() > Deadline

            Connection:Disconnect()

            --// Give the new character a moment to finish loading.
            task.wait(1)
        end

        local function Release(StatusText)
            State.Holding = false
            State.Busy = false
            SetStatus(StatusText)
        end

        local function RunFollow()
            State.Holding = true
            SetStatus("RESETTING")
            ResetCharacter()

            --// Someone joined but the Leader is still here: stand still until
            --// the Leader moves on, then follow.
            while IsLeaderInServer() do
                if not IsActive() then
                    Release("IDLE")
                    return
                end

                if not GetIntruder() then
                    Release("WITH LEADER")
                    return
                end

                SetStatus("WAITING FOR LEADER TO MOVE")
                task.wait(1)
            end

            local Leader = GetLeader()
            local Attempts = math.max(1, tonumber(CONFIG.PARTY_TP_ATTEMPTS) or 3)
            local Timeout = tonumber(CONFIG.PARTY_TP_ATTEMPT_TIMEOUT) or 15

            for Attempt = 1, Attempts do
                if not IsActive() then
                    Release("IDLE")
                    return
                end

                SetStatus(string.format("TP FRIEND %s  (%d/%d)", Leader.Name, Attempt, Attempts))

                if not SendChat("Tp friend " .. Leader.Name) then
                    NotifyAction("Party", "Could not send chat message")
                end

                --// A successful Tp moves us to the Leader's server and this
                --// script ends there; the Leader showing up here also counts.
                local Deadline = os.clock() + Timeout

                repeat
                    task.wait(1)
                until IsLeaderInServer() or os.clock() > Deadline or not IsActive()

                if IsLeaderInServer() then
                    Release("WITH LEADER")
                    return
                end
            end

            State.CooldownUntil = os.clock() + (tonumber(CONFIG.PARTY_FAILED_COOLDOWN) or 60)
            NotifyAction("Party", "Tp to " .. Leader.Name .. " failed after " .. Attempts .. " tries")
            Release("TP FAILED, RETRY LATER")
        end

        --// Auto Block stays out of the way while a Leader is being followed,
        --// except during the cooldown after a failed Tp.
        function AICFeature.PartyHandlesIntruders()
            return IsActive() and os.clock() >= State.CooldownUntil
        end

        function AICFeature.IsPartyHolding()
            return State.Holding == true
        end

        function Feature:Update()
            local now = os.clock()

            if now - State.LastCheck < (tonumber(CONFIG.PARTY_CHECK_INTERVAL) or 1) then
                return
            end

            State.LastCheck = now

            if State.Busy then
                return
            end

            if not IsActive() then
                if State.Holding then
                    Release("IDLE")
                end

                return
            end

            if IsLeaderInServer() and not GetIntruder() then
                if State.Status ~= "WITH LEADER" then
                    SetStatus("WITH LEADER")
                end

                return
            end

            if now < State.CooldownUntil then
                return
            end

            State.Busy = true
            task.spawn(RunFollow)
        end

        ------------------------------------------------------------------------
        --// UI (Party tab)
        ------------------------------------------------------------------------
        local Section = UIRef.PartySection
        local LeaderOptions = {}

        local function RefreshLeaderLabel()
            local Leader = GetLeader()

            if UIRef.PartyLeaderLabel then
                UIRef.PartyLeaderLabel.Text = "LEADER:  " .. (Leader and Leader.Name or "NONE")
            end
        end

        local function SetLeader(OtherPlayer)
            if OtherPlayer then
                CONFIG.PARTY_LEADER = { Name = OtherPlayer.Name, UserId = OtherPlayer.UserId }
                NotifyAction("Party", "Leader set to " .. OtherPlayer.Name)
            else
                CONFIG.PARTY_LEADER = {}
                NotifyAction("Party", "Leader cleared")
            end

            State.CooldownUntil = 0
            RefreshLeaderLabel()
            AICProfile.SaveActiveProfile()
        end

        function AICUI.RefreshPartyLeaderDropdown()
            table.clear(LeaderOptions)

            local Options = {}

            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                if OtherPlayer ~= Player then
                    local Label = string.format("%s (@%s)", OtherPlayer.DisplayName, OtherPlayer.Name)
                    LeaderOptions[Label] = OtherPlayer
                    table.insert(Options, Label)
                end
            end

            table.sort(Options, function(A, B)
                return string.lower(A) < string.lower(B)
            end)

            if #Options == 0 then
                Options = { "No other players" }
            end

            if UIRef.PartyLeaderDropdown then
                if UIRef.PartyLeaderDropdown.Popup then
                    UIRef.PartyLeaderDropdown.Popup:Destroy()
                end

                if UIRef.PartyLeaderDropdown.Frame then
                    UIRef.PartyLeaderDropdown.Frame:Destroy()
                end
            end

            UIRef.PartyLeaderDropdown = Section:AddDropdown("Set Leader", Options, function(Value)
                local OtherPlayer = LeaderOptions[Value]

                --// Only someone still in this server can be picked.
                if OtherPlayer and OtherPlayer.Parent == Players then
                    SetLeader(OtherPlayer)
                end
            end)
        end

        --// Called after a profile loads, since the Leader is saved per profile.
        function AICUI.RefreshPartyUI()
            RefreshLeaderLabel()
        end

        if Section then
            FeatureState.PartySystem.Button = Section:AddToggle(
                "Party System",
                FeatureState.PartySystem.Enabled,
                function(Value)
                    FeatureState.PartySystem.Enabled = Value
                    State.CooldownUntil = 0
                    AICProfile.SaveActiveProfile()
                end
            )

            UIRef.PartyLeaderLabel = Section:AddLabel("LEADER:  NONE")
            UIRef.PartyStatusLabel = Section:AddLabel("STATUS:  IDLE")

            Section:AddButton("Clear Leader", function()
                SetLeader(nil)
            end)

            Section:AddButton("Refresh Player List", function()
                AICUI.RefreshPartyLeaderDropdown()
            end)

            AICUI.RefreshPartyLeaderDropdown()
            RefreshLeaderLabel()

            Players.PlayerAdded:Connect(function()
                AICUI.RefreshPartyLeaderDropdown()
            end)

            Players.PlayerRemoving:Connect(function()
                task.defer(AICUI.RefreshPartyLeaderDropdown)
            end)
        end

        return Feature
    end,
}
