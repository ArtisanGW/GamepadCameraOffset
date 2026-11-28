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
--          mouse works, and the D-pad through CombatDPad.lua. Any other
--          controller button let go ends it, so the controller can never stay
--          taken. With Stop at center on, it stops at the center (CenterStop.lua):
--          the mouse for a moment, the left stick until it's let go.
--   Left / Right: one step each press (the Step size slider); held, it keeps
--          going, so a controller button works the same. With Stop at center
--          on, a held step stops at the center: press again to go past it.
-- Each change goes through the slider's own setting, so the settings page,
-- the saved value and the camera all follow.
local Camera = _G.GamepadCameraOffset

local OffsetKeys = {
    DRAG_PERCENT_PER_SCREEN = 200,  -- dragging across the whole screen: the slider's whole range
    STICK_PERCENT_PER_SECOND = 100, -- the left stick pushed all the way
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

-- The key held now: { drag, value, lastX, stickX, controllerTaken, centerHold } for Hold & drag;
-- { direction, untilNext } while a step repeats (either key).
local held
local updater = CreateFrame("Frame")
updater:Hide()

local function sideValue()
    return tonumber(Camera.GetSettings().side) or Camera.DEFAULTS.side
end

local function clampSide(value)
    return Camera.Clamp(value, Camera.SIDE_MIN, Camera.SIDE_MAX, Camera.DEFAULTS.side)
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
    return Camera.Clamp(Camera.GetSettings().stepSize, Camera.STEP_SIZE_MIN, Camera.STEP_SIZE_MAX,
        Camera.DEFAULTS.stepSize)
end

local function step(direction)
    -- Back onto the steps first, so a dragged 37% goes to 40% or 20% (at 20%).
    local value, size = sideValue(), stepSize()
    local onStep = (direction > 0 and math.ceil or math.floor)(value / size) * size
    OffsetKeys.SetSide(onStep ~= value and onStep or value + direction * size)
    if held and held.drag then held.value = sideValue() end
end

-- A step, and whether it repeats while held: not once it's at the center
-- with Stop at center on, so the next press goes past it.
local function stepAndRepeat(direction)
    step(direction)
    held.direction = not Camera.CenterStop.StopsStep(sideValue()) and direction or nil
end

-- A step now, then again and again while held.
local function startStepping(direction)
    stepAndRepeat(direction)
    held.untilNext = OffsetKeys.REPEAT_DELAY
end

local function cursorX()
    return (GetCursorPosition())
end

-- The Drag speed slider, as a multiplier (1 = Normal).
local function dragSpeed()
    return Camera.Clamp(Camera.GetSettings().dragSpeed, Camera.DRAG_SPEED_MIN, Camera.DRAG_SPEED_MAX,
        Camera.DEFAULTS.dragSpeed) / 100
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

-- A drag's move, in percent before Drag speed; byStick: the left stick moved it.
local function dragBy(moved, byStick)
    held.value = Camera.CenterStop.Move(held, moved, dragSpeed(), clampSide, byStick)
    OffsetKeys.SetSide(held.value)
end

updater:SetScript("OnUpdate", function(_, elapsed)
    if not held then return release() end
    if held.drag then
        local x = cursorX()
        local stickPush = Camera.CenterStop.StickPush(held, held.stickX)
        local stickMoved = stickPush * OffsetKeys.STICK_PERCENT_PER_SECOND * elapsed
        local moved = (x - held.lastX) / screenWidth() * OffsetKeys.DRAG_PERCENT_PER_SCREEN + stickMoved
        held.lastX = x
        if moved ~= 0 then dragBy(moved, stickMoved ~= 0) end
    end
    if held.direction then
        held.untilNext = held.untilNext - elapsed
        if held.untilNext <= 0 then
            held.untilNext = OffsetKeys.REPEAT_INTERVAL
            stepAndRepeat(held.direction)
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
        .. "• Left, Right: a step each press; held, it keeps going until the center (with Stop at center)",
        true))
end
