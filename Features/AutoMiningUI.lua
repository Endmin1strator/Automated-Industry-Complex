-- AutoMiningUI owns the Auto Mining controls on the Mining tab: the toggle,
-- the status line, the Ore Priority list with a Target per ore, and the ways
-- to add an ore. The list is saved as the MINE_ORES setting.
return {
    Name = "AutoMiningUI",
    Dependencies = {"Runtime", "SaveConfig", "ProfileManager", "Components", "AutoMining", "Minezone"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local CONFIG = Context.CONFIG
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI
        local UIRef = Context.UIRef
        local NotifyAction = Context.NotifyAction
        local AutoMining = Context.AutoMining

        local MAX_STACK = Context.SaveConfig.MINE_ORE_MAX_STACK
        local NO_ORES_OPTION = "No ores found"

        local Module = {
            Name = "AutoMiningUI",
            OrePickerSignature = nil,
        }

        local Section = UIRef.MineSection

        AICUI.BindFeatureToggle("AutoMining", "Auto Mining", function(Enabled)
            if not Enabled then
                AutoMining:Reset()
            elseif #(Runtime:GetPlaceConfig().MINE_ZONES or {}) == 0 then
                NotifyAction("AUTO MINING", "Add a mine zone first; ores outside one are never mined.", 5)
            end
        end, Section)

        --// AutoMining writes the text.
        UIRef.MineStatusLabel = Section:AddLabel("STATUS  OFF")

        UIRef.OrePriorityComponent = Section:AddPriority("Ore Priority", {}, {
            Values = true,
            ValueLabel = "Target",
            Default = MAX_STACK,
            Min = 0,
            Max = MAX_STACK,
        })

        local OreList = UIRef.OrePriorityComponent

        --// The list is the source of truth while editing; CONFIG follows it.
        local function SaveOreList()
            local Values = OreList:GetValues()
            local Ores = {}

            for Index, Name in ipairs(OreList:GetPriority()) do
                table.insert(Ores, { Name = Name, Target = Values[Index] })
            end

            CONFIG.MINE_ORES = Ores
            AutoMining:Rescan()
            AICProfile.QueueProfileSave()
        end

        local function LoadOreList()
            local Names, Targets = {}, {}

            for Index, Entry in ipairs(CONFIG.MINE_ORES or {}) do
                Names[Index] = Entry.Name
                Targets[Index] = Entry.Target
            end

            OreList:SetPriority(Names, Targets)
        end

        local OriginalMoveUp = OreList.MoveUp
        local OriginalMoveDown = OreList.MoveDown
        local OriginalRemove = OreList.Remove

        function OreList:MoveUp(Name)
            OriginalMoveUp(self, Name)
            SaveOreList()
        end

        function OreList:MoveDown(Name)
            OriginalMoveDown(self, Name)
            SaveOreList()
        end

        function OreList:Remove(Name)
            local Removed = OriginalRemove(self, Name)
            SaveOreList()
            AICUI.RefreshOrePicker(true)
            return Removed
        end

        OreList.OnValueChanged = function()
            SaveOreList()
        end

        local function AddOre(Name)
            Name = tostring(Name or ""):gsub("^%s+", ""):gsub("%s+$", "")

            if Name == "" or Name == NO_ORES_OPTION then
                return
            end

            if not OreList:Add(Name, MAX_STACK) then
                NotifyAction("AUTO MINING", Name .. " is already in the list")
                return
            end

            SaveOreList()
            AICUI.RefreshOrePicker(true)
            NotifyAction("AUTO MINING", "Added " .. Name)
        end

        --// Loaded ores not yet in the list. Rebuilt only when that set
        --// changes, never while open (unless forced by the user), and in its
        --// old slot, like the target pickers.
        function AICUI.RefreshOrePicker(Force)
            local Options = {}

            for _, Name in ipairs(AutoMining:GetLoadedOreNames()) do
                if not table.find(OreList.Priority, Name) then
                    table.insert(Options, Name)
                end
            end

            if #Options == 0 then
                Options = { NO_ORES_OPTION }
            end

            local Old = UIRef.OrePicker
            local Signature = table.concat(Options, "\n")

            if Old and (Module.OrePickerSignature == Signature or (Old.IsOpen and not Force)) then
                return
            end

            local Order = Old and Old.Frame and Old.Frame.LayoutOrder

            if Old then
                if Old.Popup then Old.Popup:Destroy() end
                if Old.Frame then Old.Frame:Destroy() end
            end

            UIRef.OrePicker = Section:AddDropdown("Add Ore", Options, AddOre)

            if Order and UIRef.OrePicker.Frame then
                UIRef.OrePicker.Frame.LayoutOrder = Order
            end

            Module.OrePickerSignature = Signature
        end

        AICUI.RefreshOrePicker(true)

        Section:AddButton("Refresh Ore List", function()
            AICUI.RefreshOrePicker(true)
        end)

        --// For ores not loaded right now (streamed out with distance).
        UIRef.OreNameBox = Section:AddTextbox("Ore Name", "", function() end)

        Section:AddButton("Add Ore By Name", function()
            AddOre(UIRef.OreNameBox:Get())
            UIRef.OreNameBox:Set("")
        end)

        --// Called from updateFeatureButtons on every profile load.
        function AICUI.RefreshMiningUI()
            LoadOreList()
            AICUI.RefreshOrePicker(true)
            AICUI.RefreshMineZoneList()
            AICUI.RefreshMineZonePicker()
            AutoMining:Reset(true)
        end

        LoadOreList()

        return Module
    end,
}
