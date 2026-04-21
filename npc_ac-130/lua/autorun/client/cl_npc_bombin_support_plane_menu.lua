-- ============================================================
--  AC-130U Control Panel
--  lua/autorun/client/cl_bombinplane_menu.lua
-- ============================================================

if not CLIENT then return end

-- ----------------------------------------
--  Color Palette
-- ----------------------------------------
local col_bg_panel      = Color(0,   0,   0,   255)
local col_section_title = Color(210, 210, 210, 255)
local col_accent        = Color(0,   180, 255, 255)

-- ----------------------------------------
--  Colored Section Banners
-- ----------------------------------------
local SECTION_COLORS = {
    ["NPC Call Settings"]    = Color(60,  120, 200, 120),
    ["Probability & Timing"] = Color(80,  160, 100, 120),
    ["Flight Behaviour"]     = Color(80,  180, 120, 120),
    ["Engagement Range"]     = Color(200, 140, 40,  120),
    ["Debug"]                = Color(100, 100, 110, 120),
    ["Manual Spawn"]         = Color(140, 80,  200, 120),
}

local function AddColoredCategory(panel, text)
    local bgColor = SECTION_COLORS[text]
    if not bgColor then
        panel:Help(text)
        return
    end

    local cat = vgui.Create("DPanel", panel)
    cat:SetTall(24)
    cat:Dock(TOP)
    cat:DockMargin(0, 8, 0, 4)
    cat.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, bgColor)
        surface.SetDrawColor(0, 0, 0, 35)
        surface.DrawOutlinedRect(0, 0, w, h)
        local textColor = (bgColor.r + bgColor.g + bgColor.b < 200)
            and Color(255, 255, 255, 255)
            or  Color(0,   0,   0,   255)
        draw.SimpleText(
            text, "DermaDefaultBold",
            8, h / 2,
            textColor,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
        )
    end
    panel:AddItem(cat)
end

-- ----------------------------------------
--  Console Command — manual test spawn
-- ----------------------------------------
concommand.Add("bombin_spawnplane", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("BombinSupportPlane_ManualSpawn")
    net.SendToServer()
end)

-- ----------------------------------------
--  Tab & Category Registration
-- ----------------------------------------
hook.Add("AddToolMenuTabs", "BombinSupportPlane_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "BombinSupportPlane_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "AC-130U", "AC-130U")
end)

-- ----------------------------------------
--  Tool Menu Population
-- ----------------------------------------
hook.Add("PopulateToolMenu", "BombinSupportPlane_ToolMenu", function()
    spawnmenu.AddToolMenuOption(
        "Bombin Support",
        "AC-130U",
        "npc_bombin_support_plane_settings",
        "AC-130U Settings",
        "", "",
        function(panel)
            panel:ClearControls()

            -- Header banner
            local header = vgui.Create("DPanel", panel)
            header:SetTall(32)
            header:Dock(TOP)
            header:DockMargin(0, 0, 0, 8)
            header.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, col_bg_panel)
                surface.SetDrawColor(col_accent)
                surface.DrawRect(0, h - 2, w, 2)
                draw.SimpleText(
                    "AC-130U Controller",
                    "DermaLarge",
                    8, h / 2,
                    col_section_title,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
                )
            end
            panel:AddItem(header)

            -- ─── NPC Call Settings ─────────────────────────────────
            AddColoredCategory(panel, "NPC Call Settings")
            panel:CheckBox("Enable AC-130U calls", "npc_bombinplane_enabled")

            -- ─── Probability & Timing ──────────────────────────────
            AddColoredCategory(panel, "Probability & Timing")
            panel:NumSlider("Call chance (per check)",  "npc_bombinplane_chance",   0,  1,   2)
            panel:NumSlider("Check interval (seconds)", "npc_bombinplane_interval", 1,  60,  0)
            panel:NumSlider("Call cooldown (seconds)",  "npc_bombinplane_cooldown", 10, 180, 0)
            panel:NumSlider("Delay after flare (s)",    "npc_bombinplane_delay",    1,  15,  0)
            panel:NumSlider("AC-130U lifetime (seconds)","npc_bombinplane_lifetime", 5,  120, 0)

            -- ─── Flight Behaviour ──────────────────────────────────
            AddColoredCategory(panel, "Flight Behaviour")
            panel:NumSlider("AC-130U speed (HU/s)",              "npc_bombinplane_speed",  100, 1200, 0)
            panel:NumSlider("Orbit radius (HU)",                 "npc_bombinplane_radius", 500, 8000, 0)
            panel:NumSlider("Preferred height above ground (HU)", "npc_bombinplane_height", 500, 6000, 0)

            -- ─── Engagement Range ──────────────────────────────────
            AddColoredCategory(panel, "Engagement Range")
            panel:NumSlider("Min distance (HU)", "npc_bombinplane_min_dist", 0,   1000, 0)
            panel:NumSlider("Max distance (HU)", "npc_bombinplane_max_dist", 500, 8000, 0)

            -- ─── Debug ─────────────────────────────────────────────
            AddColoredCategory(panel, "Debug")
            panel:CheckBox("Enable debug prints", "npc_bombinplane_announce")

            -- ─── Manual Spawn ──────────────────────────────────────
            AddColoredCategory(panel, "Manual Spawn")
            panel:Button("Spawn AC-130U now", "bombin_spawnplane")
        end
    )
end)
