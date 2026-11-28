-- In a fight, the D-pad's left and right step the side offset while hold & drag
-- is held. Outside a fight OffsetKeys.lua takes the left stick and the D-pad
-- itself, but the game blocks that in combat (EnableGamePadStick/Button). Its
-- secure code may still change bindings there (forever branch
-- Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:546, SetBindingClick),
-- so the hold & drag key goes through a secure button whose snippet, when it's
-- pressed in a fight, points D-pad left and right at two step buttons; letting
-- go gives them back. The left stick's directions can't be bound this way: an
-- in-game test (DebugPadProbe.lua) saw none of them reach the addon.
local Camera = _G.GamepadCameraOffset
local OffsetKeys = Camera.OffsetKeys

local CombatDPad = {
    DRAG_BUTTON = "GamepadCameraOffsetSecureDrag",
    STEP_BUTTONS = {
        { key = "PADDLEFT", name = "GamepadCameraOffsetStepLeft", direction = -1 },
        { key = "PADDRIGHT", name = "GamepadCameraOffsetStepRight", direction = 1 },
    },
}
Camera.CombatDPad = CombatDPad

-- Runs in the game's restricted environment (self, button, down).
CombatDPad.SNIPPET = [[
    if down and PlayerInCombat() then
        self:SetBindingClick(true, "PADDLEFT", "GamepadCameraOffsetStepLeft", "LeftButton")
        self:SetBindingClick(true, "PADDRIGHT", "GamepadCameraOffsetStepRight", "LeftButton")
    elseif not down then
        self:ClearBindings()
    end
]]

local function keystate(down) return down and "down" or "up" end

for _, stepButton in ipairs(CombatDPad.STEP_BUTTONS) do
    local button = CreateFrame("Button", stepButton.name, UIParent)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetScript("OnClick", function(_, _, down) OffsetKeys.Step(stepButton.direction, keystate(down)) end)
end

local dragButton = CreateFrame("Button", CombatDPad.DRAG_BUTTON, UIParent, "SecureHandlerClickTemplate")
dragButton:RegisterForClicks("AnyDown", "AnyUp")
dragButton:SetAttribute("_onclick", CombatDPad.SNIPPET)
dragButton:HookScript("OnClick", function(_, _, down) OffsetKeys.Drag(keystate(down)) end)
CombatDPad.dragButton = dragButton

-- The keys bound to hold & drag click the secure button instead (override
-- bindings, out of combat only: the player's own bindings stay as they are).
local router = CreateFrame("Frame")
local routedKeys

local function routeDragKeys()
    if InCombatLockdown() then return router:RegisterEvent("PLAYER_REGEN_ENABLED") end
    router:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local keys = { GetBindingKey("GAMEPADCAMERAOFFSET_DRAG") }
    local keyList = table.concat(keys, " ")
    if keyList == routedKeys then return end   -- setting them fires UPDATE_BINDINGS again
    routedKeys = keyList
    ClearOverrideBindings(router)
    for _, key in ipairs(keys) do
        SetOverrideBindingClick(router, false, key, CombatDPad.DRAG_BUTTON, "LeftButton")
    end
end
CombatDPad.RouteDragKeys = routeDragKeys

router:RegisterEvent("PLAYER_LOGIN")
router:RegisterEvent("UPDATE_BINDINGS")
router:SetScript("OnEvent", routeDragKeys)
