-- Keys that move the side offset, bound in the game's Options > Key Bindings >
-- AddOns (Bindings.xml, category "ADDONS": the game's keybindings page puts a
-- binding under the section named by that global, forever branch
-- Blizzard_SettingsDefinitions_Frame/Keybindings.lua:219-252). None is bound
-- until you bind it.
--   Drag:  hold it and move the mouse left or right (a mouse button works too,
--          like the middle one); the whole screen's width sweeps the slider
--          from 100% left to 100% right.
--   Left / Right: one step each press (the slider's step); held, it keeps
--          going, so a controller button works the same.
-- Each change goes through the slider's own setting, so the settings page,
-- the saved value and the camera all follow.
local Camera = _G.GamepadCameraOffset

local OffsetKeys = {
    DRAG_PERCENT_PER_SCREEN = 200,  -- dragging across the whole screen: the slider's whole range
    REPEAT_DELAY = 0.4,             -- seconds a held Left/Right waits before it repeats
    REPEAT_INTERVAL = 0.08,         -- then seconds between steps
}
Camera.OffsetKeys = OffsetKeys

-- Binding names (Options > Key Bindings > AddOns).
BINDING_NAME_GAMEPADCAMERAOFFSET_DRAG = "Camera side: hold & drag"
BINDING_NAME_GAMEPADCAMERAOFFSET_LEFT = "Camera side: left"
BINDING_NAME_GAMEPADCAMERAOFFSET_RIGHT = "Camera side: right"

local held      -- the key held now: { drag = true, startX, startValue } or { direction, untilNext }
local updater = CreateFrame("Frame")
updater:Hide()

local function sideValue()
    return tonumber(Camera.GetSettings().side) or Camera.DEFAULTS.side
end

-- Sets the slider's value (clamped, whole percent) as the settings page would.
function OffsetKeys.SetSide(value)
    value = math.floor(math.max(Camera.SIDE_MIN, math.min(Camera.SIDE_MAX, value)) + 0.5)
    if value == sideValue() then return end
    local setting = Camera.sliderSettings and Camera.sliderSettings.side
    if setting and setting.SetValue then
        setting:SetValue(value)
    else
        Camera.GetSettings().side = value
        Camera.Apply()
    end
end

local function step(direction)
    -- Back onto the slider's steps first, so a dragged 37% goes to 40% or 35%.
    local value = sideValue()
    local onStep = (direction > 0 and math.ceil or math.floor)(value / Camera.SIDE_STEP) * Camera.SIDE_STEP
    OffsetKeys.SetSide(onStep ~= value and onStep or value + direction * Camera.SIDE_STEP)
end

local function cursorX()
    local x = GetCursorPosition()
    return x
end

-- The Drag speed slider, as a multiplier (1 = Normal).
local function dragSpeed()
    local percent = tonumber(Camera.GetSettings().dragSpeed) or Camera.DEFAULTS.dragSpeed
    return math.max(Camera.DRAG_SPEED_MIN, math.min(Camera.DRAG_SPEED_MAX, percent)) / 100
end

local function screenWidth()
    return GetScreenWidth() * UIParent:GetEffectiveScale()
end

local function release()
    held = nil
    updater:Hide()
end

updater:SetScript("OnUpdate", function(_, elapsed)
    if not held then return release() end
    if held.drag then
        local moved = (cursorX() - held.startX) / screenWidth()
        OffsetKeys.SetSide(held.startValue + moved * OffsetKeys.DRAG_PERCENT_PER_SCREEN * dragSpeed())
    else
        held.untilNext = held.untilNext - elapsed
        if held.untilNext <= 0 then
            held.untilNext = OffsetKeys.REPEAT_INTERVAL
            step(held.direction)
        end
    end
end)

-- Bindings.xml: keystate is "down" or "up" (runOnUp).
function OffsetKeys.Drag(keystate)
    if keystate ~= "down" then return release() end
    held = { drag = true, startX = cursorX(), startValue = sideValue() }
    updater:Show()
end

function OffsetKeys.Step(direction, keystate)
    if keystate ~= "down" then return release() end
    step(direction)
    held = { direction = direction, untilNext = OffsetKeys.REPEAT_DELAY }
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
        .. "• Hold & drag: hold it and move the mouse left or right\n"
        .. "• Left, Right: a step each press; held, it keeps going", true))
end
