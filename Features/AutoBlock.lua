-- AutoBlock owns its state, blocking logic, whitelist, and UI.
return {
    Name = "AutoBlock",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "ProfileManager", "Components"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local Services = Context.Services
        local Players = Services.Players
        local StarterGui = Services.StarterGui
        local Player = Context.Player
        local CONFIG = Context.CONFIG
        local Feature = Context.Feature
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICProfile = Context.AICProfile
        local SaveConfig = Context.SaveConfig
        local UIRef = Context.UIRef
        local NotifyAction = Context.NotifyAction

        local AutoBlock = {
            Name = "AutoBlock",
            IsFeature = true,
            Enabled = false,
            Button = nil,
            WhitelistComponent = nil,
            WhitelistBox = nil,
            WhitelistDropdown = nil,
        }

        AICFeature.S.BlockCache = AICFeature.S.BlockCache or {}
        AICFeature.S.BlockEnabled = Runtime:GetPlaceConfig().AUTOBLOCK == true
        AutoBlock.Enabled = AICFeature.S.BlockEnabled
        Feature.AutoBlock.Enabled = AutoBlock.Enabled

        function AutoBlock:SetEnabled(Value, Save)
            self.Enabled = Value == true
            AICFeature.S.BlockEnabled = self.Enabled
            Feature.AutoBlock.Enabled = self.Enabled

            if SaveConfig.AutoBlock then
                SaveConfig.AutoBlock.Enabled = self.Enabled
            end

            if self.Button then
                self.Button:Set(self.Enabled, false)
            end

            if Save ~= false and AICProfile.SaveActiveProfile then
                AICProfile.SaveActiveProfile()
            end
        end

        function AutoBlock:TeleportToPlace(PlaceId)
            game:GetService("TeleportService"):Teleport(PlaceId or game.PlaceId, Player)
        end

        function AutoBlock:NormalizeUserId(Value)
            local Text = tostring(Value or ""):gsub("%s+", "")

            if Text == "" or not Text:match("^%d+$") then
                return nil
            end

            return Text
        end

        function AutoBlock:IsWhitelisted(UserId)
            local Id = self:NormalizeUserId(UserId)

            if not Id then
                return false
            end

            for _, Entry in ipairs(CONFIG.BLOCK_WHITELIST or {}) do
                if self:NormalizeUserId(Entry) == Id then
                    return true
                end
            end

            return false
        end

        function AutoBlock:IsBlocked(UserId)
            local Success, BlockedUserIds = pcall(function()
                return StarterGui:GetCore("GetBlockedUserIds")
            end)

            if not Success or not BlockedUserIds then
                return false
            end

            for _, BlockedUserId in BlockedUserIds do
                if BlockedUserId == UserId then
                    return true
                end
            end

            return false
        end

        function AutoBlock:PromptBlockPlayer(OtherPlayer)
            local UserId = OtherPlayer.UserId

            if AICFeature.S.BlockCache[UserId] or self:IsBlocked(UserId) then
                return
            end

            AICFeature.S.BlockCache[UserId] = true

            local Success, ErrorMessage = pcall(function()
                StarterGui:SetCore("PromptBlockPlayer", OtherPlayer)
            end)

            if not Success then
                warn("PromptBlockPlayer failed:", ErrorMessage)
                AICFeature.S.BlockCache[UserId] = nil
                return
            end

            task.delay(CONFIG.BLOCK_COOLDOWN, function()
                AICFeature.S.BlockCache[UserId] = nil
            end)
        end

        function AutoBlock:RefreshWhitelistPlayerDropdown()
            local Section = UIRef.BlockSection

            if not Section then
                return
            end

            table.clear(UIRef.WhitelistPlayerOptions)

            local Options = {}

            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                if OtherPlayer ~= Player and not self:IsWhitelisted(OtherPlayer.UserId) then
                    local Label = string.format(
                        "%s (@%s)  %d",
                        OtherPlayer.DisplayName,
                        OtherPlayer.Name,
                        OtherPlayer.UserId
                    )

                    UIRef.WhitelistPlayerOptions[Label] = tostring(OtherPlayer.UserId)
                    table.insert(Options, Label)
                end
            end

            table.sort(Options, function(A, B)
                return string.lower(A) < string.lower(B)
            end)

            if #Options == 0 then
                Options = {"No other players"}
            end

            if UIRef.WhitelistPlayerDropdown then
                if UIRef.WhitelistPlayerDropdown.Popup then
                    UIRef.WhitelistPlayerDropdown.Popup:Destroy()
                end

                if UIRef.WhitelistPlayerDropdown.Frame then
                    UIRef.WhitelistPlayerDropdown.Frame:Destroy()
                end
            end

            self.WhitelistDropdown = Section:AddDropdown(
                "Add Player In Server",
                Options,
                function(Value)
                    local Id = UIRef.WhitelistPlayerOptions[Value]

                    if not Id or self:IsWhitelisted(Id) then
                        return
                    end

                    self.WhitelistComponent:Add(Id)
                    CONFIG.BLOCK_WHITELIST = self.WhitelistComponent.Priority
                    AICProfile.SaveActiveProfile()
                    NotifyAction("Whitelist", "Added " .. tostring(Value))
                    self:RefreshWhitelistPlayerDropdown()
                end
            )

            UIRef.WhitelistPlayerDropdown = self.WhitelistDropdown
        end

        function AutoBlock:RefreshUI()
            if self.WhitelistComponent then
                self.WhitelistComponent:SetPriority(table.clone(CONFIG.BLOCK_WHITELIST or {}))
            end

            self:SetEnabled(AICFeature.S.BlockEnabled == true, false)
            self:RefreshWhitelistPlayerDropdown()
        end

        function AutoBlock:CreateUI()
            local FeatureSection = UIRef.FeatureSection
            local BlockSection = UIRef.BlockSection

            if FeatureSection and FeatureSection.AddToggle then
                self.Button = FeatureSection:AddToggle(
                    "Auto Block",
                    self.Enabled,
                    function(Value)
                        self:SetEnabled(Value)
                    end
                )

                Feature.AutoBlock.Button = self.Button
            end

            if not BlockSection then
                return
            end

            self.WhitelistComponent = BlockSection:AddPriority(
                "Block Whitelist",
                CONFIG.BLOCK_WHITELIST or {}
            )
            UIRef.BlockWhitelistComponent = self.WhitelistComponent
            CONFIG.BLOCK_WHITELIST = self.WhitelistComponent.Priority

            self.WhitelistBox = BlockSection:AddTextbox("User ID", "", function() end)
            UIRef.BlockWhitelistBox = self.WhitelistBox

            BlockSection:AddButton("Add User ID", function()
                local Id = self:NormalizeUserId(self.WhitelistBox:Get())

                if not Id then
                    NotifyAction("Whitelist", "Enter a numeric UserId")
                    return
                end

                if self:IsWhitelisted(Id) then
                    NotifyAction("Whitelist", Id .. " is already on the list")
                    return
                end

                self.WhitelistComponent:Add(Id)
                CONFIG.BLOCK_WHITELIST = self.WhitelistComponent.Priority
                self.WhitelistBox:Set("")
                AICProfile.SaveActiveProfile()
                NotifyAction("Whitelist", "Added " .. Id)
                self:RefreshWhitelistPlayerDropdown()
            end)

            BlockSection:AddButton("Refresh Player List", function()
                self:RefreshWhitelistPlayerDropdown()
            end)

            BlockSection:AddButton("Add Everyone Here", function()
                local Added = 0

                for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                    if OtherPlayer ~= Player and not self:IsWhitelisted(OtherPlayer.UserId) then
                        self.WhitelistComponent:Add(tostring(OtherPlayer.UserId))
                        Added += 1
                    end
                end

                CONFIG.BLOCK_WHITELIST = self.WhitelistComponent.Priority
                AICProfile.SaveActiveProfile()
                NotifyAction("Whitelist", "Added " .. tostring(Added) .. " player(s)")
                self:RefreshWhitelistPlayerDropdown()
            end)

            BlockSection:AddButton("Clear Whitelist", function()
                self.WhitelistComponent:SetPriority({})
                CONFIG.BLOCK_WHITELIST = self.WhitelistComponent.Priority
                AICProfile.SaveActiveProfile()
                NotifyAction("Whitelist", "Cleared")
                self:RefreshWhitelistPlayerDropdown()
            end)

            local OriginalRemove = self.WhitelistComponent.Remove
            local OriginalMoveUp = self.WhitelistComponent.MoveUp
            local OriginalMoveDown = self.WhitelistComponent.MoveDown

            local WhitelistComponent = self.WhitelistComponent

            function WhitelistComponent:Remove(Entry)
                local Changed = OriginalRemove(self, Entry)
                CONFIG.BLOCK_WHITELIST = self.Priority
                AICProfile.SaveActiveProfile()
                AutoBlock:RefreshWhitelistPlayerDropdown()
                return Changed
            end

            function WhitelistComponent:MoveUp(Entry)
                OriginalMoveUp(self, Entry)
                CONFIG.BLOCK_WHITELIST = self.Priority
                AICProfile.SaveActiveProfile()
            end

            function WhitelistComponent:MoveDown(Entry)
                OriginalMoveDown(self, Entry)
                CONFIG.BLOCK_WHITELIST = self.Priority
                AICProfile.SaveActiveProfile()
            end

            self:RefreshWhitelistPlayerDropdown()

            Players.PlayerAdded:Connect(function()
                self:RefreshWhitelistPlayerDropdown()
            end)

            Players.PlayerRemoving:Connect(function()
                task.defer(function()
                    self:RefreshWhitelistPlayerDropdown()
                end)
            end)

            -- Compatibility hooks for older combat/profile code.
            AICFeature.TeleportToPlace = function(PlaceId)
                return AutoBlock:TeleportToPlace(PlaceId)
            end
            AICFeature.NormalizeUserId = function(Value)
                return AutoBlock:NormalizeUserId(Value)
            end
            AICFeature.IsWhitelisted = function(UserId)
                return AutoBlock:IsWhitelisted(UserId)
            end
            AICFeature.isBlocked = function(UserId)
                return AutoBlock:IsBlocked(UserId)
            end
            AICFeature.promptBlockPlayer = function(OtherPlayer)
                return AutoBlock:PromptBlockPlayer(OtherPlayer)
            end

            AICUI.RefreshWhitelistPlayerDropdown = function()
                return AutoBlock:RefreshWhitelistPlayerDropdown()
            end
        end

        function AutoBlock:Update()
            --// The player check runs inside the AutoFarming loop, after the
            --// Auto Farm and retreat gates, as it did in AFV2. Running it here
            --// too prompted twice and teleported with Auto Farm switched off.
        end

        AutoBlock:CreateUI()
        return AutoBlock
    end,
}
