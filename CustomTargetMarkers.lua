-- ============================================================
-- CustomTargetMarkers
-- Shows a raid target icon selection popup above an enemy's
-- nameplate (with fallback to TargetFrame) when you target
-- a hostile unit.  Click an icon to apply it; click the
-- clear button to remove any existing marker.
--
-- Compatible with any UI addon (pfUI, ElvUI, TukUI, oUF, etc.)
-- Uses progressive detection: Blizzard nameplate API → WorldFrame
-- child scan → known custom target frame names → default TargetFrame.
--
-- Slash commands:
--   /ctm              – print help
--   /ctm enable       – toggle the addon on/off
--   /ctm lock         – lock frame to current position (stops tracking)
--   /ctm unlock       – unlock frame so it tracks nameplates again
--   /ctm size <n>     – set icon size (default 28, recommended 18-48)
--   /ctm reset        – reset position and size to defaults
-- ============================================================

-- ============================================================
-- Saved variable defaults  (persisted across sessions via CustomTargetMarkersDB)
-- ============================================================
CTM_DB_DEFAULTS = {
    enabled  = true,
    locked   = false,   -- true = fixed position, false = tracks nameplate
    iconSize = 28,
    posX     = nil,     -- UIParent-relative centre X (nil = auto)
    posY     = nil,     -- UIParent-relative centre Y (nil = auto)
}

-- ============================================================
-- Internal config (non-saved)
-- ============================================================
local CFG = {
    iconPad    = 3,     -- gap between icon buttons (px)
    framePad   = 5,     -- inner padding of the popup frame (px)
    npOffset   = 10,    -- gap above the nameplate / TargetFrame (px)
    updateRate = 0.05,  -- seconds between position-update ticks
}

-- Display order for marker buttons (most-used first: Skull → Star)
local ICON_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }

local ICON_NAMES = {
    [1] = "Star",   [2] = "Circle",   [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon",   [6] = "Square",   [7] = "Cross",   [8] = "Skull",
}

-- Texture coordinates inside UI-RaidTargetingIcons (L, R, T, B)
-- Sprite layout: 4 cols x 2 rows
--   Row 1: Star(1)  Circle(2)  Diamond(3)  Triangle(4)
--   Row 2: Moon(5)  Square(6)  Cross(7)    Skull(8)
local ICON_COORDS = {
    [1] = { 0,    0.25, 0,   0.5  },
    [2] = { 0.25, 0.5,  0,   0.5  },
    [3] = { 0.5,  0.75, 0,   0.5  },
    [4] = { 0.75, 1.0,  0,   0.5  },
    [5] = { 0,    0.25, 0.5, 1.0  },
    [6] = { 0.25, 0.5,  0.5, 1.0  },
    [7] = { 0.5,  0.75, 0.5, 1.0  },
    [8] = { 0.75, 1.0,  0.5, 1.0  },
}

local ICON_TEX  = "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcons"
local NUM_ICONS = table.getn(ICON_ORDER)   -- 8  (Lua 5.0 compatible, no # operator)
local NUM_BTNS  = NUM_ICONS + 1            -- +1 for the clear button

-- Runtime reference to the saved DB (set in VARIABLES_LOADED / PLAYER_LOGIN)
local db

-- ============================================================
-- Layout helpers
-- ============================================================
local function CalcFrameSize(iconSize)
    local w = CFG.framePad * 2 + iconSize * NUM_BTNS + CFG.iconPad * (NUM_BTNS - 1)
    local h = iconSize + CFG.framePad * 2
    return w, h
end

-- ============================================================
-- Create the popup frame
-- ============================================================
local popup = CreateFrame(
    "Frame", "CTM_Popup", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil
)
popup:SetFrameStrata("HIGH")
popup:SetFrameLevel(100)
popup:SetClampedToScreen(true)
popup:Hide()

local function ApplyBackdrop()
    if popup.SetBackdrop then
        popup:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        popup:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
        popup:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
    end
end
ApplyBackdrop()

-- Drag support (active when frame is unlocked)
popup:SetMovable(true)
popup:EnableMouse(true)
popup:RegisterForDrag("LeftButton")

popup:SetScript("OnDragStart", function(self)
    if db and not db.locked then
        self:StartMoving()
    end
end)
popup:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    local s    = UIParent:GetEffectiveScale() / self:GetEffectiveScale()
    if db then
        db.posX   = x * s
        db.posY   = y * s
        db.locked = true
    end
    print("|cff00ff00[CustomTargetMarkers]|r Frame locked at new position. Type |cffFFFF00/ctm unlock|r to track nameplates again.")
end)

-- Drag hint label shown when the frame is unlocked
local dragLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dragLabel:SetPoint("CENTER", popup, "CENTER", 0, 0)
dragLabel:SetText("|cffFFFF00Drag to move  /ctm lock to lock|r")
dragLabel:Hide()

-- ============================================================
-- Icon buttons
-- ============================================================
local buttons = {}

local function MakeIconButton(markerIndex, iconSize)
    local btn = CreateFrame("Button", "CTM_Btn_" .. markerIndex, popup)
    btn:SetWidth(iconSize)
    btn:SetHeight(iconSize)

    btn:SetNormalTexture(ICON_TEX)
    local c = ICON_COORDS[markerIndex]
    btn:GetNormalTexture():SetTexCoord(c[1], c[2], c[3], c[4])
    btn:SetPushedTexture(ICON_TEX)
    btn:GetPushedTexture():SetTexCoord(c[1], c[2], c[3], c[4])
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    btn.glow = glow

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ICON_NAMES[markerIndex], 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        if UnitExists("target") then SetRaidTarget("target", markerIndex) end
    end)

    buttons[markerIndex] = btn
end

-- Clear / remove marker button
local clearBtn = CreateFrame("Button", "CTM_ClearBtn", popup)
clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up", "ADD")
clearBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Clear Marker", 1, 0.2, 0.2)
    GameTooltip:Show()
end)
clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
clearBtn:SetScript("OnClick", function()
    if UnitExists("target") then SetRaidTarget("target", 0) end
end)

-- Build initial buttons (position/size applied properly after VARIABLES_LOADED)
for _, idx in ipairs(ICON_ORDER) do
    MakeIconButton(idx, 28)
end

-- ============================================================
-- Apply size – resizes the popup frame and all icon buttons
-- ============================================================
local function ApplySize(iconSize)
    local w, h = CalcFrameSize(iconSize)
    popup:SetWidth(w)
    popup:SetHeight(h)

    for pos, idx in ipairs(ICON_ORDER) do
        local btn  = buttons[idx]
        local xOff = CFG.framePad + (pos - 1) * (iconSize + CFG.iconPad)
        btn:SetWidth(iconSize)
        btn:SetHeight(iconSize)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", popup, "LEFT", xOff, 0)
    end

    local clearXOff = CFG.framePad + NUM_ICONS * (iconSize + CFG.iconPad)
    clearBtn:SetWidth(iconSize)
    clearBtn:SetHeight(iconSize)
    clearBtn:ClearAllPoints()
    clearBtn:SetPoint("LEFT", popup, "LEFT", clearXOff, 0)
end

-- ============================================================
-- Apply saved fixed position
-- ============================================================
local function ApplySavedPosition()
    if db and db.posX and db.posY then
        popup:ClearAllPoints()
        popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.posX, db.posY)
    end
end

-- ============================================================
-- Glow refresh – highlight the currently active marker
-- ============================================================
local function RefreshGlows()
    local active = (GetRaidTargetIndex and GetRaidTargetIndex("target")) or 0
    for idx, btn in pairs(buttons) do
        btn.glow:SetAlpha(idx == active and 0.65 or 0)
    end
end

-- ============================================================
-- Nameplate / target-frame finders (UI-addon agnostic)
-- ============================================================
local function FindTargetNameplate()
    -- 1. Blizzard nameplate API
    if C_NamePlate then
        local np = C_NamePlate.GetNamePlateForUnit("target")
        if np and np:IsShown() then return np end
    end

    -- 2. Generic WorldFrame child scan (pfUI, KuiNameplates, TidyPlates, etc.)
    for _, child in ipairs({WorldFrame:GetChildren()}) do
        if child:IsShown() then
            local ok, unit = pcall(child.GetAttribute, child, "unit")
            if ok and unit and UnitIsUnit(unit, "target") then return child end

            if child.UnitFrame then
                local ok2, unit2 = pcall(
                    child.UnitFrame.GetAttribute, child.UnitFrame, "unit")
                if ok2 and unit2 and UnitIsUnit(unit2, "target") then
                    return child
                end
            end

            if child.unit and UnitIsUnit(child.unit, "target") then
                return child
            end
        end
    end
    return nil
end

local function FindTargetFrame()
    local candidates = {
        "pfUI_target", "oUF_Target", "SUFFrametarget",
        "XPerl_Target", "PitBull4_Frames_target", "TargetFrame",
    }
    for _, name in ipairs(candidates) do
        local f = _G[name]
        if f and f.IsVisible and f:IsVisible() then return f end
    end
    if pfUI and pfUI.units then
        local f = pfUI.units["target"]
        if f and type(f) == "table" and f.IsVisible and f:IsVisible() then
            return f
        end
    end
    if oUF and oUF.units then
        for _, f in pairs(oUF.units) do
            if f and f.unit == "target" and f.IsVisible and f:IsVisible() then
                return f
            end
        end
    end
    return nil
end

-- ============================================================
-- Show / position logic
-- ============================================================
local function ShowPopup()
    if not db or not db.enabled then popup:Hide(); return end
    if not UnitExists("target") or not UnitIsEnemy("player", "target") then
        popup:Hide()
        return
    end

    -- Fixed / locked position: just show in place
    if db.locked and db.posX and db.posY then
        ApplySavedPosition()
        popup:Show()
        RefreshGlows()
        return
    end

    -- Tracking mode: follow the nameplate
    local np = FindTargetNameplate()
    if np then
        popup:ClearAllPoints()
        popup:SetPoint("BOTTOM", np, "TOP", 0, CFG.npOffset)
        popup:Show()
        RefreshGlows()
        return
    end

    -- Fallback: target unit frame
    local tf = FindTargetFrame()
    if tf then
        popup:ClearAllPoints()
        popup:SetPoint("BOTTOM", tf, "TOP", 0, CFG.npOffset)
        popup:Show()
        RefreshGlows()
        return
    end

    popup:Hide()
end

local throttle = 0
popup:SetScript("OnUpdate", function(self, dt)
    throttle = throttle + dt
    if throttle >= CFG.updateRate then
        throttle = 0
        ShowPopup()
    end
end)

-- ============================================================
-- Events
-- ============================================================
-- Shared initialisation logic called by VARIABLES_LOADED and PLAYER_LOGIN.
-- Using both events ensures saved variables are available on all client
-- versions: 1.12 (TurtleWoW), Classic Era, Wrath, Cata, etc.
local addonInitDone = false
local function InitAddon()
    if addonInitDone then return end
    addonInitDone = true

    if not CustomTargetMarkersDB then
        CustomTargetMarkersDB = {}
    end
    for k, v in pairs(CTM_DB_DEFAULTS) do
        if CustomTargetMarkersDB[k] == nil then
            CustomTargetMarkersDB[k] = v
        end
    end
    db = CustomTargetMarkersDB

    ApplySize(db.iconSize)

    if not db.locked then
        dragLabel:Show()
    end

    print("|cff00ff00[CustomTargetMarkers]|r Loaded. Type |cffFFFF00/ctm|r for options.")
end

local ev = CreateFrame("Frame")
-- VARIABLES_LOADED fires on 1.12 / TurtleWoW once saved vars are ready
-- PLAYER_LOGIN fires on all client versions as a reliable fallback
ev:RegisterEvent("VARIABLES_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("RAID_TARGET_UPDATE")
if C_NamePlate then
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "VARIABLES_LOADED"
    or event == "PLAYER_LOGIN" then
        InitAddon()

    elseif event == "PLAYER_TARGET_CHANGED" then
        ShowPopup()

    elseif event == "PLAYER_ENTERING_WORLD" then
        popup:Hide()

    elseif event == "RAID_TARGET_UPDATE" then
        if popup:IsShown() then RefreshGlows() end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if UnitExists("target") and UnitIsEnemy("player", "target")
        and arg1 and UnitIsUnit(arg1, "target") then
            ShowPopup()
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if arg1 and UnitIsUnit(arg1, "target") then
            ShowPopup()
        end
    end
end)

-- ============================================================
-- Slash commands  /ctm
-- ============================================================
local function PrintHelp()
    print("|cff00ff00[CustomTargetMarkers]|r commands:")
    print("  |cffFFFF00/ctm enable|r        – toggle addon on/off")
    print("  |cffFFFF00/ctm unlock|r        – unlock frame so it tracks nameplates")
    print("  |cffFFFF00/ctm lock|r          – lock frame at its current position")
    print("  |cffFFFF00/ctm size <10-64>|r  – set icon size (default 28)")
    print("  |cffFFFF00/ctm reset|r         – reset position and size to defaults")
end

SLASH_CTM1 = "/ctm"
SlashCmdList["CTM"] = function(msg)
    if not db then
        print("|cffff4444[CustomTargetMarkers]|r Not yet loaded.")
        return
    end

    -- string.match is Lua 5.1+; use string.find with captures for Lua 5.0
    local _, _, cmd, arg = string.find(msg, "^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if cmd == "" then
        PrintHelp()

    elseif cmd == "enable" then
        db.enabled = not db.enabled
        if db.enabled then
            print("|cff00ff00[CustomTargetMarkers]|r Enabled.")
            ShowPopup()
        else
            popup:Hide()
            print("|cffff4444[CustomTargetMarkers]|r Disabled.")
        end

    elseif cmd == "unlock" then
        db.locked = false
        dragLabel:Show()
        popup:SetMovable(true)
        -- Force the popup visible so the user can drag it immediately
        popup:ClearAllPoints()
        local cx = db.posX or (GetScreenWidth()  * UIParent:GetEffectiveScale() / 2)
        local cy = db.posY or (GetScreenHeight() * UIParent:GetEffectiveScale() / 2)
        popup:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        popup:Show()
        print("|cff00ff00[CustomTargetMarkers]|r Unlocked – drag the frame to reposition it.")
        print("Type |cffFFFF00/ctm lock|r when done.")

    elseif cmd == "lock" then
        local x, y = popup:GetCenter()
        local s    = UIParent:GetEffectiveScale() / popup:GetEffectiveScale()
        db.posX   = x * s
        db.posY   = y * s
        db.locked = true
        dragLabel:Hide()
        print("|cff00ff00[CustomTargetMarkers]|r Locked at current position.")

    elseif cmd == "size" then
        local n = tonumber(arg)
        if not n or n < 10 or n > 64 then
            print("|cffff4444[CustomTargetMarkers]|r Usage: /ctm size <10-64>")
            return
        end
        db.iconSize = n
        ApplySize(n)
        print("|cff00ff00[CustomTargetMarkers]|r Icon size set to " .. n .. ".")

    elseif cmd == "reset" then
        db.iconSize = CTM_DB_DEFAULTS.iconSize
        db.posX     = nil
        db.posY     = nil
        db.locked   = false
        ApplySize(db.iconSize)
        dragLabel:Show()
        print("|cff00ff00[CustomTargetMarkers]|r Position and size reset to defaults.")

    else
        PrintHelp()
    end
end
