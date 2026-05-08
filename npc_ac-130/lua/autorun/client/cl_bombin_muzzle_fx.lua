if not CLIENT then return end

-- ============================================================
-- AC-130 MUZZLE FX
-- "bombin_muzzle_flash"      -> GAU / 25mm
-- "bombin_muzzle_flash_40mm" -> 40mm Bofors
--
-- Bloom + flame: track the plane entity each frame (entindex sent)
--   so the flash stays on the barrel, not floating at fire-time pos.
-- Smoke: intentionally stays at world-space fire position and drifts
--   upward — gun smoke should NOT follow the plane.
-- Size: distance-adaptive with high caps so it reads from ground
--   observers looking up at ~6000+ unit altitude.
-- ============================================================

local mat_flash = Material("effects/muzzleflash1")
local mat_flame = Material("effects/muzzleflash4")
local mat_smoke = Material("particle/particle_smokegrenade")

local muzzle_flashes    = {}   -- GAU bloom+flame  { entIdx, localPos, expire, fexpire }
local smoke_particles   = {}   -- GAU smoke quads  (world-space, intentional)
local flash40_entries   = {}   -- 40mm bloom+flame { entIdx, localPos, expire, fexpire }
local smoke40_particles = {}   -- 40mm smoke quads (world-space)

-- ============================================================
-- GAU / 25mm
-- ============================================================
net.Receive("bombin_muzzle_flash", function()
    local entIdx   = net.ReadUInt(16)
    local localPos = net.ReadVector()   -- muzzle in LOCAL space
    local now      = UnPredictedCurTime()
    local firePos  = net.ReadVector()   -- world pos at fire time (for smoke)

    muzzle_flashes[#muzzle_flashes + 1] = {
        entIdx   = entIdx,
        localPos = localPos,
        firePos  = firePos,
        expire   = now + 0.08,
        fexpire  = now + 0.05,
    }

    -- Sparks at world fire pos
    local ed = EffectData()
    ed:SetOrigin(firePos)
    ed:SetNormal(Vector(0, 0, -1))
    ed:SetScale(2.4)
    ed:SetMagnitude(2)
    ed:SetRadius(16)
    util.Effect("ManhackSparks", ed)

    -- Smoke: 8 puffs, 1.4 s, dark, world-space drift
    for i = 1, 8 do
        smoke_particles[#smoke_particles + 1] = {
            pos    = firePos + Vector(math.Rand(-6,6), math.Rand(-6,6), math.Rand(0,8)),
            vel    = Vector(math.Rand(-8,8), math.Rand(-8,8), math.Rand(18,40)),
            born   = now + (i - 1) * 0.04,
            expire = now + (i - 1) * 0.04 + 1.4,
            size   = math.Rand(14, 28),
        }
    end
end)

-- ============================================================
-- 40mm Bofors
-- ============================================================
net.Receive("bombin_muzzle_flash_40mm", function()
    local entIdx   = net.ReadUInt(16)
    local localPos = net.ReadVector()
    local now      = UnPredictedCurTime()
    local firePos  = net.ReadVector()

    flash40_entries[#flash40_entries + 1] = {
        entIdx   = entIdx,
        localPos = localPos,
        firePos  = firePos,
        expire   = now + 0.12,
        fexpire  = now + 0.075,
    }

    local ed = EffectData()
    ed:SetOrigin(firePos)
    ed:SetNormal(Vector(0, 0, -1))
    ed:SetScale(3.6)
    ed:SetMagnitude(4)
    ed:SetRadius(28)
    util.Effect("ManhackSparks", ed)

    local ed2 = EffectData()
    ed2:SetOrigin(firePos + Vector(math.Rand(-12,12), math.Rand(-12,12), math.Rand(-4,4)))
    ed2:SetNormal(Vector(0, 0, -1))
    ed2:SetScale(2.2)
    ed2:SetMagnitude(3)
    ed2:SetRadius(18)
    util.Effect("ManhackSparks", ed2)

    -- Smoke: 16 puffs, 2.4 s, very dark, bigger quads
    for i = 1, 16 do
        smoke40_particles[#smoke40_particles + 1] = {
            pos    = firePos + Vector(math.Rand(-10,10), math.Rand(-10,10), math.Rand(0,12)),
            vel    = Vector(math.Rand(-12,12), math.Rand(-12,12), math.Rand(22,55)),
            born   = now + (i - 1) * 0.035,
            expire = now + (i - 1) * 0.035 + 2.4,
            size   = math.Rand(32, 64),
        }
    end
end)

-- Helper: get current world muzzle pos, falls back to fire-time pos
local function GetLivePos(f)
    local ent = Entity(f.entIdx)
    if IsValid(ent) and f.localPos then
        return ent:LocalToWorld(f.localPos)
    end
    return f.firePos
end

-- ============================================================
-- RENDER
-- ============================================================
hook.Add("PostDrawTranslucentRenderables", "bombin_muzzle_fx_draw", function(depth, skybox)
    if depth or skybox then return end

    local ct  = UnPredictedCurTime()
    local eye = EyePos()

    -- GAU SMOKE (world-space, intentional drift)
    if #smoke_particles > 0 then
        render.SetMaterial(mat_smoke)
        local keep = {}
        for _, s in ipairs(smoke_particles) do
            if ct < s.born then keep[#keep + 1] = s continue end
            if ct > s.expire then continue end
            local life = ct - s.born
            local frac = life / (s.expire - s.born)
            local alpha
            if     frac < 0.15 then alpha = (frac / 0.15) * 145
            elseif frac < 0.70 then alpha = 145
            else                     alpha = (1 - (frac - 0.70) / 0.30) * 145 end
            local sz      = s.size * (1 + frac * 2.5)
            local drawPos = s.pos + s.vel * life
            render.DrawSprite(drawPos, sz, sz, Color(40, 36, 34, alpha))
            keep[#keep + 1] = s
        end
        smoke_particles = keep
    end

    -- 40mm SMOKE
    if #smoke40_particles > 0 then
        render.SetMaterial(mat_smoke)
        local keep = {}
        for _, s in ipairs(smoke40_particles) do
            if ct < s.born then keep[#keep + 1] = s continue end
            if ct > s.expire then continue end
            local life = ct - s.born
            local frac = life / (s.expire - s.born)
            local alpha
            if     frac < 0.12 then alpha = (frac / 0.12) * 170
            elseif frac < 0.65 then alpha = 170
            else                     alpha = (1 - (frac - 0.65) / 0.35) * 170 end
            local sz      = s.size * (1 + frac * 3.2)
            local drawPos = s.pos + s.vel * life
            render.DrawSprite(drawPos, sz, sz, Color(28, 24, 22, alpha))
            keep[#keep + 1] = s
        end
        smoke40_particles = keep
    end

    -- GAU BLOOM + FLAME  (tracks plane)
    if #muzzle_flashes > 0 then
        local keep = {}

        render.SetMaterial(mat_flash)
        for _, f in ipairs(muzzle_flashes) do
            if ct > f.expire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            -- Size scales aggressively with distance so it reads at altitude
            -- min 300 at close range, grows to 2000 at 8000 units
            local sz = math.Clamp(300 + dist * 0.22, 300, 2000)
            render.DrawSprite(wpos, sz, sz, Color(255, 220, 100, 255))
            keep[#keep + 1] = f
        end

        render.SetMaterial(mat_flame)
        for _, f in ipairs(muzzle_flashes) do
            if ct > f.fexpire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local base = math.Clamp(300 + dist * 0.22, 300, 2000)
            local w    = base * 3.2   -- 2x the old value
            local h    = base * 1.4
            render.DrawSprite(wpos, w, h, Color(255, 200, 80, 230))
            render.DrawSprite(wpos, w * 0.35, h * 0.35, Color(255, 255, 220, 255))
        end

        muzzle_flashes = keep
    end

    -- 40mm BLOOM + FLAME  (tracks plane)
    if #flash40_entries > 0 then
        local keep = {}

        render.SetMaterial(mat_flash)
        for _, f in ipairs(flash40_entries) do
            if ct > f.expire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local sz   = math.Clamp(900 + dist * 0.66, 900, 6000)
            render.DrawSprite(wpos, sz, sz, Color(255, 160, 40, 255))
            local szc  = math.Clamp(1300 + dist * 0.96, 1300, 8000)
            render.DrawSprite(wpos + Vector(0,0,10), szc, szc, Color(255, 120, 20, 90))
            keep[#keep + 1] = f
        end

        render.SetMaterial(mat_flame)
        for _, f in ipairs(flash40_entries) do
            if ct > f.fexpire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local base = math.Clamp(600 + dist * 0.44, 600, 4000)
            local w    = base * 2.56
            local h    = base * 1.12
            render.DrawSprite(wpos, w, h, Color(255, 140, 30, 240))
            render.DrawSprite(wpos, w * 0.40, h * 0.40, Color(255, 240, 180, 255))
            render.DrawSprite(wpos, w * 0.70, h * 0.70, Color(255, 210, 120, 180))
        end

        flash40_entries = keep
    end
end)
