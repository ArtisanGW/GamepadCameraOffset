-- A hint on the settings page: Gamepad Crosshair Customizer, a separate addon,
-- customizes the controller's crosshair (shape, size, color, border, an icon on
-- your target). Shown only when it isn't installed; its button opens the popup
-- (Popup.lua) with the download link selected to copy (the game can't open a web
-- page) and a Reload for once it's installed. The other
-- addon is named here only as text: nothing calls it or depends on it.
local Camera = _G.GamepadCameraOffset

local RelatedAddon = {
    NAME = "GamepadCrosshairCustomizer",
    TITLE = "Gamepad Crosshair Customizer",
    -- CurseForge's permanent short address for its project (redirects to its page).
    LINK = "https://www.curseforge.com/projects/1818557",
}
Camera.RelatedAddon = RelatedAddon

function RelatedAddon.Installed()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, RelatedAddon.NAME)
    return succeeded and exists == true
end

-- Its link to copy, and a Reload for once it's installed (Popup.lua).
function RelatedAddon.ShowLink()
    Camera.Popup.Show({
        text = "To get " .. RelatedAddon.TITLE .. ":\n"
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
        "Customizes the controller's crosshair:\n\n"
        .. "• Its shape, size, color and border\n"
        .. "• An icon on your target: its class, a raid marker\n\n"
        .. "A separate addon; this one works without it.", true))
end
