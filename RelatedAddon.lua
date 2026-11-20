-- A hint on the settings page: Gamepad Reticle On Target, a separate addon, puts
-- the controller's reticle under your target's nameplate ("Crosshair on your
-- target" was part of this addon until 1.7.0). Shown only when it isn't
-- installed; its button opens the popup (Popup.lua) with the download link
-- selected to copy (the game can't open a web page) and a Reload for once it's
-- installed. If you had that setting on, the same popup opens once at login to
-- say where it went. The other addon is named here only as text: nothing calls
-- it or depends on it.
local Camera = _G.GamepadCameraOffset

local RelatedAddon = {
    NAME = "GamepadReticleOnTarget",
    TITLE = "Gamepad Reticle On Target",
    -- CurseForge's permanent short address for its project (redirects to its page).
    LINK = "https://www.curseforge.com/projects/1819101",
}
Camera.RelatedAddon = RelatedAddon

function RelatedAddon.Installed()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, RelatedAddon.NAME)
    return succeeded and exists == true
end

-- Its link to copy, and a Reload for once it's installed (Popup.lua).
function RelatedAddon.ShowLink(intro)
    Camera.Popup.Show({
        text = (intro or "") .. "To get " .. RelatedAddon.TITLE .. ":\n"
            .. "• Copy the link (Ctrl+C)\n"
            .. "• Install it\n"
            .. "• Reload",
        copyText = RelatedAddon.LINK,
        buttons = { { text = "Reload", reload = true }, { text = "Close" } },
    })
end

-- The settings page's button (GamepadCameraOffset.lua calls this while building it).
function Camera.AddRelatedAddonButton(layout)
    if RelatedAddon.Installed() then return end
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    layout:AddInitializer(CreateSettingsButtonInitializer(RelatedAddon.TITLE, "Get " .. RelatedAddon.TITLE,
        function() RelatedAddon.ShowLink() end,
        "Puts the controller's reticle just below your target's nameplate.\n\n"
        .. "It was \"Crosshair on your target\" here before 1.7.0.\n\n"
        .. "A separate addon; this one works without it.", true))
end

-- Once, at the first login after the update, for those who had it on.
RelatedAddon.eventFrame = CreateFrame("Frame")
RelatedAddon.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
RelatedAddon.eventFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not Camera.reticleMoved or RelatedAddon.Installed() then return end
    Camera.reticleMoved = nil
    RelatedAddon.ShowLink("Gamepad Camera Offset\n\n\"Crosshair on your target\" is now its own addon, "
        .. RelatedAddon.TITLE .. ". The camera settings stay here.\n\n")
end)
