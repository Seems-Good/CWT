-- CWT.lua  —  CWT - Coach's Whistle Tracker
--
-- Shows "USE COACH'S WHISTLE" when:
--   • Emerald Coach's Whistle equipped in trinket slot 13 or 14
--   • NOT in combat
--   • In a group or raid
--   • Inside a raid, dungeon, or Mythic+ instance
--   • No Coaching buff (or buff expiring in < 5 min)
--
-- /cwt  — open settings

-- ============================================================
--  Constants
-- ============================================================
local ITEM_ID        = 193718
local SPELL_COACHING = 389581
local TRINKET_1      = 13
local TRINKET_2      = 14
local WARN_SECS      = 300
local TICK_INTERVAL  = 30
local SOUND_ID       = 204190

local FONT_SIZE_MIN  = 18
local FONT_SIZE_MAX  = 96
local FONT_FILE      = "Fonts\\FRIZQT__.TTF"

local COLOR_PRESETS = {
    { label = "Red",    r = 1.0, g = 0.15, b = 0.15 },
    { label = "Orange", r = 1.0, g = 0.55, b = 0.0  },
    { label = "Yellow", r = 1.0, g = 1.0,  b = 0.0  },
    { label = "White",  r = 1.0, g = 1.0,  b = 1.0  },
    { label = "Cyan",   r = 0.0, g = 1.0,  b = 1.0  },
}

local DB_DEFAULTS = {
    posX     = 0,
    posY     = 120,
    fontSize = 46,
    colorR   = 1.0,
    colorG   = 0.15,
    colorB   = 0.15,
    muted    = false,
}

-- Pulse
local _sin         = math.sin
local _pi2         = math.pi * 2
local PULSE_PERIOD = 1.4
local ALPHA_LO     = 0.25
local ALPHA_HI     = 1.00
local ALPHA_MID    = (ALPHA_HI + ALPHA_LO) / 2
local ALPHA_AMP    = (ALPHA_HI - ALPHA_LO) / 2
local pulseTime    = 0

-- ============================================================
--  Conditions
-- ============================================================
local function WhistleEquipped()
    return GetInventoryItemID("player", TRINKET_1) == ITEM_ID
        or GetInventoryItemID("player", TRINKET_2) == ITEM_ID
end

local function CoachingBuffOK()
    local data = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_COACHING)
    if not data then
        -- GetPlayerAuraBySpellID returns nil both when the buff is genuinely
        -- absent AND when aura data is restricted in an active M+ key (even
        -- between pulls). We cannot distinguish the two from nil alone.
        -- Safe default: if a M+ key is active, assume the buff is present to
        -- avoid a false-positive warning. We will catch the real absence once
        -- the key ends or via the UNIT_AURA event when the buff actually drops.
        if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
           and C_ChallengeMode.IsChallengeModeActive() then
            return true
        end
        return false
    end
    if not data.expirationTime or data.expirationTime == 0 then return true end
    return (data.expirationTime - GetTime()) >= WARN_SECS
end

local function AuraAccessRestricted()
    if C_RestrictedActions and C_RestrictedActions.IsRestrictionActive then
        return C_RestrictedActions.IsRestrictionActive(Enum.AddOnRestrictionType.Combat)
            or C_RestrictedActions.IsRestrictionActive(Enum.AddOnRestrictionType.Encounter)
    end
    return InCombatLockdown()
end

-- Returns true only when inside a raid, dungeon, or Mythic+ instance.
-- instanceType == "party"  covers normal/heroic dungeons and Mythic+
-- instanceType == "raid"   covers all raid difficulties
local function InInstanceContent()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "raid" or instanceType == "party")
end

local function ShouldWarn()
    if not WhistleEquipped()   then return false end
    if InCombatLockdown()      then return false end
    if not IsInGroup()         then return false end
    if not InInstanceContent() then return false end
    if AuraAccessRestricted()  then return false end
    if CoachingBuffOK()        then return false end
    return true
end

-- ============================================================
--  Frame
-- ============================================================
local frame = CreateFrame("Frame", "CWTFrame", UIParent)
frame:SetSize(900, 120)
frame:SetFrameStrata("HIGH")
frame:SetFrameLevel(100)
frame:Hide()

local label = frame:CreateFontString(nil, "OVERLAY")
label:SetAllPoints(frame)
label:SetFont(FONT_FILE, DB_DEFAULTS.fontSize, "OUTLINE")
label:SetTextColor(DB_DEFAULTS.colorR, DB_DEFAULTS.colorG, DB_DEFAULTS.colorB, 1)
label:SetShadowColor(0, 0, 0, 1)
label:SetShadowOffset(2, -2)
label:SetJustifyH("CENTER")
label:SetJustifyV("MIDDLE")
label:SetText("USE COACH'S WHISTLE")

local function ApplySavedAppearance()
    if not CWTDB then return end
    label:SetFont(FONT_FILE, CWTDB.fontSize or DB_DEFAULTS.fontSize, "OUTLINE")
    label:SetTextColor(
        CWTDB.colorR or DB_DEFAULTS.colorR,
        CWTDB.colorG or DB_DEFAULTS.colorG,
        CWTDB.colorB or DB_DEFAULTS.colorB, 1)
end

-- ============================================================
--  Pulse
-- ============================================================
frame:SetScript("OnShow", function(self)
    pulseTime = 0
    if not (CWTDB and CWTDB.muted) then
        PlaySound(SOUND_ID, "Master")
    end
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
--  Show / Hide
-- ============================================================
local previewMode = false

local function Show()
    if not frame:IsShown() then frame:Show() end
end

local function Hide()
    previewMode = false
    frame:Hide()
end

-- ============================================================
--  Ticker (30s safety net)
-- ============================================================
local ticker = nil

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
        if previewMode then return end
        if ShouldWarn() then Show() else if frame:IsShown() then Hide() end end
    end)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- ============================================================
--  Drag
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
--  Debug print (shared by button and legacy slash)
-- ============================================================
local function PrintDebug()
    local data = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_COACHING)
    local rem  = 0
    if data and data.expirationTime and data.expirationTime > 0 then
        rem = math.max(0, data.expirationTime - GetTime())
    end
    local inInst, instType = IsInInstance()
    print("|cffff9900[CWT Debug]|r ---")
    print("  equipped    = " .. tostring(WhistleEquipped()))
    print("  inCombat    = " .. tostring(InCombatLockdown()))
    print("  inGroup     = " .. tostring(IsInGroup()))
    print("  inInstance  = " .. tostring(inInst) .. "  (" .. tostring(instType) .. ")")
    print("  buffOK      = " .. tostring(CoachingBuffOK()))
    print("  remaining   = " .. string.format("%.0f", rem) .. "s")
    print("  ShouldWarn  = " .. tostring(ShouldWarn()))
    print("  visible     = " .. tostring(frame:IsShown()))
    print("  muted       = " .. tostring(CWTDB and CWTDB.muted))
    print("  fontSize    = " .. tostring(CWTDB and CWTDB.fontSize))
    print("  ticker      = " .. tostring(ticker ~= nil))
end

-- ============================================================
--  Settings panel
-- ============================================================
local CWTCategory
local muteBtn  -- referenced in ApplyMuteLabel below

local function ApplyMuteLabel()
    if not muteBtn then return end
    local muted = CWTDB and CWTDB.muted
    muteBtn:SetText(muted and "Unmute Sound" or "Mute Sound")
end

local function BuildSettingsCanvas()
    local W      = 600
    local PAD    = 20
    local BTN_H  = 26
    local HALF_W = math.floor((W - PAD * 2 - 8) / 2)
    local _floor = math.floor
    local y      = -10

    local outer = CreateFrame("Frame")
    outer:SetSize(W, 700)
    outer:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", "CWTSettingsScroll", outer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     outer, "TOPLEFT",      0,   0)
    scrollFrame:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -26,  0)

    local canvas = CreateFrame("Frame", nil, scrollFrame)
    canvas:SetSize(W - 30, 900)
    scrollFrame:SetScrollChild(canvas)

    local function addGap(px) y = y - px end

    local function sectionHeader(text)
        local fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
        fs:SetText(text)
        addGap(26)
    end

    local function divider()
        local line = canvas:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        line:SetPoint("TOPLEFT",  canvas, "TOPLEFT",  PAD,  y)
        line:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -PAD, y)
        line:SetHeight(1)
        addGap(14)
    end

    -- ── Position ─────────────────────────────────────────────
    sectionHeader("Position")

    local showBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    showBtn:SetSize(HALF_W, BTN_H)
    showBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    showBtn:SetText("Show Warning")

    local hideBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    hideBtn:SetSize(HALF_W, BTN_H)
    hideBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + HALF_W + 8, y)
    hideBtn:SetText("Hide Warning")
    addGap(BTN_H + 8)

    local dragBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    dragBtn:SetSize(HALF_W, BTN_H)
    dragBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    dragBtn:SetText("Drag to Reposition")

    local resetBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    resetBtn:SetSize(HALF_W, BTN_H)
    resetBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + HALF_W + 8, y)
    resetBtn:SetText("Reset Position")
    addGap(BTN_H + 18)
    divider()

    -- ── Font Size ─────────────────────────────────────────────
    sectionHeader("Font Size")

    local sizeSlider = CreateFrame("Slider", "CWTSizeSlider", canvas, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + 8, y)
    sizeSlider:SetWidth(W - PAD * 2 - 16)
    sizeSlider:SetMinMaxValues(FONT_SIZE_MIN, FONT_SIZE_MAX)
    sizeSlider:SetValueStep(2)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetValue(DB_DEFAULTS.fontSize)
    CWTSizeSliderLow:SetText(FONT_SIZE_MIN .. "pt")
    CWTSizeSliderHigh:SetText(FONT_SIZE_MAX .. "pt")
    CWTSizeSliderText:SetText("")

    local sizeReadout = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeReadout:SetPoint("BOTTOM", sizeSlider, "TOP", 0, 4)

    local lastSize = DB_DEFAULTS.fontSize
    local function refreshSize(v)
        local s = _floor(v + 0.5)
        sizeReadout:SetText(s .. "pt")
        return s
    end
    refreshSize(sizeSlider:GetValue())

    sizeSlider:SetScript("OnValueChanged", function(self, val)
        if not CWTDB then return end
        local s = refreshSize(val)
        if s == lastSize then return end
        lastSize = s
        CWTDB.fontSize = s
        label:SetFont(FONT_FILE, s, "OUTLINE")
    end)
    addGap(54)
    divider()

    -- ── Color ─────────────────────────────────────────────────
    sectionHeader("Text Color")

    for i, preset in ipairs(COLOR_PRESETS) do
        local col = (i - 1) % 2
        local row = _floor((i - 1) / 2)
        local btn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
        btn:SetSize(HALF_W, BTN_H)
        btn:SetPoint("TOPLEFT", canvas, "TOPLEFT",
            PAD + col * (HALF_W + 8), y - row * (BTN_H + 4))
        btn:SetText(preset.label)
        local fs = btn:GetFontString()
        if fs then fs:SetTextColor(preset.r, preset.g, preset.b, 1) end
        local r, g, b = preset.r, preset.g, preset.b
        btn:SetScript("OnClick", function()
            if not CWTDB then return end
            CWTDB.colorR, CWTDB.colorG, CWTDB.colorB = r, g, b
            label:SetTextColor(r, g, b, 1)
        end)
    end
    addGap(math.ceil(#COLOR_PRESETS / 2) * (BTN_H + 4) + 18)
    divider()

    -- ── Sound ─────────────────────────────────────────────────
    sectionHeader("Sound")

    muteBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    muteBtn:SetSize(HALF_W, BTN_H)
    muteBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    ApplyMuteLabel()
    addGap(BTN_H + 18)
    divider()

    -- ── Debug ─────────────────────────────────────────────────
    sectionHeader("Debug")

    local debugBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    debugBtn:SetSize(HALF_W, BTN_H)
    debugBtn:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD, y)
    debugBtn:SetText("Debug State")
    addGap(BTN_H + 18)
    divider()

    -- ── Footer ────────────────────────────────────────────────
    local function fline(text, indent)
        local fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + (indent or 0), y)
        fs:SetTextColor(0.72, 0.72, 0.72, 1)
        fs:SetText(text)
        addGap(18)
    end
    fline("|cFFFFD700Jeremy-Gstein|r  \226\128\148  CWT - Coach's Whistle Tracker")
    fline("|cFFFFD700Github:|r  |cFF4DA6FF[https://github.com/Seems-Good/CWT]|r", 8)
    fline("|cFFFFD700Guild:|r   |cFF4DA6FF[https://seemsgood.org]|r", 8)

    -- ── Sync panel on open ────────────────────────────────────
    outer:SetScript("OnShow", function()
        if not CWTDB then return end
        local sz = CWTDB.fontSize or DB_DEFAULTS.fontSize
        lastSize = sz
        sizeSlider:SetValue(sz)
        refreshSize(sz)
        ApplyMuteLabel()
    end)

    -- Close settings → stop drag preview
    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function()
            DisableDrag()
            if not ShouldWarn() then Hide() end
        end)
    end

    -- ── Callbacks ─────────────────────────────────────────────
    showBtn:SetScript("OnClick", function()
        previewMode = true
        Show()
    end)

    hideBtn:SetScript("OnClick", function()
        DisableDrag()
        Hide()
    end)

    dragBtn:SetScript("OnClick", function()
        previewMode = true
        Show()
        EnableDrag()
        print("|cffff9900[CWT]|r Drag the warning into position, then click Hide.")
    end)

    resetBtn:SetScript("OnClick", function()
        if not CWTDB then return end
        CWTDB.posX, CWTDB.posY = DB_DEFAULTS.posX, DB_DEFAULTS.posY
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", CWTDB.posX, CWTDB.posY)
        print("|cffff9900[CWT]|r Position reset.")
    end)

    muteBtn:SetScript("OnClick", function()
        if not CWTDB then return end
        CWTDB.muted = not CWTDB.muted
        ApplyMuteLabel()
        print("|cffff9900[CWT]|r Sound " .. (CWTDB.muted and "muted." or "unmuted."))
    end)

    debugBtn:SetScript("OnClick", PrintDebug)

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
--  Events
-- ============================================================
local rosterPending = false

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PET_BATTLE_OPENING_START")
events:RegisterEvent("PET_BATTLE_CLOSE")

events:SetScript("OnEvent", function(self, event, arg1)

    if event == "ADDON_LOADED" and arg1 == "CWT" then
        self:UnregisterEvent("ADDON_LOADED")
        CWTDB = CWTDB or {}
        for k, v in pairs(DB_DEFAULTS) do
            if CWTDB[k] == nil then CWTDB[k] = v end
        end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", CWTDB.posX, CWTDB.posY)
        ApplySavedAppearance()
        RegisterSettings()
        return
    end

    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            if ShouldWarn() then Show() end
            StartTicker()
        end)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        Hide()
        StopTicker()
        C_Timer.After(2, function()
            if ShouldWarn() then Show() end
            StartTicker()
        end)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" or event == "PET_BATTLE_OPENING_START" then
        Hide()
        return
    end

    if event == "UNIT_AURA" then
        if arg1 ~= "player" then return end
        -- Defer one frame so PLAYER_REGEN_DISABLED fires first (race condition fix)
        C_Timer.After(0, function()
            if ShouldWarn() then Show() else Hide() end
        end)
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if rosterPending then return end
        rosterPending = true
        C_Timer.After(0.5, function()
            rosterPending = false
            if ShouldWarn() then Show() else Hide() end
        end)
        return
    end

    if ShouldWarn() then Show() else Hide() end
end)

-- ============================================================
--  Slash  —  /cwt opens config
-- ============================================================
SLASH_CWT1 = "/cwt"
SlashCmdList["CWT"] = function()
    OpenConfig()
end
