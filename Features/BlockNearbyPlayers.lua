-- Distance-based safety is independent of Auto Block and Auto Farm.
return {
    Name = "BlockNearbyPlayers",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "ProfileManager", "Components", "AutoBlock", "AutoBlockConfirm"},

    Start = function(Context)
        local SCAN_INTERVAL = 0.25
        local BLOCK_WAIT = 10
        local TELEPORT_TIMEOUT = 15
        local RETRY_DELAY = 3
        local MAX_ATTEMPTS = 3
        local FAILED_COOLDOWN = 30

        local Feature = {
            Name = "BlockNearbyPlayers",
            IsFeature = true,
            S = {
                Target = nil,
                StartedAt = 0,
                LastScan = -math.huge,
                Teleporting = false,
                TeleportAt = 0,
                Attempts = 0,
                RetryAt = 0,
                Token = 0,
                Status = "OFF",
            },
        }
        local S = Feature.S
        local Players = Context.Services.Players
        local AutoBlock = Context.AutoBlock
        local Confirm = Context.AutoBlockConfirm
        local AICFeature = Context.AICFeature

        local function SetStatus(Text)
            S.Status = Text
            local Label = Context.UIRef.NearbyBlockStatus
            if Label then
                Label.Text = "NEARBY BLOCK  " .. Text
            end
        end

        function Feature:Reset(Status)
            if S.Target and Confirm:IsConfirming(S.Target) then
                Confirm:Disarm()
            end
            S.Token += 1
            S.Target = nil
            S.Teleporting = false
            S.Attempts = 0
            S.RetryAt = 0
            SetStatus(Status or "SCANNING")
        end

        local function GetDistance(OtherPlayer, Root)
            if OtherPlayer == Context.Player or OtherPlayer.Parent ~= Players
                or AutoBlock:IsWhitelisted(OtherPlayer.UserId) then
                return nil
            end
            local Character = OtherPlayer.Character
            local OtherRoot = Character and Character:FindFirstChild("HumanoidRootPart")
            if not OtherRoot then
                return nil
            end
            return (Root.Position - OtherRoot.Position).Magnitude
        end

        function Feature:TeleportFailed(Message)
            S.Teleporting = false
            if S.Attempts >= MAX_ATTEMPTS then
                S.Attempts = 0
                S.RetryAt = os.clock() + FAILED_COOLDOWN
                Context.NotifyAction("Nearby Block", tostring(Message) .. "; retrying in 30s", 5)
            else
                S.RetryAt = os.clock() + RETRY_DELAY
            end
            SetStatus("HOP FAILED, RETRYING")
        end

        function Feature:Step(now)
            if not Context.Lifetime.Alive or not Context.Feature.BlockNearbyPlayers.Enabled then
                if S.Target or S.Status ~= "OFF" then self:Reset("OFF") end
                return false
            end

            if now - S.LastScan < SCAN_INTERVAL then
                return S.Target ~= nil
            end
            S.LastScan = now

            -- Another server operation or a party follow already owns the leave.
            local Server = Context.ServerHop
            if (Server and (Server.S.Teleporting or Server.S.Finding))
                or (AICFeature.IsPartyHolding and AICFeature.IsPartyHolding()) then
                self:Reset("WAITING FOR SERVER / PARTY")
                return false
            end

            if S.Teleporting then
                if now - S.TeleportAt >= TELEPORT_TIMEOUT then
                    self:TeleportFailed("Teleport timed out")
                end
                return true
            end

            local _, Humanoid, Root = Context.Runtime:GetCharacter()
            if not Root or not Humanoid or Humanoid.Health <= 0 then
                self:Reset("WAITING FOR CHARACTER")
                return false
            end

            local Radius = Context.CONFIG.NEARBY_BLOCK_DISTANCE
            if S.Target then
                local Distance = GetDistance(S.Target, Root)
                if not Distance or Distance > Radius then
                    self:Reset()
                end
            end

            if not S.Target then
                local Nearest, Best = nil, Radius
                for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                    local Distance = GetDistance(OtherPlayer, Root)
                    if Distance and Distance <= Best then
                        Nearest, Best = OtherPlayer, Distance
                    end
                end
                if not Nearest then
                    SetStatus("SCANNING (" .. tostring(Radius) .. " studs)")
                    return false
                end
                S.Target = Nearest
                S.StartedAt = now
            end

            if now < S.RetryAt then
                SetStatus("RETRY IN " .. tostring(math.ceil(S.RetryAt - now)) .. "s")
                return true
            end

            local Target = S.Target
            if not AutoBlock:IsBlocked(Target.UserId) then
                -- Force confirmation for this feature without changing the
                -- saved Auto Confirm Block toggle used by the old Auto Block.
                AutoBlock:PromptBlockPlayer(Target, true)
                SetStatus("BLOCKING @" .. Target.Name)
            else
                SetStatus("CHECKING @" .. Target.Name)
            end

            local Settled = AutoBlock:IsBlockSettled(Target)
            if not Settled and now - S.StartedAt < BLOCK_WAIT then
                return true
            end

            if not Settled then
                Context.NotifyAction("Nearby Block", "Block did not settle for @" .. Target.Name .. "; leaving anyway", 5)
                if Confirm:IsConfirming(Target) then Confirm:Disarm() end
            end
            SetStatus("HOPPING FROM @" .. Target.Name)
            S.Teleporting = true
            S.TeleportAt = now
            S.Attempts += 1
            local Token = S.Token
            task.spawn(function()
                if not Context.Lifetime.Alive or Token ~= S.Token then return end
                local Ok, Error = pcall(function()
                    AutoBlock:TeleportToPlace()
                end)
                if not Ok and Context.Lifetime.Alive and S.Teleporting and Token == S.Token then
                    self:TeleportFailed(Error)
                end
            end)
            return true
        end

        function Feature:Update()
            self:Step(os.clock())
        end

        AICFeature.NearbyBlockStep = function(now)
            return Feature:Step(now)
        end
        AICFeature.IsNearbyBlockHolding = function()
            return Context.Feature.BlockNearbyPlayers.Enabled and S.Target ~= nil
        end

        Context.Connect(game:GetService("TeleportService").TeleportInitFailed, function(Who, _, Message)
            if Who == Context.Player and S.Teleporting then
                Feature:TeleportFailed(Message or "Teleport failed")
            end
        end)
        Context.Lifetime.OnEnd(function()
            Feature:Reset("OFF")
        end)

        local Section = Context.UIRef.BlockSection
        Context.AICUI.BindFeatureToggle("BlockNearbyPlayers", "Block Nearby Players", function(Enabled)
            Feature:Reset(Enabled and "SCANNING" or "OFF")
            S.LastScan = -math.huge
        end, Section)
        Context.AICUI.AddGlobalSettingSlider(Section, "Nearby Block Distance", "NEARBY_BLOCK_DISTANCE")
        Context.UIRef.NearbyBlockStatus = Section:AddLabel("NEARBY BLOCK  OFF")

        return Feature
    end,
}
