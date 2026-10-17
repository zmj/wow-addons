local addonName, ns = ...

--------------------------------------------------------------------------------
-- DebugConsole - Run Lua in game and show the output in a copyable window
--
-- Commands: /dbg <lua>
-- API for other addons: DebugConsole.Show(text)
--------------------------------------------------------------------------------

DebugConsole = {}

-- Debug modal frame reference
ns.debugFrame = nil

--------------------------------------------------------------------------------
-- Debug Modal
--------------------------------------------------------------------------------

local function CreateDebugModal()
    if ns.debugFrame then
        return ns.debugFrame
    end

    local frame = CreateFrame("Frame", "DebugConsoleFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 450)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("DebugConsole")

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "DebugConsoleScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 50)

    -- EditBox for output
    local editBox = CreateFrame("EditBox", "DebugConsoleEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    -- Hint text
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", 12, 15)
    hint:SetText("Ctrl+A to select all, Ctrl+C to copy")
    hint:SetTextColor(0.7, 0.7, 0.7)

    -- Close button at bottom
    local closeBottomBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBottomBtn:SetSize(80, 22)
    closeBottomBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    closeBottomBtn:SetText("Close")
    closeBottomBtn:SetScript("OnClick", function() frame:Hide() end)

    frame.editBox = editBox
    frame.scrollFrame = scrollFrame
    ns.debugFrame = frame

    return frame
end

local function ShowDebugOutput(text)
    local frame = CreateDebugModal()
    frame.editBox:SetText(text)
    frame.editBox:SetCursorPosition(0)
    frame.editBox:HighlightText(0, 0)
    frame:Show()
end

local function ExecuteDebugCode(code)
    local output = {}

    -- Capture print output
    local oldPrint = print
    print = function(...)
        local args = {...}
        local line = ""
        for i, v in ipairs(args) do
            line = line .. tostring(v)
            if i < #args then line = line .. "\t" end
        end
        table.insert(output, line)
    end

    -- Execute
    local func, err = loadstring(code)
    if not func then
        table.insert(output, "|cffff0000Syntax Error:|r " .. tostring(err))
    else
        local success, result = pcall(func)
        if not success then
            table.insert(output, "|cffff0000Runtime Error:|r " .. tostring(result))
        elseif result ~= nil then
            table.insert(output, "|cff00ff00Return:|r " .. tostring(result))
        end
    end

    -- Restore print
    print = oldPrint

    local outputText = table.concat(output, "\n")
    if outputText == "" then
        outputText = "(no output)"
    end

    ShowDebugOutput("-- Code:\n" .. code .. "\n\n-- Output:\n" .. outputText)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Show text in the copyable output window
DebugConsole.Show = ShowDebugOutput

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

SLASH_DEBUGCONSOLE1 = "/dbg"
SLASH_DEBUGCONSOLE2 = "/debugconsole"

function SlashCmdList.DEBUGCONSOLE(msg)
    local code = msg and msg:match("^%s*(.-)%s*$")
    if code and code ~= "" then
        ExecuteDebugCode(code)
    else
        print("|cffff8800DebugConsole:|r Usage: /dbg <lua code>")
    end
end
