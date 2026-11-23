-- Stop at center (a checkbox, off until you turn it on): a hold & drag that
-- reaches or crosses the center stops there, and stays until HOLD_PERCENT more
-- is moved (either way), with a short buzz on the controller, so you feel it's
-- centered. Moves are counted before Drag speed: the hold feels the same at any
-- speed. OffsetKeys.lua runs each drag move through CenterStop.Move.
local Camera = _G.GamepadCameraOffset

local CenterStop = {
    HOLD_PERCENT = 15,
    VIBRATION = "High",          -- C_GamePad.SetVibration's type (see buzz)
    VIBRATION_INTENSITY = 0.5,
    VIBRATION_SECONDS = 0.06,
}
Camera.CenterStop = CenterStop

-- The game names no vibration types in its own code: "High" (the small motor)
-- is a guess, and a client or controller without it just stays still.
local function buzz()
    local gamePad = _G.C_GamePad
    if type(gamePad) ~= "table" or type(gamePad.SetVibration) ~= "function" then return end
    pcall(gamePad.SetVibration, CenterStop.VIBRATION, CenterStop.VIBRATION_INTENSITY)
    if type(gamePad.StopVibration) == "function" then
        C_Timer.After(CenterStop.VIBRATION_SECONDS, function() pcall(gamePad.StopVibration) end)
    end
end

-- drag: the held drag ({ value, centerHold }); moved: this move in percent,
-- before speed (the Drag speed multiplier). Returns the new side value, clamped
-- by clampSide; updates drag.centerHold.
function CenterStop.Move(drag, moved, speed, clampSide)
    if drag.centerHold then
        drag.centerHold = drag.centerHold - math.abs(moved)
        if drag.centerHold > 0 then return drag.value end
        moved = (moved > 0 and 1 or -1) * -drag.centerHold   -- what's left past the hold
        drag.centerHold = nil
    end
    local before = drag.value
    local after = clampSide(before + moved * speed)
    local crossed = before ~= 0 and (after == 0 or (before > 0) ~= (after > 0))
    if crossed and Camera.GetSettings().centerHold == true then
        drag.centerHold = CenterStop.HOLD_PERCENT
        buzz()
        return 0
    end
    return after
end
