-- Keep character on screen (a checkbox, off until you turn it on): while you're
-- zoomed in, the side offset is lowered so your character stays on screen; zoom
-- back out and it goes back to the slider's.
-- The game doesn't say where your character is on screen, so the limit comes
-- from the zoom. Measured with DebugSideProbe.lua: your character moves across
-- the screen by side offset / zoom, and at 0.45 x zoom it sits about a fifth in
-- from the edge of a 21:9 screen (width / height 2.4). The game keeps the
-- screen's height in view and widens the view with the screen, so a narrower
-- screen gets a smaller limit.
-- GetCameraZoom is the zoom you asked for: when a wall pulls the camera in,
-- your character can still go past the edge.
local Camera = _G.GamepadCameraOffset

local KeepOnScreen = {
    ZOOM_SHARE = 0.45,          -- the most side offset, as a share of the zoom, on MEASURED_ASPECT
    MEASURED_ASPECT = 2.4,
    RESEND_YARDS = 0.01,        -- a smaller change than this isn't sent to the camera
}
Camera.KeepOnScreen = KeepOnScreen

local sliderYards = 0   -- the side offset the slider asks for, in yards
local sentYards = 0     -- what the camera has now

-- The most side offset that keeps your character on screen at this zoom.
function KeepOnScreen.MaxYards()
    local zoom = tonumber(GetCameraZoom()) or 0
    local aspect = GetScreenWidth() / GetScreenHeight()
    return zoom * KeepOnScreen.ZOOM_SHARE * aspect / KeepOnScreen.MEASURED_ASPECT
end

local function limit(yards)
    local maxYards = KeepOnScreen.MaxYards()
    return math.max(-maxYards, math.min(maxYards, yards))
end

-- Follows the zoom while the limit is on.
local zoomWatcher = CreateFrame("Frame")
zoomWatcher:Hide()
zoomWatcher:SetScript("OnUpdate", function()
    local yards = limit(sliderYards)
    if math.abs(yards - sentYards) < KeepOnScreen.RESEND_YARDS then return end
    sentYards = yards
    Camera.SetCVar(Camera.CVAR_OVER_SHOULDER, yards)
end)

-- The side offset the camera gets for the slider's yards: limited by the zoom
-- while the checkbox is on, and kept up to date as you zoom.
function KeepOnScreen.Yards(yards, turnedOn)
    sliderYards = yards
    sentYards = turnedOn and limit(yards) or yards
    zoomWatcher:SetShown(turnedOn and yards ~= 0)
    return sentYards
end

function KeepOnScreen.Stop()
    zoomWatcher:Hide()
end
