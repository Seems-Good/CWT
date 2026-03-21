-- Locale/enUS.lua
local _, addon = ...
addon.L = {
    -- Warning display
    WARNING_TEXT        = "USE COACH'S WHISTLE",

    -- Tooltip
    TT_UNLOCK           = "Right-click to unlock",
    TT_DRAG             = "Left-drag to move",
    TT_LOCK             = "Right-click to lock",

    -- Lock/unlock chat messages
    MSG_LOCKED          = "Frame locked.",
    MSG_UNLOCKED        = "Frame unlocked \226\128\148 drag to move, right-click to lock.",

    -- Slash command messages
    SLASH_CONFIG_MSG    = "Drag the warning into position, then right-click to lock.",
    SLASH_HELP_CONFIG   = "/cwt config  \226\128\148  show & drag warning into place",
    SLASH_HELP_DEBUG    = "/cwt debug   \226\128\148  print current state",

    -- Debug labels
    DBG_HEADER          = "---",
    DBG_EQUIPPED        = "  whistleEquipped = ",
    DBG_COMBAT          = "  inCombat        = ",
    DBG_REMAINING       = "  coachingRemain  = ",
    DBG_REMAINING_UNIT  = "s",
    DBG_WARN            = "  warnActive      = ",
    DBG_VISIBLE         = "  frameVisible    = ",
    DBG_LOCKED          = "  locked          = ",
}
