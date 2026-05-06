-- Realm: CLIENT
-- Draws a JASSM bay counter for the nearest AC-130 support plane.
-- Only visible when a plane entity exists in the world.
-- Uses NWInt "JASSM_Spent" (missiles launched) and "JASSM_Max" (bay capacity).

local ICON_SIZE   = 18
local ICON_GAP    = 6
local PANEL_PAD   = 12
local PANEL_H     = 48
local CORNER_R    = 6
local FADE_DIST   = 8000   -- start fading beyond this distance (hammer units)
local MAX_DIST    = 14000  -- fully invisible beyond this distance

-- Pre-create fonts once.
local FONT_LABEL = "BombinJASSM_Label"
local FONT_TITLE = "BombinJASSM_Title"
surface.CreateFont(FONT_TITLE, { font = "Roboto", size = 13, weight = 700, antialias = true })
surface.CreateFont(FONT_LABEL, { font = "Roboto", size = 11, weight = 400, antialias = true })

-- Colours
local COL_BG        = Color(10,  10,  10,  180)
local COL_BORDER    = Color(255, 255, 255, 40)
local COL_READY     = Color(80,  220, 120, 255)   -- missile available
local COL_SPENT     = Color(60,  60,  60,  200)   -- missile fired / empty
local COL_TEXT      = Color(220, 220, 220, 255)
local COL_TEXT_DIM  = Color(140, 140, 140, 255)

-- Cached missile icon path (uses a simple rounded rectangle drawn by code).
-- We draw the missile glyphs entirely via surface calls for zero asset dependency.

local function DrawMissileGlyph(x, y, w, h, fired)
    local col = fired and COL_SPENT or COL_READY
    -- Body
    draw.RoundedBox(3, x, y + math.floor(h * 0.3), w, math.floor(h * 0.4), col)
    -- Nose cone
    surface.SetDrawColor(col)
    local noseH = math.floor(h * 0.25)
    local cx    = x + math.floor(w / 2)
    surface.DrawLine(cx - 2, y + math.floor(h * 0.3), cx, y + math.floor(h * 0.3) - noseH)
    surface.DrawLine(cx + 2, y + math.floor(h * 0.3), cx, y + math.floor(h * 0.3) - noseH)
    -- Fins
    local finY = y + math.floor(h * 0.7) - 2
    surface.DrawLine(x,     finY, x - 3,  y + h)
    surface.DrawLine(x + w, finY, x + w + 3, y + h)
end

hook.Add("HUDPaint", "BombinJASSmCounter", function()
    -- Find the closest valid support plane.
    local plane = nil
    local bestDist = MAX_DIST
    local localPos = LocalPlayer():GetPos()

    for _, ent in ipairs(ents.FindByClass("ent_bombin_support_plane")) do
        if not IsValid(ent) then continue end
        local d = localPos:Distance(ent:GetPos())
        if d < bestDist then
            bestDist = d
            plane    = ent
        end
    end

    if not IsValid(plane) then return end

    local spent = plane:GetNWInt("JASSM_Spent", 0)
    local maxM  = plane:GetNWInt("JASSM_Max",   6)
    if maxM < 1 then return end

    -- Distance-based alpha fade.
    local alpha = 1
    if bestDist > FADE_DIST then
        alpha = 1 - math.Clamp((bestDist - FADE_DIST) / (MAX_DIST - FADE_DIST), 0, 1)
    end
    if alpha <= 0 then return end

    -- Panel sizing.
    local totalIcons = maxM
    local panelW     = PANEL_PAD * 2 + totalIcons * ICON_SIZE + (totalIcons - 1) * ICON_GAP
    local scrW, scrH = ScrW(), ScrH()
    local panelX     = scrW - panelW - 20
    local panelY     = scrH - PANEL_H - 20 - 60  -- sits above the health bar area

    local a = math.floor(alpha * 255)

    -- Background panel.
    local bg = Color(COL_BG.r, COL_BG.g, COL_BG.b, math.floor(COL_BG.a * alpha))
    draw.RoundedBox(CORNER_R, panelX, panelY, panelW, PANEL_H, bg)
    -- Border
    surface.SetDrawColor(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, math.floor(40 * alpha))
    surface.DrawOutlinedRect(panelX, panelY, panelW, PANEL_H, 1)

    -- Title
    surface.SetFont(FONT_TITLE)
    surface.SetTextColor(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a)
    surface.SetTextPos(panelX + PANEL_PAD, panelY + 4)
    surface.DrawText("JASSM BAY")

    -- Stock label  e.g.  "4 / 6"
    local remaining = maxM - spent
    local labelStr  = remaining .. " / " .. maxM
    surface.SetFont(FONT_LABEL)
    local lw = surface.GetTextSize(labelStr)
    surface.SetTextColor(remaining > 0 and COL_TEXT.r or 180,
                         remaining > 0 and COL_TEXT.g or 60,
                         remaining > 0 and COL_TEXT.b or 60, a)
    surface.SetTextPos(panelX + panelW - PANEL_PAD - lw, panelY + 6)
    surface.DrawText(labelStr)

    -- Missile glyphs row.
    local glyphY = panelY + PANEL_H - ICON_SIZE - 8
    for i = 1, totalIcons do
        local gx    = panelX + PANEL_PAD + (i - 1) * (ICON_SIZE + ICON_GAP)
        local fired = (i <= spent)
        -- Alpha-scale the glyph colours inline.
        local col = fired and
            Color(COL_SPENT.r,  COL_SPENT.g,  COL_SPENT.b,  math.floor(COL_SPENT.a  * alpha)) or
            Color(COL_READY.r,  COL_READY.g,  COL_READY.b,  math.floor(COL_READY.a  * alpha))
        draw.RoundedBox(3, gx, glyphY + math.floor(ICON_SIZE * 0.3), ICON_SIZE, math.floor(ICON_SIZE * 0.4), col)
        -- Nose tip
        surface.SetDrawColor(col)
        local cx = gx + math.floor(ICON_SIZE / 2)
        surface.DrawLine(cx - 2, glyphY + math.floor(ICON_SIZE * 0.3),
                         cx,     glyphY + math.floor(ICON_SIZE * 0.3) - 4)
        surface.DrawLine(cx + 2, glyphY + math.floor(ICON_SIZE * 0.3),
                         cx,     glyphY + math.floor(ICON_SIZE * 0.3) - 4)
        -- Fin left
        surface.DrawLine(gx,              glyphY + math.floor(ICON_SIZE * 0.7),
                         gx - 3,          glyphY + ICON_SIZE)
        -- Fin right
        surface.DrawLine(gx + ICON_SIZE,  glyphY + math.floor(ICON_SIZE * 0.7),
                         gx + ICON_SIZE + 3, glyphY + ICON_SIZE)
    end
end)
