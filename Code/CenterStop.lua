-- Stop at center (a checkbox, off until you turn it on): a hold & drag that
-- reaches or crosses the center stops there, and stays until HOLD_PERCENT more
-- is moved (either way), with a short buzz on the controller, so you feel it's
-- centered. Moves are counted before Drag speed: the hold feels the same at any
-- speed. OffsetKeys.lua runs each drag move through CenterStop.Move.
-- The left stick stops there until it's let go (CenterStop.StickPush): a push
-- goes too fast for HOLD_PERCENT to be felt; the next push goes past it.
-- A held Left or Right step (a key, or the D-pad during hold & drag) stops
-- repeating at the center, with the same buzz: the next press goes past it,
-- so the center is easy to get back to without the settings.
local Camera = _G.GamepadCameraOffset

local CenterStop = {
    HOLD_PERCENT = 15,
    STICK_LET_GO = 0.15,         -- the left stick under this (0 to 1) counts as let go
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

-- A step that landed on value: true when it's the center and Stop at center
-- is on (then it buzzes), so the held step stops repeating there.
function CenterStop.StopsStep(value)
    if value ~= 0 or Camera.GetSettings().centerHold ~= true then return false end
    buzz()
    return true
end

-- The left stick's push (-1 to 1) a drag may use: none while the stick that
-- stopped at the center is still pushed (drag.stickWaits); let go, it's free.
function CenterStop.StickPush(drag, stickX)
    if drag.stickWaits then
        if math.abs(stickX) >= CenterStop.STICK_LET_GO then return 0 end
        drag.stickWaits = nil
    end
    return stickX
end

-- drag: the held drag ({ value, centerHold, stickWaits }); moved: this move in
-- percent, before speed (the Drag speed multiplier); byStick: the left stick
-- moved it. Returns the new side value, clamped by clampSide; updates
-- drag.centerHold, or drag.stickWaits for the stick.
function CenterStop.Move(drag, moved, speed, clampSide, byStick)
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
        if byStick then drag.stickWaits = true else drag.centerHold = CenterStop.HOLD_PERCENT end
        buzz()
        return 0
    end
    return after
end
