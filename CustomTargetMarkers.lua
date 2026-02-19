-- ============================================================
-- CustomTargetMarkers
-- Shows a raid target icon selection popup above an enemy's
-- nameplate (with fallback to TargetFrame) when you target
-- a hostile unit.  Click an icon to apply it; click the
-- clear button (↩) to remove any existing marker.
-- ============================================================

-- ============================================================
-- Configuration
-- ============================================================
local CFG = {
    iconSize   = 28,          -- width/height of each icon button (px)
    iconPad    = 3,           -- gap between icon buttons (px)
    framePad   = 5,           -- inner padding of the popup frame (px)
    npOffset   = 10,          -- gap above the nameplate / TargetFrame (px)
    updateRate = 0.05,        -- seconds between position-update ticks
}

-- Display order for marker buttons (most-used first: Skull → Star)
local ICON_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }

local ICON_NAMES = {
    [1] = "Star",
    [2] = "Circle",
    [3] = "Diamond",
    [4] = "Triangle",
    [5] = "Moon",
    [6] = "Square",
    [7] = "Cross",
    [8] = "Skull",
}

-- Texture coordinates inside UI-RaidTargetingIcons (L, R, T, B)
-- Sprite layout: 4 cols × 2 rows
--   Row 1: Star(1)  Circle(2)  Diamond(3)  Triangle(4)
--   Row 2: Moon(5)  Square(6)  Cross(7)    Skull(8)
local ICON_COORDS = {
    [1] = { 0,    0.25, 0,   0.5  },  -- Star
    [2] = { 0.25, 0.5,  0,   0.5  },  -- Circle
    [3] = { 0.5,  0.75, 0,   0.5  },  -- Diamond
    [4] = { 0.75, 1.0,  0,   0.5  },  -- Triangle
    [5] = { 0,    0.25, 0.5, 1.0  },  -- Moon
    [6] = { 0.25, 0.5,  0.5, 1.0  },  -- Square
    [7] = { 0.5,  0.75, 0.5, 1.0  },  -- Cross
    [8] = { 0.75, 1.0,  0.5, 1.0  },  -- Skull
}

local ICON_TEX  = "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcons"
local NUM_ICONS = #ICON_ORDER   -- 8
local NUM_BTNS  = NUM_ICONS + 1 -- +1 for the clear button

-- ============================================================
-- Derived layout constants
-- ============================================================
local FRAME_W = CFG.framePad * 2
                + CFG.iconSize * NUM_BTNS
                + CFG.iconPad  * (NUM_BTNS - 1)
local FRAME_H = CFG.iconSize + CFG.framePad * 2

-- ============================================================
-- Create the popup frame
-- ============================================================
local popup = CreateFrame(
    "Frame", "CTM_Popup", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil
)
popup:SetFrameStrata("HIGH")
popup:SetFrameLevel(100)
popup:SetSize(FRAME_W, FRAME_H)
popup:Hide()
popup:SetClampedToScreen(true)

-- Dark semi-transparent backdrop with a thin border
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

-- ============================================================
-- Icon button factory
-- ============================================================
local buttons = {}  -- buttons[markerIndex] = button frame

local function MakeIconButton(markerIndex, xOffset)
    local btn = CreateFrame("Button", "CTM_Btn_" .. markerIndex, popup)
    btn:SetSize(CFG.iconSize, CFG.iconSize)
    btn:SetPoint("LEFT", popup, "LEFT", xOffset, 0)

    -- Normal texture – splice the correct cell from the sprite sheet
    btn:SetNormalTexture(ICON_TEX)
    local c = ICON_COORDS[markerIndex]
    btn:GetNormalTexture():SetTexCoord(c[1], c[2], c[3], c[4])

    -- Pushed texture (same icon, slightly inset via button default behaviour)
    btn:SetPushedTexture(ICON_TEX)
    btn:GetPushedTexture():SetTexCoord(c[1], c[2], c[3], c[4])

    -- Hover highlight
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- "Active" glow overlay (shown when this marker is already set on the target)
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    btn.glow = glow

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ICON_NAMES[markerIndex], 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Apply the marker on click
    btn:SetScript("OnClick", function()
        if UnitExists("target") then
            SetRaidTarget("target", markerIndex)
        end
    end)

    buttons[markerIndex] = btn
end

-- Build the 8 marker buttons
for pos, idx in ipairs(ICON_ORDER) do
    local xOff = CFG.framePad + (pos - 1) * (CFG.iconSize + CFG.iconPad)
    MakeIconButton(idx, xOff)
end

-- ============================================================
-- Clear / remove marker button
-- ============================================================
local clearXOff = CFG.framePad + NUM_ICONS * (CFG.iconSize + CFG.iconPad)
local clearBtn = CreateFrame("Button", "CTM_ClearBtn", popup)
clearBtn:SetSize(CFG.iconSize, CFG.iconSize)
clearBtn:SetPoint("LEFT", popup, "LEFT", clearXOff, 0)
clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up", "ADD")

clearBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Clear Marker", 1, 0.2, 0.2)
    GameTooltip:Show()
end)
clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
clearBtn:SetScript("OnClick", function()
    if UnitExists("target") then
        SetRaidTarget("target", 0)
    end
end)

-- ============================================================
-- Glow refresh – highlight whichever icon is currently active
-- ============================================================
local function RefreshGlows()
    local active = (GetRaidTargetIndex and GetRaidTargetIndex("target")) or 0
    for idx, btn in pairs(buttons) do
        btn.glow:SetAlpha(idx == active and 0.65 or 0)
    end
end

-- ============================================================
-- Position management
-- ============================================================
local function ShowPopup()
    -- Only show for hostile / attackable targets
    if not UnitExists("target") or not UnitIsEnemy("player", "target") then
        popup:Hide()
        return
    end

    -- Prefer positioning above the enemy's nameplate
    if C_NamePlate then
        local np = C_NamePlate.GetNamePlateForUnit("target")
        if np and np:IsShown() then
            popup:ClearAllPoints()
            popup:SetPoint("BOTTOM", np, "TOP", 0, CFG.npOffset)
            popup:Show()
            RefreshGlows()
            return
        end
    end

    -- Fallback: attach to the TargetFrame when the nameplate is off-screen
    if TargetFrame and TargetFrame:IsVisible() then
        popup:ClearAllPoints()
        popup:SetPoint("BOTTOM", TargetFrame, "TOP", 0, CFG.npOffset)
        popup:Show()
        RefreshGlows()
    else
        popup:Hide()
    end
end

-- Throttled OnUpdate so the popup tracks a moving nameplate smoothly
local throttle = 0
popup:SetScript("OnUpdate", function(self, dt)
    throttle = throttle + dt
    if throttle >= CFG.updateRate then
        throttle = 0
        ShowPopup()
    end
end)

-- ============================================================
-- Event handling
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("RAID_TARGET_UPDATE")

-- Nameplate visibility events (Classic 1.13+ / all live versions)
if C_NamePlate then
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end

ev:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        ShowPopup()

    elseif event == "PLAYER_ENTERING_WORLD" then
        popup:Hide()

    elseif event == "RAID_TARGET_UPDATE" then
        if popup:IsShown() then
            RefreshGlows()
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- A nameplate appeared – re-evaluate if it belongs to our target
        if UnitExists("target")
        and UnitIsEnemy("player", "target")
        and unit
        and UnitIsUnit(unit, "target") then
            ShowPopup()
        end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- Our target's nameplate left the screen – fall back or hide
        if unit and UnitIsUnit(unit, "target") then
            ShowPopup()
        end
    end
end)

-- ============================================================
-- Slash command  /ctm  –  toggle the popup on/off
-- ============================================================
local addonEnabled = true

SLASH_CTM1 = "/ctm"
SlashCmdList["CTM"] = function(msg)
    addonEnabled = not addonEnabled
    if addonEnabled then
        print("|cff00ff00[CustomTargetMarkers]|r Enabled.")
        ShowPopup()
    else
        popup:Hide()
        print("|cffff4444[CustomTargetMarkers]|r Disabled.")
    end
end

-- Wrap ShowPopup to respect the toggle
local _ShowPopup = ShowPopup
ShowPopup = function()
    if addonEnabled then _ShowPopup() end
end
