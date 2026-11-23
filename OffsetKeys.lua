-- Keys that move the side offset, bound in the game's Options > Key Bindings >
-- AddOns (Bindings.xml, category "ADDONS": the game's keybindings page puts a
-- binding under the section named by that global, forever branch
-- Blizzard_SettingsDefinitions_Frame/Keybindings.lua:219-252). None is bound
-- until you bind it.
--   Hold & drag: while it's held (a mouse button works too, like the middle
--          one; on a controller, the right stick's click):
--          • the mouse left or right: the whole screen's width sweeps the
--            slider from 100% left to 100% right;
--          • the left stick: the further it's pushed, the faster it goes;
--          • the D-pad's left and right: a step each press, like the keys below.
--          The stick and the D-pad are taken from the game only while it's held
--          (EnableGamePadStick / EnableGamePadButton, as the game's soft cursor
--          does, Blizzard_GamepadSoftCursor/SoftCursor.lua:25), so the left
--          stick doesn't walk meanwhile. Both are blocked in combat: there the
--          mouse works, and the D-pad through CombatDPad.lua. Any other controller button let go ends it, so the
--          controller can never stay taken.
--   Left / Right: one step each press (the Step size slider); held, it keeps
--          going, so a controller button works the same.
-- Each change goes through the slider's own setting, so the settings page,
-- the saved value and the camera all follow.
local Camera = _G.GamepadCameraOffset

local OffsetKeys = {
    DRAG_PERCENT_PER_SCREEN = 200,  -- dragging across the whole screen: the slider's whole range
    STICK_PERCENT_PER_SECOND = 100, -- the left stick pushed all the way
    CENTER_HOLD_PERCENT = 15,       -- a drag stops at the center until moved this much more
    CENTER_VIBRATION = "High",      -- C_GamePad.SetVibration's type (see centerFeedback)
    CENTER_VIBRATION_INTENSITY = 0.5,
    CENTER_VIBRATION_SECONDS = 0.06,
    REPEAT_DELAY = 0.4,             -- seconds a held step waits before it repeats
    REPEAT_INTERVAL = 0.08,         -- then seconds between steps
    STICK = "Movement",             -- the game's name for the left stick
    PAD_STEPS = { PADDLEFT = -1, PADDRIGHT = 1 },
}
Camera.OffsetKeys = OffsetKeys

-- Binding names (Options > Key Bindings > AddOns).
BINDING_NAME_GAMEPADCAMERAOFFSET_DRAG = "Camera side: hold & drag"
BINDING_NAME_GAMEPADCAMERAOFFSET_LEFT = "Camera side: left"
BINDING_NAME_GAMEPADCAMERAOFFSET_RIGHT = "Camera side: right"

-- The key held now: { drag, value, lastX, stickX, controllerTaken } for Hold & drag;
-- { direction, untilNext } while a step repeats (either key).
local held
local updater = CreateFrame("Frame")
updater:Hide()

local function sideValue()
    return tonumber(Camera.GetSettings().side) or Camera.DEFAULTS.side
end

local function clampSide(value)
    return math.max(Camera.SIDE_MIN, math.min(Camera.SIDE_MAX, value))
end

-- Sets the slider's value (clamped, whole percent) as the settings page would.
function OffsetKeys.SetSide(value)
    value = math.floor(clampSide(value) + 0.5)
    if value == sideValue() then return end
    local setting = Camera.sliderSettings and Camera.sliderSettings.side
    if setting and setting.SetValue then
        setting:SetValue(value)
    else
        Camera.GetSettings().side = value
        Camera.Apply()
    end
end

-- The Step size slider, in percent.
local function stepSize()
    local percent = tonumber(Camera.GetSettings().stepSize) or Camera.DEFAULTS.stepSize
    return math.max(Camera.STEP_SIZE_MIN, math.min(Camera.STEP_SIZE_MAX, percent))
end

local function step(direction)
    -- Back onto the steps first, so a dragged 37% goes to 40% or 20% (at 20%).
    local value, size = sideValue(), stepSize()
    local onStep = (direction > 0 and math.ceil or math.floor)(value / size) * size
    OffsetKeys.SetSide(onStep ~= value and onStep or value + direction * size)
    if held and held.drag then held.value = sideValue() end
end

-- A step now, then again and again while held.
local function startStepping(direction)
    step(direction)
    held.direction, held.untilNext = direction, OffsetKeys.REPEAT_DELAY
end

local function cursorX()
    return (GetCursorPosition())
end

-- The Drag speed slider, as a multiplier (1 = Normal).
local function dragSpeed()
    local percent = tonumber(Camera.GetSettings().dragSpeed) or Camera.DEFAULTS.dragSpeed
    return math.max(Camera.DRAG_SPEED_MIN, math.min(Camera.DRAG_SPEED_MAX, percent)) / 100
end

local function screenWidth()
    return GetScreenWidth() * UIParent:GetEffectiveScale()
end

local function setControllerTaken(taken)
    if held then held.controllerTaken = taken end
    updater:EnableGamePadStick(taken)
    updater:EnableGamePadButton(taken)
end

local function release()
    if held and held.controllerTaken and not InCombatLockdown() then setControllerTaken(false) end
    held = nil
    updater:Hide()
end

-- A short buzz on the controller as the drag reaches the center. The game names
-- no vibration types in its own code: "High" (the small motor) is a guess, and
-- a client or controller without it just stays still.
local function centerFeedback()
    local gamePad = _G.C_GamePad
    if type(gamePad) ~= "table" or type(gamePad.SetVibration) ~= "function" then return end
    pcall(gamePad.SetVibration, OffsetKeys.CENTER_VIBRATION, OffsetKeys.CENTER_VIBRATION_INTENSITY)
    if type(gamePad.StopVibration) == "function" then
        C_Timer.After(OffsetKeys.CENTER_VIBRATION_SECONDS, function() pcall(gamePad.StopVibration) end)
    end
end

-- A drag's move (in percent before Drag speed). With Stop at center on, reaching
-- or crossing the center stops there, and it stays until CENTER_HOLD_PERCENT more is moved (either way),
-- so you feel it's centered; at any Drag speed the hold feels the same.
local function dragBy(moved)
    if held.centerHold then
        held.centerHold = held.centerHold - math.abs(moved)
        if held.centerHold > 0 then return end
        moved = (moved > 0 and 1 or -1) * -held.centerHold   -- what's left past the hold
        held.centerHold = nil
    end
    local before = held.value
    local after = clampSide(before + moved * dragSpeed())
    local centerHoldOn = Camera.GetSettings().centerHold == true   -- the Stop at center checkbox
    if centerHoldOn and before ~= 0 and (after == 0 or (before > 0) ~= (after > 0)) then
        after = 0
        held.centerHold = OffsetKeys.CENTER_HOLD_PERCENT
        centerFeedback()
    end
    held.value = after
    OffsetKeys.SetSide(after)
end

updater:SetScript("OnUpdate", function(_, elapsed)
    if not held then return release() end
    if held.drag then
        local x = cursorX()
        local moved = (x - held.lastX) / screenWidth() * OffsetKeys.DRAG_PERCENT_PER_SCREEN
            + held.stickX * OffsetKeys.STICK_PERCENT_PER_SECOND * elapsed
        held.lastX = x
        if moved ~= 0 then dragBy(moved) end
    end
    if held.direction then
        held.untilNext = held.untilNext - elapsed
        if held.untilNext <= 0 then
            held.untilNext = OffsetKeys.REPEAT_INTERVAL
            step(held.direction)
        end
    end
end)

-- The left stick while Hold & drag is held; the other sticks go on to the game.
updater:SetScript("OnGamePadStick", function(_, stick, x)
    if stick ~= OffsetKeys.STICK or not held then return true end
    held.stickX = x or 0
    return false
end)

updater:SetScript("OnGamePadButtonDown", function(_, button)
    local direction = OffsetKeys.PAD_STEPS[button]
    if direction and held then startStepping(direction) end
end)

updater:SetScript("OnGamePadButtonUp", function(_, button)
    if OffsetKeys.PAD_STEPS[button] then
        if held then held.direction = nil end
    else
        release()   -- the right stick's click let go (or any other button)
    end
end)

-- A fight starting: the controller goes back before it's locked.
updater:RegisterEvent("PLAYER_REGEN_DISABLED")
updater:SetScript("OnEvent", function()
    if held and held.controllerTaken then release() end
end)

-- Bindings.xml: keystate is "down" or "up" (runOnUp).
function OffsetKeys.Drag(keystate)
    if keystate ~= "down" then return release() end
    held = { drag = true, value = sideValue(), lastX = cursorX(), stickX = 0 }
    updater:Show()
    if not InCombatLockdown() then setControllerTaken(true) end
end

-- While hold & drag is held (CombatDPad.lua's D-pad in a fight), a step
-- leaves it held.
function OffsetKeys.Step(direction, keystate)
    local dragHeld = held and held.drag
    if keystate ~= "down" then
        if dragHeld then held.direction = nil; return end
        return release()
    end
    if not dragHeld then held = {} end
    startStepping(direction)
    updater:Show()
end

-- Opens Options > Key Bindings at its AddOns section, opened up, as the game's
-- own Ping page does for its keys (forever branch
-- Blizzard_SettingsDefinitions_Frame/PingSystem.lua:74-90).
function OffsetKeys.OpenBindings()
    local categoryID = Settings.KEYBINDINGS_CATEGORY_ID
    if not categoryID then return end
    local sectionName = ADDONS
    local category = SettingsPanel and SettingsPanel:GetCategory(categoryID)
    local layout = category and SettingsPanel:GetLayout(category)
    if layout and layout.EnumerateInitializers then
        for _, initializer in layout:EnumerateInitializers() do
            if initializer:GetName() == sectionName and initializer.data then initializer.data.expanded = true end
        end
    end
    Settings.OpenToCategory(categoryID, sectionName)
end

-- The settings page's button (GamepadCameraOffset.lua calls this while building it).
function OffsetKeys.AddButton(layout)
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    layout:AddInitializer(CreateSettingsButtonInitializer("Side offset keys", "Key Bindings",
        function() pcall(OffsetKeys.OpenBindings) end,
        "Bind keys that move the side offset.\n\n"
        .. "• Hold & drag: hold it, then the mouse, the left stick or the D-pad\n"
        .. "• Left, Right: a step each press; held, it keeps going", true))
end
