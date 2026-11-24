-- Debug only, not for release (.pkgmeta). Answers one question: do override
-- bindings on the controller's left stick directions and D-pad reach our
-- buttons, or does the game keep them? If they reach us, a secure hold & drag
-- button can set them in combat too (RestrictedFrames.lua:546, SetBindingClick).
-- /gpco debug pad starts it (RUN_AT_LOGIN: a few seconds after each login): for PROBE_SECONDS
-- the keys below go to logging buttons, a timer shows the time left, then the
-- bindings are cleared and a reload box writes GamepadCameraOffsetDebugDB.padProbe.
local Camera = _G.GamepadCameraOffset

local DebugPadProbe = {
    RUN_AT_LOGIN = false,   -- true runs it after every login: a loop, since it ends with a reload
    START_DELAY = 3,
    PROBE_SECONDS = 15,
    KEYS = { "PADLSTICKLEFT", "PADLSTICKRIGHT", "PADDLEFT", "PADDRIGHT" },
}
Camera.DebugPadProbe = DebugPadProbe

local owner = CreateFrame("Frame")
local running = false
local presses

local banner = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
banner:SetPoint("TOP", UIParent, "TOP", 0, -120)
banner:Hide()

local function probeLog()
    if type(GamepadCameraOffsetDebugDB) ~= "table" then GamepadCameraOffsetDebugDB = {} end
    GamepadCameraOffsetDebugDB.padProbe = GamepadCameraOffsetDebugDB.padProbe or {}
    return GamepadCameraOffsetDebugDB.padProbe
end

local function record(text)
    local lines = probeLog()
    lines[#lines + 1] = string.format("%s %s", date("%H:%M:%S"), text)
end

-- One logging button per key, clicked by the override binding.
for _, key in ipairs(DebugPadProbe.KEYS) do
    local button = CreateFrame("Button", "GamepadCameraOffsetProbe" .. key, UIParent)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetScript("OnClick", function(_, _, down)
        if not running then return end
        presses[key] = (presses[key] or 0) + (down and 1 or 0)
        record(key .. (down and " down" or " up"))
    end)
end

local function finish()
    running = false
    if not InCombatLockdown() then ClearOverrideBindings(owner) end
    banner:Hide()
    local summary = {}
    for _, key in ipairs(DebugPadProbe.KEYS) do summary[#summary + 1] = key .. " " .. (presses[key] or 0) end
    record("done: " .. table.concat(summary, ", "))
    Camera.Popup.Show({ text = "Controller test done.\n\nReload to save what reached the addon.",
        buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

function DebugPadProbe.Start()
    if running then return end
    if InCombatLockdown() then return print("|cff88ccffgco debug|r pad probe: not in combat") end
    running, presses = true, {}
    record("start")
    for _, key in ipairs(DebugPadProbe.KEYS) do
        SetOverrideBindingClick(owner, true, key, "GamepadCameraOffsetProbe" .. key, "LeftButton")
    end
    local endTime = GetTime() + DebugPadProbe.PROBE_SECONDS
    banner:Show()
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        local left = endTime - GetTime()
        if left <= 0 then ticker:Cancel(); return finish() end
        local counts = {}
        for _, key in ipairs(DebugPadProbe.KEYS) do counts[#counts + 1] = key:gsub("^PAD", "") .. " " .. (presses[key] or 0) end
        banner:SetText(string.format("Controller test: %d s left\nPush the left stick left and right, then the D-pad left and right\n%s",
            math.ceil(left), table.concat(counts, "   ")))
    end)
end

owner:RegisterEvent("PLAYER_LOGIN")
owner:SetScript("OnEvent", function()
    if DebugPadProbe.RUN_AT_LOGIN then C_Timer.After(DebugPadProbe.START_DELAY, DebugPadProbe.Start) end
end)
