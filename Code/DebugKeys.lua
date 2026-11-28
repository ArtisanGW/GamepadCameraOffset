-- Debug only, not for release (.pkgmeta). Watches hold & drag: shows at the top of
-- the screen what reaches the game (mouse and controller buttons, the binding's
-- key down/up, the cursor and the side value) and keeps the last lines in
-- GamepadCameraOffsetDebugDB.keyLog, written to disk on /reload.
-- Off at login; /gpco debug keys turns it on or off.
local Camera = _G.GamepadCameraOffset
local OffsetKeys = Camera.OffsetKeys

local DebugKeys = { LOG_LINES = 200, SAMPLE_SECONDS = 0.25 }
Camera.DebugKeys = DebugKeys

local shown = false
local dragHeld = false
local lastLine = "waiting"

local readout = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
readout:SetPoint("TOP", UIParent, "TOP", 0, -60)

local function keyLog()
    if type(GamepadCameraOffsetDebugDB) ~= "table" then GamepadCameraOffsetDebugDB = {} end
    GamepadCameraOffsetDebugDB.keyLog = GamepadCameraOffsetDebugDB.keyLog or {}
    return GamepadCameraOffsetDebugDB.keyLog
end

local function cursorX()
    local x = GetCursorPosition()
    return math.floor(x + 0.5)
end

local function sideValue()
    return Camera.GetSettings().side
end

local function bindingText()
    local first, second = GetBindingKey("GAMEPADCAMERAOFFSET_DRAG")
    return tostring(first) .. (second and (", " .. second) or "")
end

local function refresh()
    if not shown then return readout:Hide() end
    readout:Show()
    readout:SetText(string.format("hold & drag on: %s | held: %s | cursor x: %d | side: %s\n%s",
        bindingText(), tostring(dragHeld), cursorX(), tostring(sideValue()), lastLine))
end

local function log(text)
    lastLine = string.format("%.2f %s (cursor x %d, side %s)", GetTime(), text, cursorX(), tostring(sideValue()))
    local lines = keyLog()
    lines[#lines + 1] = lastLine
    while #lines > DebugKeys.LOG_LINES do table.remove(lines, 1) end
    refresh()
end

hooksecurefunc(OffsetKeys, "Drag", function(keystate)
    dragHeld = keystate == "down"
    log("binding fired: " .. tostring(keystate))
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GLOBAL_MOUSE_DOWN")
events:RegisterEvent("GLOBAL_MOUSE_UP")
pcall(events.RegisterEvent, events, "GAME_PAD_BUTTON_DOWN")
pcall(events.RegisterEvent, events, "GAME_PAD_BUTTON_UP")
events:SetScript("OnEvent", function(_, event, button)
    if event == "PLAYER_LOGIN" then
        log(string.format("login: binding set %s, GamePadEnable %s, BUTTON3 does %s",
            tostring(GetCurrentBindingSet()), tostring(GetCVar("GamePadEnable")),
            tostring(GetBindingAction("BUTTON3"))))
    elseif event:find("^GLOBAL_MOUSE") or button and tostring(button):find("STICK") then
        log(event .. " " .. tostring(button) .. " does " .. tostring(GetBindingAction(tostring(button))))
    end
end)

local sampler = CreateFrame("Frame")
sampler:Hide()
local untilSample = 0
sampler:SetScript("OnUpdate", function(_, elapsed)
    untilSample = untilSample - elapsed
    if untilSample > 0 then return end
    untilSample = DebugKeys.SAMPLE_SECONDS
    if dragHeld then log("held") else refresh() end
end)

function DebugKeys.Toggle()
    shown = not shown
    sampler:SetShown(shown)
    refresh()
    print("|cff88ccffgco debug|r key watch " .. (shown and "on" or "off"))
end
