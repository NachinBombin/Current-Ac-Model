if not CLIENT then return end

-- ============================================================
-- AC-130 MUZZLE FX
-- "bombin_muzzle_flash"      -> GAU / 25mm
-- "bombin_muzzle_flash_40mm" -> 40mm Bofors
-- ============================================================

local mat_flash = Material("effects/muzzleflash1")
local mat_flame = Material("effects/muzzleflash4")
local mat_smoke = Material("particle/particle_smokegrenade")

-- ── shared tables ────────────────────────────────────────────
local muzzle_flashes    = {}   -- GAU bloom+flame entries
local smoke_particles   = {}   -- GAU smoke quads
local flash40_entries   = {}   -- 40mm bloom+flame entries
local smoke40_particles = {}   -- 40mm smoke quads

-- ============================================================
-- GAU / 25mm  (bombin_muzzle_flash)
-- Changes vs previous:
--   cone flame  2× bigger (base scale ×2, hot core ×2)
--   smoke       duration 1.4 s (was 0.8), darker (40,36,34), 8 puffs (was 5)
-- ============================================================
net.Receive("bombin_muzzle_flash", function()
    local pos = net.ReadVector()
    local now = UnPredictedCurTime()

    muzzle_flashes[#muzzle_flashes + 1] = {
        pos     = pos,
        expire  = now + 0.06,
        fexpire = now + 0.035,
    }

    -- Sparks
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, -1))
    ed:SetScale(1.8)
    ed:SetMagnitude(2)
    ed:SetRadius(12)
    util.Effect("ManhackSparks", ed)

    -- Smoke: 8 puffs, 1.4 s lifetime, darker colour
    for i = 1, 8 do
        smoke_particles[#smoke_particles + 1] = {
            pos  = pos + Vector(math.Rand(-6, 6), math.Rand(-6, 6), math.Rand(0, 8)),
            vel  = Vector(math.Rand(-8, 8), math.Rand(-8, 8), math.Rand(18, 40)),
            born   = now + (i - 1) * 0.04,
            expire = now + (i - 1) * 0.04 + 1.4,
            size   = math.Rand(14, 28),
        }
    end
end)

-- ============================================================
-- 40mm Bofors  (bombin_muzzle_flash_40mm)
-- Stacked effects:
--   bloom     3× wider than GAU, orange tint
--   cone      2× GAU but also ×1.6 on top of that (so ~3.2× GAU)
--   hot core  same scaling
--   smoke     16 puffs, 2.4 s, considerably darker (28,24,22)
--             start size 2× GAU, expand faster
--   extra     second bloom ring (corona) for differentiation
-- ============================================================
net.Receive("bombin_muzzle_flash_40mm", function()
    local pos = net.ReadVector()
    local now = UnPredictedCurTime()

    flash40_entries[#flash40_entries + 1] = {
        pos     = pos,
        expire  = now + 0.10,   -- stays visible longer than GAU
        fexpire = now + 0.065,
    }

    -- Heavy sparks: more, wider spread
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, -1))
    ed:SetScale(3.6)
    ed:SetMagnitude(4)
    ed:SetRadius(28)
    util.Effect("ManhackSparks", ed)

    -- Second spark burst offset slightly for scatter feel
    local ed2 = EffectData()
    ed2:SetOrigin(pos + Vector(math.Rand(-12,12), math.Rand(-12,12), math.Rand(-4,4)))
    ed2:SetNormal(Vector(0, 0, -1))
    ed2:SetScale(2.2)
    ed2:SetMagnitude(3)
    ed2:SetRadius(18)
    util.Effect("ManhackSparks", ed2)

    -- Smoke: 16 puffs, 2.4 s, very dark, bigger quads
    for i = 1, 16 do
        smoke40_particles[#smoke40_particles + 1] = {
            pos  = pos + Vector(math.Rand(-10, 10), math.Rand(-10, 10), math.Rand(0, 12)),
            vel  = Vector(math.Rand(-12, 12), math.Rand(-12, 12), math.Rand(22, 55)),
            born   = now + (i - 1) * 0.035,
            expire = now + (i - 1) * 0.035 + 2.4,
            size   = math.Rand(32, 64),   -- 2× GAU start size
        }
    end
end)

-- ============================================================
-- RENDER
-- ============================================================
hook.Add("PostDrawTranslucentRenderables", "bombin_muzzle_fx_draw", function(depth, skybox)
    if depth or skybox then return end

    local ct  = UnPredictedCurTime()
    local eye = EyePos()

    -- ── GAU SMOKE ──────────────────────────────────────────
    if #smoke_particles > 0 then
        render.SetMaterial(mat_smoke)
        local keep = {}
        for _, s in ipairs(smoke_particles) do
            if ct < s.born then keep[#keep + 1] = s continue end
            if ct > s.expire then continue end

            local life     = ct - s.born
            local duration = s.expire - s.born
            local frac     = life / duration

            local alpha
            if frac < 0.15 then
                alpha = (frac / 0.15) * 145
            elseif frac < 0.70 then
                alpha = 145
            else
                alpha = (1 - (frac - 0.70) / 0.30) * 145
            end

            local sz      = s.size * (1 + frac * 2.5)
            local drawPos = s.pos + s.vel * life
            render.DrawSprite(drawPos, sz, sz, Color(40, 36, 34, alpha))  -- darker than before
            keep[#keep + 1] = s
        end
        smoke_particles = keep
    end

    -- ── 40mm SMOKE ─────────────────────────────────────────
    if #smoke40_particles > 0 then
        render.SetMaterial(mat_smoke)
        local keep = {}
        for _, s in ipairs(smoke40_particles) do
            if ct < s.born then keep[#keep + 1] = s continue end
            if ct > s.expire then continue end

            local life     = ct - s.born
            local duration = s.expire - s.born
            local frac     = life / duration

            local alpha
            if frac < 0.12 then
                alpha = (frac / 0.12) * 170
            elseif frac < 0.65 then
                alpha = 170
            else
                alpha = (1 - (frac - 0.65) / 0.35) * 170
            end

            local sz      = s.size * (1 + frac * 3.2)   -- expands faster than GAU
            local drawPos = s.pos + s.vel * life
            render.DrawSprite(drawPos, sz, sz, Color(28, 24, 22, alpha))  -- considerably darker
            keep[#keep + 1] = s
        end
        smoke40_particles = keep
    end

    -- ── GAU BLOOM + FLAME ──────────────────────────────────
    if #muzzle_flashes > 0 then
        local keep_flash = {}

        render.SetMaterial(mat_flash)
        for _, f in ipairs(muzzle_flashes) do
            if ct > f.expire then continue end
            local sz = math.Clamp(120 + eye:Distance(f.pos) * 0.028, 120, 400)
            render.DrawSprite(f.pos, sz, sz, Color(255, 220, 100, 255))
            keep_flash[#keep_flash + 1] = f
        end

        -- Cone flame: 2× bigger than original
        render.SetMaterial(mat_flame)
        for _, f in ipairs(muzzle_flashes) do
            if ct > f.fexpire then continue end
            local base = math.Clamp(100 + eye:Distance(f.pos) * 0.022, 100, 320)
            local w    = base * 1.6 * 2.0   -- ×2 wider
            local h    = base * 0.7 * 2.0   -- ×2 taller
            render.DrawSprite(f.pos, w, h, Color(255, 200, 80, 230))
            -- hot core: also ×2
            render.DrawSprite(f.pos, w * 0.35, h * 0.35, Color(255, 255, 220, 255))
        end

        muzzle_flashes = keep_flash
    end

    -- ── 40mm BLOOM + FLAME ─────────────────────────────────
    if #flash40_entries > 0 then
        local keep40 = {}

        -- Outer corona ring (stacked, wider, orange)
        render.SetMaterial(mat_flash)
        for _, f in ipairs(flash40_entries) do
            if ct > f.expire then continue end
            local dist = eye:Distance(f.pos)
            -- Primary bloom: 3× GAU scale, orange
            local sz   = math.Clamp(360 + dist * 0.084, 360, 1200)
            render.DrawSprite(f.pos, sz, sz, Color(255, 160, 40, 255))
            -- Corona ring: even wider, dimmer, slightly offset upward
            local szc  = math.Clamp(520 + dist * 0.12, 520, 1600)
            render.DrawSprite(f.pos + Vector(0,0,10), szc, szc, Color(255, 120, 20, 90))
            keep40[#keep40 + 1] = f
        end

        -- Cone flame: ~3.2× GAU (2× GAU base ×1.6 again), deeper orange
        render.SetMaterial(mat_flame)
        for _, f in ipairs(flash40_entries) do
            if ct > f.fexpire then continue end
            local dist = eye:Distance(f.pos)
            local base = math.Clamp(200 + dist * 0.044, 200, 640)   -- 2× GAU base
            local w    = base * 1.6 * 1.6   -- extra ×1.6 stack
            local h    = base * 0.7 * 1.6
            render.DrawSprite(f.pos, w, h, Color(255, 140, 30, 240))
            -- bright hot core
            render.DrawSprite(f.pos, w * 0.40, h * 0.40, Color(255, 240, 180, 255))
            -- second stacked cone slightly smaller, whiter
            render.DrawSprite(f.pos, w * 0.70, h * 0.70, Color(255, 210, 120, 180))
        end

        flash40_entries = keep40
    end
end)
