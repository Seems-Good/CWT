-- CWT.lua  —  CWT - Coach's Whistle Tracker
--
-- Shows "USE COACH'S WHISTLE" when:
--   • Emerald Coach's Whistle equipped in trinket slot 13 or 14
--   • NOT in combat
--   • In a group or raid
--   • No Coaching buff (or buff expiring in < 5 min)
--
-- A 2-second ticker drives all show/hide logic.
-- onUpdate runs ONLY while the frame is visible and does pure alpha math.
--
-- /cwt          — show/hide commands
-- /cwt debug    — print state
-- /cwt config   — open settings to reposition

-- ============================================================
--  Config
-- ============================================================
local ITEM_ID        = 193718   -- Emerald Coach's Whistle
local SPELL_COACHING = 389581   -- Coaching buff
local TRINKET_1      = 13
local TRINKET_2      = 14
local WARN_SECS      = 300      -- warn if buff < 5 min remaining
local TICK_INTERVAL  = 30       -- safety-net fallback only; events handle real-time response
local SOUND_ID       = 204190   -- slide whistle

-- Pulse settings
local _sin         = math.sin
local _pi2         = math.pi * 2
local PULSE_PERIOD = 1.4
local ALPHA_LO     = 0.25
local ALPHA_HI     = 1.00
local ALPHA_MID    = (ALPHA_HI + ALPHA_LO) / 2
local ALPHA_AMP    = (ALPHA_HI - ALPHA_LO) / 2
local pulseTime    = 0

-- ============================================================
--  Condition — single source of truth, called every tick
-- ============================================================
local function WhistleEquipped()
    return GetInventoryItemID("player", TRINKET_1) == ITEM_ID
        or GetInventoryItemID("player", TRINKET_2) == ITEM_ID
end

local function CoachingBuffOK()
    -- Returns true if buff is active with >= WARN_SECS remaining
    local data = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_COACHING)
    if not data then return false end
    if not data.expirationTime or data.expirationTime == 0 then
        -- Permanent / infinite buff (shouldn't happen but handle it)
        return true
    end
    return (data.expirationTime - GetTime()) >= WARN_SECS
end

local function ShouldWarn()
    if not WhistleEquipped()  then return false end
    if InCombatLockdown()     then return false end
    if not IsInGroup()        then return false end
    if CoachingBuffOK()       then return false end
    return true
end

-- ============================================================
--  Frame
-- ============================================================
local frame = CreateFrame("Frame", "CWTFrame", UIParent)
frame:SetSize(900, 100)
frame:SetFrameStrata("HIGH")
frame:SetFrameLevel(100)
frame:Hide()

local label = frame:CreateFontString(nil, "OVERLAY")
label:SetAllPoints(frame)
label:SetFont("Fonts\\FRIZQT__.TTF", 46, "OUTLINE")
label:SetTextColor(1, 0.15, 0.15, 1)
label:SetShadowColor(0, 0, 0, 1)
label:SetShadowOffset(2, -2)
label:SetJustifyH("CENTER")
label:SetJustifyV("MIDDLE")
label:SetText("USE COACH'S WHISTLE")

-- ============================================================
--  Pulse  (only runs while frame is visible)
-- ============================================================
frame:SetScript("OnShow", function(self)
    pulseTime = 0
    PlaySound(SOUND_ID, "Master")
    self:SetScript("OnUpdate", function(_, elapsed)
        pulseTime = (pulseTime + elapsed) % PULSE_PERIOD
        frame:SetAlpha(ALPHA_MID + ALPHA_AMP * _sin(
            pulseTime * _pi2 / PULSE_PERIOD + (math.pi / 2)))
    end)
end)

frame:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    self:SetAlpha(ALPHA_HI)
end)

-- ============================================================
--  Show / Hide helpers
-- ============================================================
local previewMode = false

local function Show()
    if not frame:IsShown() then
        frame:Show()
    end
end

local function Hide()
    previewMode = false
    frame:Hide()
end

-- ============================================================
--  Ticker — checks conditions every TICK_INTERVAL seconds
--  This is the authoritative driver. Simple and reliable.
-- ============================================================
local ticker = nil

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
        if previewMode then return end
        if ShouldWarn() then
            Show()
        else
            if frame:IsShown() then Hide() end
        end
    end)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- ============================================================
--  Drag support (for /cwt config)
-- ============================================================
local function EnableDrag()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if CWTDB then
            local x, y   = self:GetCenter()
            local cx, cy = UIParent:GetCenter()
            CWTDB.posX = x - cx
            CWTDB.posY = y - cy
        end
        print("|cffff9900[CWT]|r Position saved.")
    end)
end

local function DisableDrag()
    frame:SetMovable(false)
    frame:EnableMouse(false)
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop",  nil)
end

-- ============================================================
--  Settings panel
-- ============================================================
local CWTCategory

local function BuildSettingsCanvas()
    local W     = 600
    local PAD   = 20
    local BTN_H = 26
    local HALF_W = math.floor((W - PAD * 2 - 8) / 2)
    local y     = -10

    local outer = CreateFrame("Frame")
    outer:SetSize(W, 300)
    outer:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", "CWTSettingsScroll", outer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     outer, "TOPLEFT",      0,   0)
    scrollFrame:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -26,  0)

    local canvas = CreateFrame("Frame", nil, scrollFrame)
    canvas:SetSize(W - 30, 400)
    scrollFrame:SetScrollChild(canvas)

    local function addGap(px) y = y - px end

    local hdr = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    hdr:SetText("Position")
    addGap(26)

    local showBtn  = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    showBtn:SetSize(HALF_W, BTN_H)
    showBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    showBtn:SetText("Show Warning")

    local hideBtn  = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    hideBtn:SetSize(HALF_W, BTN_H)
    hideBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + HALF_W + 8, y)
    hideBtn:SetText("Hide Warning")
    addGap(BTN_H + 8)

    local dragBtn  = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    dragBtn:SetSize(HALF_W, BTN_H)
    dragBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    dragBtn:SetText("Drag to Reposition")

    local resetBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    resetBtn:SetSize(HALF_W, BTN_H)
    resetBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + HALF_W + 8, y)
    resetBtn:SetText("Reset Position")
    addGap(BTN_H + 24)

    local sep = canvas:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    sep:SetPoint("TOPLEFT",  canvas, "TOPLEFT",  PAD,  y)
    sep:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -PAD, y)
    sep:SetHeight(1)
    addGap(14)

    local function fline(text, indent)
        local fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + (indent or 0), y)
        fs:SetTextColor(0.72, 0.72, 0.72, 1)
        fs:SetText(text)
        addGap(18)
    end
    fline("|cFFFFD700Jeremy-Gstein|r  \226\128\148  CWT - Coach's Whistle Tracker")
    fline("|cFFFFD700Github:|r \226\128\148  |cFF4DA6FF[https://github.com/Seems-Good/CWT]|r", 8)
    fline("|cFFFFD700Guild Website:|r \226\128\148  |cFF4DA6FF[https://seemsgood.org]|r", 8)

    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function()
            DisableDrag()
            if not ShouldWarn() then Hide() end
        end)
    end

    showBtn:SetScript("OnClick",  function() previewMode = true;  Show() end)
    hideBtn:SetScript("OnClick",  function() DisableDrag(); Hide() end)
    dragBtn:SetScript("OnClick",  function()
        previewMode = true
        Show()
        EnableDrag()
        print("|cffff9900[CWT]|r Drag the warning into position, then click Hide.")
    end)
    resetBtn:SetScript("OnClick", function()
        if not CWTDB then return end
        CWTDB.posX, CWTDB.posY = 0, 120
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        print("|cffff9900[CWT]|r Position reset.")
    end)

    return outer
end

local function RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local canvas = BuildSettingsCanvas()
    CWTCategory = Settings.RegisterCanvasLayoutCategory(canvas, "CWT - Coach's Whistle Tracker")
    Settings.RegisterAddOnCategory(CWTCategory)
end

local function OpenConfig()
    if CWTCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(CWTCategory:GetID())
    end
end

-- ============================================================
--  Events  — instant response for all known state changes.
--  Ticker (30s) is only a safety net for anything we miss.
-- ============================================================
local rosterPending = false  -- debounce GROUP_ROSTER_UPDATE burst

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")    -- entered combat  → hide now
events:RegisterEvent("PLAYER_REGEN_ENABLED")     -- left combat     → check now
events:RegisterEvent("UNIT_AURA")                -- buff gained/lost → check now
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED") -- trinket swap    → check now
events:RegisterEvent("GROUP_ROSTER_UPDATE")      -- joined/left group → check now
events:RegisterEvent("PET_BATTLE_OPENING_START")
events:RegisterEvent("PET_BATTLE_CLOSE")

events:SetScript("OnEvent", function(self, event, arg1)

    -- ── One-time DB + settings init ──────────────────────────
    if event == "ADDON_LOADED" and arg1 == "CWT" then
        self:UnregisterEvent("ADDON_LOADED")
        CWTDB = CWTDB or {}
        if CWTDB.posX == nil then CWTDB.posX = 0   end
        if CWTDB.posY == nil then CWTDB.posY = 120  end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", CWTDB.posX, CWTDB.posY)
        RegisterSettings()
        return
    end

    -- ── First login: let world settle, then start safety-net ticker ──
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            if ShouldWarn() then Show() end
            StartTicker()
        end)
        return
    end

    -- ── Zone change / reload: reset everything ───────────────
    if event == "PLAYER_ENTERING_WORLD" then
        Hide()
        StopTicker()
        C_Timer.After(2, function()
            if ShouldWarn() then Show() end
            StartTicker()
        end)
        return
    end

    -- ── Combat start: hide immediately ───────────────────────
    if event == "PLAYER_REGEN_DISABLED" or event == "PET_BATTLE_OPENING_START" then
        Hide()
        return
    end

    -- ── Aura update: only care about the player ───────────────
    -- Fires when Coaching buff is applied or removed.
    if event == "UNIT_AURA" then
        if arg1 ~= "player" then return end
        if ShouldWarn() then Show() else Hide() end
        return
    end

    -- ── Group roster: debounce the burst of events ────────────
    if event == "GROUP_ROSTER_UPDATE" then
        if rosterPending then return end
        rosterPending = true
        C_Timer.After(0.5, function()
            rosterPending = false
            if ShouldWarn() then Show() else Hide() end
        end)
        return
    end

    -- ── Everything else: left combat, equipment changed,
    --    pet battle closed — just re-evaluate immediately ──────
    if ShouldWarn() then Show() else Hide() end
end)

-- ============================================================
--  Slash
-- ============================================================
SLASH_CWT1 = "/cwt"
SlashCmdList["CWT"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "config" then
        OpenConfig()

    elseif cmd == "debug" then
        local data = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_COACHING)
        local rem  = 0
        if data and data.expirationTime and data.expirationTime > 0 then
            rem = math.max(0, data.expirationTime - GetTime())
        end
        print("|cffff9900[CWT Debug]|r ---")
        print("  equipped  = " .. tostring(WhistleEquipped()))
        print("  inCombat  = " .. tostring(InCombatLockdown()))
        print("  inGroup   = " .. tostring(IsInGroup()))
        print("  buffOK    = " .. tostring(CoachingBuffOK()))
        print("  remaining = " .. string.format("%.0f", rem) .. "s")
        print("  ShouldWarn= " .. tostring(ShouldWarn()))
        print("  visible   = " .. tostring(frame:IsShown()))
        print("  ticker    = " .. tostring(ticker ~= nil))

    else
        print("|cffff9900[CWT]|r /cwt config  —  open settings")
        print("|cffff9900[CWT]|r /cwt debug   —  print state")
    end
end
