local addonName, ns = ...

--------------------------------------------------------------------------------
-- CastBarOnly - Hide unit frame elements except cast bars
--
-- Key findings from 12.0 API exploration:
-- 1. Auras use FramePoolCollection (auraPools) - enumerate with :EnumerateActive()
-- 2. Edit Mode selection frames are anonymous children with IsSelected/ShowSelected
-- 3. TargetFramePowerBarAlt errors if shown without barInfo (encounter-specific)
-- 4. Must hook UpdateAuras to hide auras after Blizzard re-shows them
-- 5. Call UpdateAuras() after showing to refresh aura visibility
--
-- Commands: /cb target show|hide, /cb focus show|hide, /cb list
--------------------------------------------------------------------------------

-- State tracking for each supported frame type
ns.frameConfigs = {
    target = {
        mainFrame = "TargetFrame",
        spellBarPatterns = {"SpellBar", "CastBar", "Casting"}, -- patterns to preserve
        hidden = true,
        hiddenElements = {},
    },
    focus = {
        mainFrame = "FocusFrame",
        spellBarPatterns = {"SpellBar", "CastBar", "Casting"},
        hidden = false,
        hiddenElements = {},
    },
}

-- Forward declarations
local HideAurasForFrame

--------------------------------------------------------------------------------
-- Debug Output (uses the DebugConsole addon's copyable window when loaded)
--------------------------------------------------------------------------------

local function ShowDebugOutput(text)
    if DebugConsole and DebugConsole.Show then
        DebugConsole.Show(text)
    else
        for line in text:gmatch("[^\n]+") do
            print(line)
        end
    end
end

--------------------------------------------------------------------------------
-- Frame Discovery
--------------------------------------------------------------------------------

local function IsSpellBarFrame(frame, config)
    local name = frame:GetName()
    if not name then return false end

    for _, pattern in ipairs(config.spellBarPatterns) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

-- Check if frame is an Edit Mode selection frame (should not be touched)
local function IsEditModeFrame(frame)
    return frame.IsSelected ~= nil and frame.ShowSelected ~= nil
end

local function CatalogFrameChildren(frameType)
    local config = ns.frameConfigs[frameType]
    if not config then return end

    local mainFrame = _G[config.mainFrame]
    if not mainFrame then
        print("|cffff0000CastBarOnly:|r Could not find " .. config.mainFrame)
        return
    end

    config.hiddenElements = {}

    -- Get children
    local children = { mainFrame:GetChildren() }
    for _, child in ipairs(children) do
        if not IsSpellBarFrame(child, config) and not IsEditModeFrame(child) then
            table.insert(config.hiddenElements, {
                frame = child,
                name = child:GetName() or "unnamed_child",
                type = "frame"
            })
        end
    end

    -- Get regions (textures, fontstrings)
    local regions = { mainFrame:GetRegions() }
    for _, region in ipairs(regions) do
        table.insert(config.hiddenElements, {
            frame = region,
            name = region:GetName() or "unnamed_region",
            type = "region"
        })
    end

    return config.hiddenElements
end

--------------------------------------------------------------------------------
-- Hide/Show Functions
--------------------------------------------------------------------------------

local function HideFrameElements(frameType)
    local config = ns.frameConfigs[frameType]
    if not config then
        print("|cffff0000CastBarOnly:|r Unknown frame type: " .. tostring(frameType))
        return
    end

    local mainFrame = _G[config.mainFrame]

    -- Catalog if needed
    if #config.hiddenElements == 0 then
        CatalogFrameChildren(frameType)
    end

    -- Hide elements
    for _, elem in ipairs(config.hiddenElements) do
        if elem.frame then
            if elem.frame.Hide then
                elem.frame:Hide()
            end
            if elem.frame.SetAlpha then
                elem.frame:SetAlpha(0)
            end
        end
    end

    -- Disable mouse on the main frame so it doesn't intercept clicks
    if mainFrame then
        mainFrame:EnableMouse(false)
        HideAurasForFrame(mainFrame)
    end

    config.hidden = true
    -- print("|cff00ff00CastBarOnly:|r " .. frameType .. " elements hidden (cast bar preserved)")
end

-- Frames that shouldn't be manually shown (they manage their own visibility)
local skipShowFrames = {
    ["TargetFramePowerBarAlt"] = true,
    ["FocusFramePowerBarAlt"] = true,
}

local function ShowFrameElements(frameType)
    local config = ns.frameConfigs[frameType]
    if not config then
        print("|cffff0000CastBarOnly:|r Unknown frame type: " .. tostring(frameType))
        return
    end

    local mainFrame = _G[config.mainFrame]

    -- Re-enable mouse on the main frame
    if mainFrame then
        mainFrame:EnableMouse(true)
    end

    for _, elem in ipairs(config.hiddenElements) do
        if elem.frame and not skipShowFrames[elem.name] then
            if elem.frame.SetAlpha then
                elem.frame:SetAlpha(1)
            end
            if elem.frame.Show then
                elem.frame:Show()
            end
        end
    end

    config.hidden = false

    -- Trigger aura refresh so they become visible immediately
    if mainFrame and mainFrame.UpdateAuras then
        mainFrame:UpdateAuras()
    end

    print("|cff00ff00CastBarOnly:|r " .. frameType .. " elements shown (for Edit Mode)")
end

--------------------------------------------------------------------------------
-- List Command
--------------------------------------------------------------------------------

local function ListFrameElements(frameType)
    local config = ns.frameConfigs[frameType]
    if not config then
        print("|cffff0000CastBarOnly:|r Unknown frame type: " .. tostring(frameType))
        return
    end

    local mainFrame = _G[config.mainFrame]
    if not mainFrame then
        print("|cffff0000CastBarOnly:|r " .. config.mainFrame .. " not found")
        return
    end

    local output = {}
    table.insert(output, "=== " .. config.mainFrame .. " Children ===")

    local children = { mainFrame:GetChildren() }
    for i, child in ipairs(children) do
        local name = child:GetName() or "(anonymous)"
        local objType = child:GetObjectType()
        local isSpellBar = IsSpellBarFrame(child, config)
        local marker = isSpellBar and " [PRESERVED]" or ""
        table.insert(output, string.format("%d. %s (%s)%s", i, name, objType, marker))
    end

    table.insert(output, "\n=== " .. config.mainFrame .. " Regions ===")

    local regions = { mainFrame:GetRegions() }
    for i, region in ipairs(regions) do
        local name = region:GetName() or "(anonymous)"
        local objType = region:GetObjectType()
        table.insert(output, string.format("%d. %s (%s)", i, name, objType))
    end

    ShowDebugOutput(table.concat(output, "\n"))
end

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

SLASH_CASTBARONLY1 = "/cb"
SLASH_CASTBARONLY2 = "/castbaronly"

function SlashCmdList.CASTBARONLY(msg)
    local args = { strsplit(" ", msg) }
    local cmd = args[1] and args[1]:lower() or ""
    local subCmd = args[2] and args[2]:lower() or ""

    if cmd == "target" or cmd == "t" then
        if subCmd == "show" then
            ShowFrameElements("target")
        elseif subCmd == "hide" then
            HideFrameElements("target")
        else
            print("|cffff8800CastBarOnly:|r Usage: /cb target [show|hide]")
        end

    elseif cmd == "focus" or cmd == "f" then
        if subCmd == "show" then
            ShowFrameElements("focus")
        elseif subCmd == "hide" then
            HideFrameElements("focus")
        else
            print("|cffff8800CastBarOnly:|r Usage: /cb focus [show|hide]")
        end

    elseif cmd == "list" then
        local target = subCmd ~= "" and subCmd or "target"
        ListFrameElements(target)

    elseif cmd == "help" or cmd == "" then
        print("|cff00ff00CastBarOnly Commands:|r")
        print("  /cb target show - Show all target frame elements")
        print("  /cb target hide - Hide elements (keep cast bar)")
        print("  /cb focus show|hide - Same for focus frame")
        print("  /cb list [target|focus] - List frame elements")

    else
        print("|cffff8800CastBarOnly:|r Unknown command. Use /cb help")
    end
end

--------------------------------------------------------------------------------
-- Aura Hiding (hooks into UpdateAuras to hide buff/debuff icons)
--------------------------------------------------------------------------------

HideAurasForFrame = function(unitFrame)
    if not unitFrame then return end

    -- Hide all active aura frames from the pool
    if unitFrame.auraPools and unitFrame.auraPools.EnumerateActive then
        for auraFrame in unitFrame.auraPools:EnumerateActive() do
            auraFrame:Hide()
        end
    end
end

local function SetupAuraHook(frameType)
    local config = ns.frameConfigs[frameType]
    if not config then return end

    local mainFrame = _G[config.mainFrame]
    if not mainFrame then return end

    -- Hook UpdateAuras to hide auras whenever they're updated
    if mainFrame.UpdateAuras and not config.auraHooked then
        hooksecurefunc(mainFrame, "UpdateAuras", function(self)
            if config.hidden then
                HideAurasForFrame(self)
            end
        end)
        config.auraHooked = true
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, function()
            CatalogFrameChildren("target")
            SetupAuraHook("target")
            HideFrameElements("target")
            HideAurasForFrame(TargetFrame)
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local config = ns.frameConfigs["target"]
        if config and config.hidden then
            C_Timer.After(0.1, function()
                HideFrameElements("target")
                HideAurasForFrame(TargetFrame)
            end)
        end
    end
end)

print("|cff00ff00CastBarOnly|r loaded. Type /cb help for commands.")
