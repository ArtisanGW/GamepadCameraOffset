-- Debug only, not for release (.pkgmeta). Finds out whether moving the
-- WorldFrame (the frame the 3D world is drawn in) moves the picture up or
-- down, a vertical offset the camera CVars don't have. Blizzard moves it
-- itself to make room for its debug bars (Blizzard_SharedXML/DebugBarManager.lua).
-- For each of STEPS it puts the WorldFrame's top and bottom edges that many
-- screen pixels from the screen's own (up is positive), waits, saves what the
-- game took (the WorldFrame's edges, the game's aim point, the crosshair and
-- the target's nameplate) and takes a screenshot (the game's Screenshots
-- folder). Then it puts the WorldFrame back and shows a reload box that writes
-- GamepadCameraOffsetDebugDB.worldFrameProbe.
-- Runs by itself a few seconds after a login when RUN_ID changed (bump it to
-- measure again after the next reload); /gpco debug worldframe runs it now. A
-- fight stops it; the WorldFrame comes back, after a reload mid-run too.
local Camera = _G.GamepadCameraOffset

local DebugWorldFrameProbe = {
    RUN_ID = 1,
    START_SECONDS = 6,
    SETTLE_SECONDS = 2,
    AFTER_SHOT_SECONDS = 0.5,   -- the shot is taken before the WorldFrame moves on
    STEPS = {
        { name = "normal", top = 0, bottom = 0 },
        { name = "bottom 300 px below the screen", top = 0, bottom = -300 },
        { name = "bottom 600 px below the screen", top = 0, bottom = -600 },
        { name = "top 600 px above the screen", top = 600, bottom = 0 },
        { name = "bottom 300 px up, inside the screen", top = 0, bottom = 300 },
        { name = "normal again", top = 0, bottom = 0 },
    },
}
Camera.DebugWorldFrameProbe = DebugWorldFrameProbe

local probe   -- the run in progress, or nil
local putBackAfterCombat   -- the anchors to put back once the fight ends, or nil

local timerText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timerText:SetPoint("TOPLEFT", 12, -12)

local function getDebugStore()
    if type(GamepadCameraOffsetDebugDB) ~= "table" then GamepadCameraOffsetDebugDB = {} end
    return GamepadCameraOffsetDebugDB
end

-- The game's "Screen captured" line stays out of the next shot.
local savedActionStatusAlpha
local function hideScreenCapturedMessage(hidden)
    if not ActionStatus then return end
    if hidden then
        savedActionStatusAlpha = ActionStatus:GetAlpha()
        ActionStatus:SetAlpha(0)
    else
        ActionStatus:SetAlpha(savedActionStatusAlpha or 1)
    end
end

local function roundPixels(value)
    return math.floor(value + 0.5)
end

-- A region's center in screen pixels; restricted regions refuse to be measured.
local function centerInPixels(region)
    if not region then return nil end
    local succeeded, result = pcall(function()
        local x, y = region:GetCenter()
        if not x then return nil end
        local scale = region:GetEffectiveScale()
        return { x = roundPixels(x * scale), y = roundPixels(y * scale) }
    end)
    if not succeeded then return { error = tostring(result) } end
    return result
end

local function worldFrameEdgesInPixels()
    local scale = WorldFrame:GetEffectiveScale()
    return { top = roundPixels(WorldFrame:GetTop() * scale), bottom = roundPixels(WorldFrame:GetBottom() * scale),
        left = roundPixels(WorldFrame:GetLeft() * scale), right = roundPixels(WorldFrame:GetRight() * scale) }
end

local function gameAimPoint()
    local succeeded, x, y = pcall(GetCursorCenterPosition)
    if not succeeded or not x then return nil end
    return { x = roundPixels(x), y = roundPixels(y) }
end

local function targetNameplate()
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
    local succeeded, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    return succeeded and nameplate or nil
end

-- The WorldFrame's anchors as the game set them, by name so they survive a reload.
local function readAnchors()
    local anchors = {}
    for index = 1, WorldFrame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = WorldFrame:GetPoint(index)
        anchors[index] = { point = point, relativeTo = relativeTo and relativeTo:GetName() or nil,
            relativePoint = relativePoint, x = x, y = y }
    end
    return anchors
end

local function placeWorldFrame(topPixels, bottomPixels)
    local scale = WorldFrame:GetEffectiveScale()
    WorldFrame:ClearAllPoints()
    WorldFrame:SetPoint("TOPLEFT", 0, topPixels / scale)
    WorldFrame:SetPoint("BOTTOMRIGHT", 0, bottomPixels / scale)
end

local function setAnchors(anchors)
    WorldFrame:ClearAllPoints()
    for _, anchor in ipairs(anchors) do
        local relativeTo = anchor.relativeTo and _G[anchor.relativeTo] or nil
        WorldFrame:SetPoint(anchor.point, relativeTo, anchor.relativePoint, anchor.x, anchor.y)
    end
end

-- In a fight the WorldFrame may be locked (nameplates are its children): then
-- it's put back once the fight ends.
local function putWorldFrameBack(run)
    if run.anchorsToRestore == nil then return end
    local anchors = run.anchorsToRestore
    run.anchorsToRestore = nil
    if InCombatLockdown() then
        putBackAfterCombat = anchors
        return
    end
    local succeeded, errorMessage = pcall(setAnchors, anchors)
    if not succeeded then geterrorhandler()(errorMessage) end
end

local function finish(stopReason)
    local run = probe
    probe = nil
    run.stopped = stopReason
    run.runID = DebugWorldFrameProbe.RUN_ID
    putWorldFrameBack(run)
    run.edgesAfter = worldFrameEdgesInPixels()
    timerText:SetText("")
    hideScreenCapturedMessage(false)
    Camera.Popup.Show({ text = "WorldFrame measured.\n\nReload to save it.",
        buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

local function measure(index)
    if not probe then return end
    local step = DebugWorldFrameProbe.STEPS[index]
    if step == nil then return finish() end
    local placed, errorMessage = pcall(placeWorldFrame, step.top, step.bottom)
    local secondsLeft = (#DebugWorldFrameProbe.STEPS - index + 1)
        * (DebugWorldFrameProbe.SETTLE_SECONDS + DebugWorldFrameProbe.AFTER_SHOT_SECONDS)
    timerText:SetText(string.format("WorldFrame test: %d s left. Don't move.", math.ceil(secondsLeft)))
    C_Timer.After(DebugWorldFrameProbe.SETTLE_SECONDS, function()
        if not probe then return end
        probe.shots[#probe.shots + 1] = {
            name = step.name,
            top = step.top,
            bottom = step.bottom,
            placed = placed,
            error = not placed and tostring(errorMessage) or nil,
            edges = worldFrameEdgesInPixels(),
            aimPoint = gameAimPoint(),
            crosshair = _G.GamepadReticle and _G.GamepadReticle:IsShown() and centerInPixels(_G.GamepadReticle) or nil,
            targetNameplate = centerInPixels(targetNameplate()),
            zoom = GetCameraZoom(),
            time = date("%H:%M:%S"),
        }
        Screenshot()
        C_Timer.After(DebugWorldFrameProbe.AFTER_SHOT_SECONDS, function() measure(index + 1) end)
    end)
end

function DebugWorldFrameProbe.Start()
    if probe then return end
    if InCombatLockdown() then return print("|cff88ccffgpco debug|r WorldFrame probe: not in combat") end
    local isProtected, isExplicitlyProtected = WorldFrame:IsProtected()
    local settings = Camera.GetSettings()
    probe = {
        time = date("%Y-%m-%d %H:%M:%S"),
        anchorsToRestore = readAnchors(),
        anchorsBefore = readAnchors(),
        edgesBefore = worldFrameEdgesInPixels(),
        isProtected = isProtected or false,
        isExplicitlyProtected = isExplicitlyProtected or false,
        screenHeight = roundPixels(GetScreenHeight() * UIParent:GetEffectiveScale()),
        cameraFov = Camera.GetCVar("cameraFov"),
        side = settings.side,
        tilt = settings.tilt,
        shots = {},
    }
    getDebugStore().worldFrameProbe = probe
    hideScreenCapturedMessage(true)
    measure(1)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- A reload during a run may have left the WorldFrame moved: put it back.
        local lastRun = getDebugStore().worldFrameProbe
        if lastRun then putWorldFrameBack(lastRun) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        local lastRun = getDebugStore().worldFrameProbe
        if lastRun and lastRun.runID == DebugWorldFrameProbe.RUN_ID then return end
        timerText:SetText(string.format("WorldFrame test starts in %d s. Don't move.",
            DebugWorldFrameProbe.START_SECONDS))
        C_Timer.After(DebugWorldFrameProbe.START_SECONDS, DebugWorldFrameProbe.Start)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if probe then finish("combat") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if putBackAfterCombat then
            local anchors = putBackAfterCombat
            putBackAfterCombat = nil
            local succeeded, errorMessage = pcall(setAnchors, anchors)
            if not succeeded then geterrorhandler()(errorMessage) end
        end
    end
end)
