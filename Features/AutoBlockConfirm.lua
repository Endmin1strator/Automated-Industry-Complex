-- AutoBlockConfirm presses "Block" in Roblox's Block dialog after Auto Block
-- opens it. Ported from Iambatman's AutoBlockConfirm.
-- Executor only: the dialog lives in CoreGui, which Studio scripts cannot read.
return {
    Name = "AutoBlockConfirm",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components", "AutoBlock"},

    Start = function(Context)
        local Services = Context.Services
        local RunService = Services.RunService
        local UserInputService = Services.UserInputService
        local FeatureState = Context.Feature
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local NotifyAction = Context.NotifyAction

        --// How long to look for the dialog after a prompt.
        local ARM_SECONDS = 6
        local SCAN_INTERVAL = 0.15
        --// Wait after each click method before checking the block list.
        local VERIFY_SECONDS = 0.7
        local FINAL_VERIFY_SECONDS = 2
        local CLICK_HOLD_SECONDS = 0.05
        --// Exact match: "Block and report" must never be pressed.
        local CONFIRM_TEXT = "Block"
        --// The dialog title reads "Block <name>?".
        local TITLE_PREFIX = "Block "

        local CloneReference = type(cloneref) == "function" and cloneref or function(Instance)
            return Instance
        end

        local CoreGui = CloneReference(game:GetService("CoreGui"))
        local GuiService = game:GetService("GuiService")
        local HasVirtualInput, VirtualInputManager = pcall(function()
            return CloneReference(game:GetService("VirtualInputManager"))
        end)

        if not HasVirtualInput then
            VirtualInputManager = nil
        end

        local Available = not RunService:IsStudio()
            and (pcall(function()
                return CoreGui:GetChildren()
            end))

        local Feature = {
            Name = "AutoBlockConfirm",
            IsFeature = true,
            S = {
                ArmToken = 0,
                ArmedPlayer = nil,
                ArmedUntil = 0,
                --// The click method that worked last, tried first next time.
                LastMethod = nil,
            },
        }

        local S = Feature.S

        local function Trim(Text)
            local Trimmed = string.gsub(tostring(Text or ""), "^%s*(.-)%s*$", "%1")
            return Trimmed
        end

        --// Turn on with getgenv().AICBlockConfirmDebug = true before running.
        local function IsDebug()
            local Ok, Env = pcall(function()
                return type(getgenv) == "function" and getgenv()
            end)

            return Ok and type(Env) == "table" and Env.AICBlockConfirmDebug == true
        end

        local function Log(...)
            if IsDebug() then
                print("[AutoBlockConfirm]", ...)
            end
        end

        local function IsBlocked(OtherPlayer)
            return AICFeature.isBlocked ~= nil and AICFeature.isBlocked(OtherPlayer.UserId) == true
        end

        local function WaitForBlocked(OtherPlayer, Seconds)
            local Deadline = os.clock() + Seconds

            while os.clock() < Deadline do
                if IsBlocked(OtherPlayer) then
                    return true
                end

                task.wait(0.1)
            end

            return IsBlocked(OtherPlayer)
        end

        local function GetButtonText(Button)
            if Button:IsA("TextButton") and Trim(Button.Text) ~= "" then
                return Trim(Button.Text)
            end

            for _, Descendant in ipairs(Button:GetDescendants()) do
                if (Descendant:IsA("TextLabel") or Descendant:IsA("TextButton")) and Trim(Descendant.Text) ~= "" then
                    return Trim(Descendant.Text)
                end
            end

            return ""
        end

        local function IsOnScreen(Gui)
            if not Gui or not Gui.Parent then
                return false
            end

            if Gui.AbsoluteSize.X < 1 or Gui.AbsoluteSize.Y < 1 then
                return false
            end

            local Node = Gui

            while Node do
                if Node:IsA("GuiObject") and not Node.Visible then
                    return false
                end

                if Node:IsA("LayerCollector") then
                    return Node.Enabled
                end

                Node = Node.Parent
            end

            return false
        end

        local function TitleNamesPlayer(Text, Names)
            if string.sub(Text, 1, #TITLE_PREFIX) ~= TITLE_PREFIX then
                return false
            end

            for _, Name in ipairs(Names) do
                if Name ~= "" and string.find(Text, Name, 1, true) then
                    return true
                end
            end

            return false
        end

        --// Only confirm a dialog whose title names our target, so a dialog
        --// the user opened for someone else is never pressed.
        local function DialogNamesPlayer(Button, OtherPlayer)
            local Names = {OtherPlayer.Name, OtherPlayer.DisplayName}
            local Node = Button.Parent

            while Node and not Node:IsA("LayerCollector") do
                for _, Descendant in ipairs(Node:GetDescendants()) do
                    if Descendant:IsA("TextLabel") and TitleNamesPlayer(Trim(Descendant.Text), Names) then
                        return true
                    end
                end

                Node = Node.Parent
            end

            return false
        end

        local function FireConnections(Signal)
            if type(getconnections) ~= "function" then
                return false
            end

            local Ok, Connections = pcall(getconnections, Signal)

            if not Ok or type(Connections) ~= "table" then
                return false
            end

            local Fired = false

            for _, Connection in ipairs(Connections) do
                if pcall(function()
                    Connection:Fire()
                end) then
                    Fired = true
                end
            end

            return Fired
        end

        local function FireSignal(Signal)
            if type(firesignal) ~= "function" then
                return false
            end

            return (pcall(firesignal, Signal))
        end

        --// Screen-space centre of a button, including the top bar inset when
        --// its ScreenGui uses it.
        local function GetButtonCenter(Button)
            local Center = Button.AbsolutePosition + Button.AbsoluteSize / 2
            local ScreenGui = Button:FindFirstAncestorWhichIsA("ScreenGui")

            if not (ScreenGui and ScreenGui.IgnoreGuiInset) then
                Center += GuiService:GetGuiInset()
            end

            return Center
        end

        local function ClickWithVirtualInput(Button)
            if not VirtualInputManager then
                return false
            end

            local Center = GetButtonCenter(Button)

            return (pcall(function()
                VirtualInputManager:SendMouseButtonEvent(Center.X, Center.Y, 0, true, game, 0)
                task.wait(CLICK_HOLD_SECONDS)
                VirtualInputManager:SendMouseButtonEvent(Center.X, Center.Y, 0, false, game, 0)
            end))
        end

        --// Last resort: moves the real cursor, clicks, then puts it back.
        local function ClickWithRealMouse(Button)
            if type(mousemoveabs) ~= "function" or type(mouse1click) ~= "function" then
                return false
            end

            local Center = GetButtonCenter(Button)
            local Previous = UserInputService:GetMouseLocation()

            return (pcall(function()
                mousemoveabs(Center.X, Center.Y)
                task.wait(CLICK_HOLD_SECONDS)
                mouse1click()
                task.wait(CLICK_HOLD_SECONDS)
                mousemoveabs(Previous.X, Previous.Y)
            end))
        end

        local CLICK_METHODS = {
            {
                Name = "getconnections",
                Click = function(Button)
                    return FireConnections(Button.Activated) or FireConnections(Button.MouseButton1Click)
                end,
            },
            {
                Name = "firesignal",
                Click = function(Button)
                    return FireSignal(Button.Activated) or FireSignal(Button.MouseButton1Click)
                end,
            },
            { Name = "VirtualInputManager", Click = ClickWithVirtualInput },
            { Name = "mouse", Click = ClickWithRealMouse },
        }

        local function GetOrderedMethods()
            local Ordered = {}

            for _, Method in ipairs(CLICK_METHODS) do
                if Method.Name == S.LastMethod then
                    table.insert(Ordered, 1, Method)
                else
                    table.insert(Ordered, Method)
                end
            end

            return Ordered
        end

        local function FindConfirmButton(OtherPlayer)
            local Ok, Descendants = pcall(function()
                return CoreGui:GetDescendants()
            end)

            if not Ok then
                return nil
            end

            for _, Descendant in ipairs(Descendants) do
                if Descendant:IsA("GuiButton")
                    and IsOnScreen(Descendant)
                    and GetButtonText(Descendant) == CONFIRM_TEXT
                    and DialogNamesPlayer(Descendant, OtherPlayer)
                then
                    return Descendant
                end
            end

            return nil
        end

        local function DumpDialogTexts()
            local Ok, Descendants = pcall(function()
                return CoreGui:GetDescendants()
            end)

            if not Ok then
                return
            end

            for _, Descendant in ipairs(Descendants) do
                if (Descendant:IsA("TextLabel") or Descendant:IsA("TextButton"))
                    and string.find(Descendant.Text, "Block", 1, true)
                then
                    print(
                        "[AutoBlockConfirm] dump:",
                        Descendant:GetFullName(),
                        Descendant.ClassName,
                        string.format("%q", Descendant.Text),
                        "onScreen=" .. tostring(IsOnScreen(Descendant))
                    )
                end
            end
        end

        local function Finish(Token)
            if Token == S.ArmToken then
                S.ArmedPlayer = nil
            end
        end

        local function WaitForConfirmButton(Token, OtherPlayer)
            while Token == S.ArmToken and os.clock() < S.ArmedUntil do
                local Button = FindConfirmButton(OtherPlayer)

                if Button then
                    return Button
                end

                task.wait(SCAN_INTERVAL)
            end

            return nil
        end

        local function Run(Token, OtherPlayer)
            local Button = WaitForConfirmButton(Token, OtherPlayer)

            if Token ~= S.ArmToken then
                return
            end

            if not Button then
                Log("Block dialog not found for", OtherPlayer.Name)

                if IsDebug() then
                    DumpDialogTexts()
                end

                Finish(Token)
                return
            end

            for _, Method in ipairs(GetOrderedMethods()) do
                if Token ~= S.ArmToken or not IsOnScreen(Button) then
                    break
                end

                local Sent = Method.Click(Button)
                Log(Method.Name, Sent and "sent" or "unavailable")

                if Sent and WaitForBlocked(OtherPlayer, VERIFY_SECONDS) then
                    S.LastMethod = Method.Name
                    Log("Blocked", OtherPlayer.Name, "via", Method.Name)
                    Finish(Token)
                    return
                end
            end

            --// A click may have closed the dialog while the block request is
            --// still in flight.
            if Token == S.ArmToken and not WaitForBlocked(OtherPlayer, FINAL_VERIFY_SECONDS) then
                warn("[AutoBlockConfirm] Could not confirm Block for", OtherPlayer.Name)
                NotifyAction("Auto Confirm Block", "Could not press Block; confirm it yourself.", 5)
            end

            Finish(Token)
        end

        function Feature:IsAvailable()
            return Available
        end

        --// Starts watching for the dialog PromptBlockPlayer just opened for
        --// this player.
        function Feature:Arm(OtherPlayer)
            if not Available or not FeatureState.AutoBlockConfirm.Enabled then
                return
            end

            if not OtherPlayer or not OtherPlayer.Parent or IsBlocked(OtherPlayer) then
                return
            end

            if S.ArmedPlayer == OtherPlayer and os.clock() < S.ArmedUntil then
                return
            end

            S.ArmToken += 1
            S.ArmedPlayer = OtherPlayer
            S.ArmedUntil = os.clock() + ARM_SECONDS
            task.spawn(Run, S.ArmToken, OtherPlayer)
        end

        function Feature:Disarm()
            S.ArmToken += 1
            S.ArmedPlayer = nil
        end

        function Feature:Update()
        end

        --// AutoBlock calls this right after it opens the dialog.
        AICFeature.ConfirmBlockPrompt = function(OtherPlayer)
            return Feature:Arm(OtherPlayer)
        end

        AICUI.BindFeatureToggle("AutoBlockConfirm", "Auto Confirm Block", function(Enabled)
            if Enabled and not Available then
                NotifyAction("Auto Confirm Block", "Executor only: Roblox's Block dialog cannot be reached here.", 5)
            end

            if not Enabled then
                Feature:Disarm()
            end
        end)

        return Feature
    end,
}
