if not CLIENT then return end

-- ============================================================
-- AC-130 MUZZLE FX
-- Ported from AC-47 cl_ac47_fx.lua.
-- Listens on "bombin_muzzle_flash" (net string added in init.lua).
--
-- Three layered effects per muzzle event:
--   A. Smoke trail  -- ParticleEmitter quads, dark grey, upward drift, 0.8s
--   B. Sparks       -- util.Effect ManhackSparks, instant, bright
--   C. Cone flame   -- effects/muzzleflash4 elongated sprite, 0.035s
-- Plus the original round bloom (effects/muzzleflash1).
-- ============================================================

local mat_flash = Material("effects/muzzleflash1")
local mat_flame = Material("effects/muzzleflash4")
local mat_smoke = Material("particle/particle_smokegrenade")

local muzzle_flashes  = {}
local smoke_particles = {}

net.Receive("bombin_muzzle_flash", function()
    local pos = net.ReadVector()
    local now = UnPredictedCurTime()

    -- Flash + flame entry
    muzzle_flashes[#muzzle_flashes + 1] = {
        pos     = pos,
        expire  = now + 0.06,
        fexpire = now + 0.035,
    }

    -- Sparks -- bright white/yellow streaks, fall downward from muzzle
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetNormal(Vector(0, 0, -1))
    ed:SetScale(1.8)
    ed:SetMagnitude(2)
    ed:SetRadius(12)
    util.Effect("ManhackSparks", ed)

    -- Smoke quads -- 5 puffs per flash, staggered birth
    for i = 1, 5 do
        smoke_particles[#smoke_particles + 1] = {
            pos  = pos + Vector(
                       math.Rand(-6, 6),
                       math.Rand(-6, 6),
                       math.Rand(0, 8)
                   ),
            vel  = Vector(
                       math.Rand(-8, 8),
                       math.Rand(-8, 8),
                       math.Rand(18, 40)
                   ),
            born   = now + (i - 1) * 0.04,
            expire = now + (i - 1) * 0.04 + 0.8,
            size   = math.Rand(14, 28),
        }
    end
end)

hook.Add("PostDrawTranslucentRenderables", "bombin_muzzle_fx_draw", function(depth, skybox)
    if depth or skybox then return end

    local ct  = UnPredictedCurTime()
    local eye = EyePos()

    -- A. SMOKE
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
                alpha = (frac / 0.15) * 140
            elseif frac < 0.70 then
                alpha = 140
            else
                alpha = (1 - (frac - 0.70) / 0.30) * 140
            end

            local sz      = s.size * (1 + frac * 2.5)
            local drawPos = s.pos + s.vel * life
            render.DrawSprite(drawPos, sz, sz, Color(55, 50, 48, alpha))
            keep[#keep + 1] = s
        end
        smoke_particles = keep
    end

    -- B + C. FLASH + FLAME
    if #muzzle_flashes == 0 then return end
    local keep_flash = {}

    -- Round bloom
    render.SetMaterial(mat_flash)
    for _, f in ipairs(muzzle_flashes) do
        if ct > f.expire then continue end
        local sz = math.Clamp(120 + eye:Distance(f.pos) * 0.028, 120, 400)
        render.DrawSprite(f.pos, sz, sz, Color(255, 220, 100, 255))
        keep_flash[#keep_flash + 1] = f
    end

    -- Cone flame (shorter lifetime, elongated)
    render.SetMaterial(mat_flame)
    for _, f in ipairs(muzzle_flashes) do
        if ct > f.fexpire then continue end
        local base = math.Clamp(100 + eye:Distance(f.pos) * 0.022, 100, 320)
        local w    = base * 1.6
        local h    = base * 0.7
        render.DrawSprite(f.pos, w, h, Color(255, 200, 80, 230))
        render.DrawSprite(f.pos, w * 0.35, h * 0.35, Color(255, 255, 220, 255))
    end

    muzzle_flashes = keep_flash
end)
