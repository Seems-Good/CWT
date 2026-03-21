-- CWT.lua
-- CWT - Coach's Whistle Tracker
--
-- Shows "USE COACH'S WHISTLE" when:
--   • Emerald Coach's Whistle is equipped in trinket slot 13 or 14
--   • Player is NOT in combat
--   • Player does NOT have the Coaching buff, OR it has < 5 min remaining
--
-- Right-click  : toggle lock/unlock (also stops the /cwt config preview)
-- Left-click   : drag to move (only when unlocked)
--
-- /cwt config  : show the warning as a preview so you can drag it into place,
--                then right-click to lock when happy
-- /cwt debug   : print current state to chat

local addonName, addon = ...
local L = addon.L

-- ============================================================
--  Constants
-- ============================================================
local ITEM_ID        = 193718   -- Emerald Coach's Whistle
local SPELL_COACHING = 389581   -- "Coaching" buff (1 hr, applied when you use the trinket)
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14
local WARN_THRESHOLD = 300      -- warn when buff has < 5 min left
local SOUND_ID       = 204190   -- https://www.wowhead.com/sound=204190/fx-slidewhistle-down-short02

-- Pulse
local _sin         = math.sin
local _pi2         = math.pi * 2
local PULSE_PERIOD = 1.4
local ALPHA_MIN    = 0.25
local ALPHA_MAX    = 1.00
local ALPHA_MID    = (ALPHA_MAX + ALPHA_MIN) / 2
local ALPHA_AMP    = (ALPHA_MAX - ALPHA_MIN) / 2
local PHASE_OFFSET = math.pi / 2
local pulseTime    = 0

-- ============================================================
--  Cached state  — NEVER read inside OnUpdate
--  All fields updated by events; OnUpdate only reads warnActive.
-- ============================================================
local whistleEquipped  = false
local inCombat         = false
local inGroup          = false
local coachingExpiry   = 0      -- GetTime() value when Coaching buff expires, 0 = no buff
local previewMode      = false

-- Called from events only — no Lua table allocation here.
local function RefreshEquipped()
    whistleEquipped =
        GetInventoryItemID("player", TRINKET_SLOT_1) == ITEM_ID or
        GetInventoryItemID("player", TRINKET_SLOT_2) == ITEM_ID
end

-- Scans auras once per event, caches the expiry timestamp.
-- Returns remaining seconds (for timer scheduling).
local function RefreshCoachingAura()
    for i = 1, 40 do
        local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not data then break end
        if data.spellId == SPELL_COACHING then
            coachingExpiry = (data.expirationTime and data.expirationTime > 0)
                             and data.expirationTime or 0
            return coachingExpiry > 0 and math.max(0, coachingExpiry - GetTime()) or 0
        end
    end
    coachingExpiry = 0
    return 0
end

-- Read by OnUpdate — pure boolean, zero API calls, zero allocations.
local warnActive = false

local function UpdateWarnActive()
    if not whistleEquipped then warnActive = false; return end
    if inCombat            then warnActive = false; return end
    if not inGroup         then warnActive = false; return end
    -- Use cached expiry: no API call
    local rem = coachingExpiry > 0 and math.max(0, coachingExpiry - GetTime()) or 0
    warnActive = (rem == 0 or rem < WARN_THRESHOLD)
end

-- Legacy wrapper used by a few callsites
local function CoachingRemaining()
    return coachingExpiry > 0 and math.max(0, coachingExpiry - GetTime()) or 0
end

-- ============================================================
--  Warning frame
-- ============================================================
local CWT = CreateFrame("Frame", "CWTFrame", UIParent)
CWT:SetSize(900, 100)
CWT:SetFrameStrata("HIGH")
CWT:SetFrameLevel(100)
CWT:SetMovable(true)
CWT:EnableMouse(true)
CWT:RegisterForDrag("LeftButton")
CWT:Hide()

local label = CWT:CreateFontString(nil, "OVERLAY")
label:SetAllPoints(CWT)
label:SetFont("Fonts\\FRIZQT__.TTF", 46, "OUTLINE")
label:SetTextColor(1, 0.15, 0.15, 1)
label:SetShadowColor(0, 0, 0, 1)
label:SetShadowOffset(2, -2)
label:SetJustifyH("CENTER")
label:SetJustifyV("MIDDLE")
label:SetText(L.WARNING_TEXT)

-- ============================================================
--  Pulse  (OnUpdate alpha-only, self-terminating)
-- ============================================================
-- OnUpdate: pure arithmetic only. No API calls, no table allocations.
-- warnActive is set by events via UpdateWarnActive(). OnUpdate just reads it.
local function onUpdate(self, elapsed)
    if not previewMode and not warnActive then
        CWT:Hide()
        return
    end
    pulseTime = (pulseTime + elapsed) % PULSE_PERIOD
    self:SetAlpha(ALPHA_MID + ALPHA_AMP * _sin(
        pulseTime * _pi2 / PULSE_PERIOD + PHASE_OFFSET))
end

CWT:SetScript("OnShow", function(self)
    pulseTime = 0
    -- Play a sharp whistle alert. 621. is SOUNDKIT.RAID_WARNING which is
    -- a recognisable short alert horn. 8959 is the in-game whistle sound.
    PlaySound(8959, "Master")
    self:SetScript("OnUpdate", onUpdate)
end)

CWT:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    self:SetAlpha(1)
    previewMode = false
end)

-- ============================================================
--  Drag
-- ============================================================
CWT:SetScript("OnDragStart", function(self)
    if CWTDB and CWTDB.locked then return end
    if InCombatLockdown() then return end
    self:StartMoving()
end)

CWT:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if CWTDB then
        local x, y   = self:GetCenter()
        local cx, cy = UIParent:GetCenter()
        CWTDB.posX = x - cx
        CWTDB.posY = y - cy
    end
end)

-- ============================================================
--  Right-click: lock / unlock
-- ============================================================
CWT:SetScript("OnMouseUp", function(self, btn)
    if btn ~= "RightButton" then return end
    if not CWTDB then return end
    local db = CWTDB
    db.locked = not db.locked
    if db.locked then
        -- Locking ends the config preview
        previewMode = false
        warnActive = false
        CWT:Hide()
        print("|cffff9900[CWT]|r " .. L.MSG_LOCKED)
    else
        print("|cffff9900[CWT]|r " .. L.MSG_UNLOCKED)
    end
end)

-- ============================================================
--  Tooltip hint
-- ============================================================
CWT:SetScript("OnEnter", function(self)
    if not CWTDB then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    if CWTDB.locked then
        GameTooltip:AddLine(L.TT_UNLOCK, 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(L.TT_DRAG, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L.TT_LOCK, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end)
CWT:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================
--  Show / Hide helpers
-- ============================================================
local function ShowWarning()
    UpdateWarnActive()
    if warnActive then CWT:Show() end
end

local function HideWarning()
    previewMode = false
    warnActive  = false
    CWT:Hide()
end

-- ============================================================
--  Expiry warning timer
-- ============================================================
local expiryTimer = nil

local function CancelExpiryTimer()
    if expiryTimer then expiryTimer:Cancel(); expiryTimer = nil end
end

local function ScheduleExpiryTimer()
    CancelExpiryTimer()
    local rem = CoachingRemaining()
    if rem <= WARN_THRESHOLD then return end
    local delay = rem - WARN_THRESHOLD
    expiryTimer = C_Timer.NewTimer(delay, function()
        expiryTimer = nil
        UpdateWarnActive()
        if warnActive then ShowWarning() end
    end)
end

-- ============================================================
--  Evaluate: called after every relevant state change
--  This is the ONLY place API calls happen; never inside OnUpdate.
-- ============================================================
local function Evaluate()
    UpdateWarnActive()
    if warnActive then
        CancelExpiryTimer()
        ShowWarning()
    else
        local rem = CoachingRemaining()
        if rem > WARN_THRESHOLD then
            HideWarning()
            ScheduleExpiryTimer()
        else
            HideWarning()
        end
    end
end

-- ============================================================
--  Events
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")   -- combat start  → hide
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")    -- combat end    → re-evaluate
eventFrame:RegisterEvent("UNIT_AURA")               -- buff change   → re-evaluate
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")-- equip change  → re-check trinket
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")     -- group join/leave → re-evaluate
eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
eventFrame:RegisterEvent("PET_BATTLE_CLOSE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)

    -- ── DB init ──────────────────────────────────────────────
    if event == "ADDON_LOADED" and arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        if not CWTDB then
            CWTDB = { posX = 0, posY = 120, locked = false }
        end
        local db = CWTDB
        if db.posX   == nil then db.posX   = 0     end
        if db.posY   == nil then db.posY   = 120   end
        if db.locked == nil then db.locked = false  end
        CWT:ClearAllPoints()
        CWT:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
        return
    end

    -- ── Login: inventory ready ───────────────────────────────
    if event == "PLAYER_LOGIN" then
        inCombat = InCombatLockdown()
        inGroup  = IsInGroup()
        RefreshEquipped()
        -- Delay slightly so auras are fully populated before we check
        C_Timer.After(1.5, function()
            inGroup = IsInGroup()
            RefreshCoachingAura()
            Evaluate()
        end)
        return
    end

    -- ── Zone change / reload UI ──────────────────────────────
    if event == "PLAYER_ENTERING_WORLD" then
        inCombat = false
        inGroup  = false
        coachingExpiry = 0
        warnActive = false
        CancelExpiryTimer()
        HideWarning()
        C_Timer.After(1.5, function()
            inCombat = InCombatLockdown()
            inGroup  = IsInGroup()
            RefreshEquipped()
            RefreshCoachingAura()
            Evaluate()
        end)
        return
    end

    -- ── Pet battle ───────────────────────────────────────────
    if event == "PET_BATTLE_OPENING_START" then
        HideWarning()
        return
    end

    -- ── Entered combat ───────────────────────────────────────
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        CancelExpiryTimer()
        HideWarning()
        return
    end

    -- ── Equipment change ─────────────────────────────────────
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshEquipped()
        Evaluate()
        return
    end

    -- ── Aura change — only care about player ─────────────────
    if event == "UNIT_AURA" then
        if arg1 ~= "player" then return end
        RefreshCoachingAura()  -- update cached expiry timestamp
        Evaluate()
        return
    end

    -- ── Left combat ──────────────────────────────────────────
    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end

    -- ── Group change — debounced ──────────────────────────────
    if event == "GROUP_ROSTER_UPDATE" then
        inGroup = IsInGroup()
    end

    -- ── Everything else (PLAYER_REGEN_ENABLED, PET_BATTLE_CLOSE, etc.) ─
    Evaluate()
end)

-- ============================================================
--  Slash commands
-- ============================================================
SLASH_CWT1 = "/cwt"
SlashCmdList["CWT"] = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "config" then
        -- Show the warning as a preview so the user can drag it into place.
        -- Right-clicking locks it and ends the preview.
        if CWTDB then
            CWTDB.locked = false
        end
        previewMode = true
        CWT:Show()
        print("|cffff9900[CWT]|r " .. L.SLASH_CONFIG_MSG)

    elseif cmd == "debug" then
        local rem = CoachingRemaining()
        print("|cffff9900[CWT Debug]|r " .. L.DBG_HEADER)
        print(L.DBG_EQUIPPED .. tostring(whistleEquipped))
        print(L.DBG_COMBAT .. tostring(inCombat))
        print(L.DBG_REMAINING .. string.format("%.0f", rem) .. L.DBG_REMAINING_UNIT)
        print(L.DBG_WARN .. tostring(warnActive))
        print(L.DBG_VISIBLE .. tostring(CWT:IsShown()))
        print(L.DBG_LOCKED .. tostring(CWTDB and CWTDB.locked))

    else
        print("|cffff9900[CWT]|r " .. L.SLASH_HELP_CONFIG)
        print("|cffff9900[CWT]|r " .. L.SLASH_HELP_DEBUG)
    end
end
