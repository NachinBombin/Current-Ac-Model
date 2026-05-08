if not CLIENT then return end

-- ============================================================
-- AC-130 MUZZLE FX
-- GAU bloom/flame: 1/3 of previous sizes
-- 40mm bloom/flame: 2/3 of previous sizes
-- Smoke unchanged.
-- ============================================================

local mat_flash = Material("effects/muzzleflash1")
local mat_flame = Material("effects/muzzleflash4")
local mat_smoke = Material("particle/particle_smokegrenade")

local muzzle_flashes    = {}
local smoke_particles   = {}
local flash40_entries   = {}
local smoke40_particles = {}

net.Receive("bombin_muzzle_flash", function()
    local entIdx   = net.ReadUInt(16)
    local localPos = net.ReadVector()
    local now      = UnPredictedCurTime()
    local firePos  = net.ReadVector()

    muzzle_flashes[#muzzle_flashes + 1] = {
        entIdx   = entIdx,
        localPos = localPos,
        firePos  = firePos,
        expire   = now + 0.08,
        fexpire  = now + 0.05,
    }

    local ed = EffectData()
    ed:SetOrigin(firePos)
    ed:SetNormal(Vector(0, 0, -1))
    ed:SetScale(2.4)
    ed:SetMagnitude(2)
    ed:SetRadius(16)
    util.Effect("ManhackSparks", ed)

    for i = 1, 8 do
        smoke_particles[#smoke_particles + 1] = {
            entIdx   = entIdx,
            localPos = localPos + Vector(math.Rand(-6,6), math.Rand(-6,6), math.Rand(0,8)),
            vel      = Vector(math.Rand(-8,8), math.Rand(-8,8), math.Rand(18,40)),
            born     = now + (i - 1) * 0.04,
            expire   = now + (i - 1) * 0.04 + 1.4,
            size     = math.Rand(14, 28),
            fallback = firePos + Vector(math.Rand(-6,6), math.Rand(-6,6), math.Rand(0,8)),
        }
    end
end)

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

local function GetLivePos(f)
    local ent = Entity(f.entIdx)
    if IsValid(ent) then return ent:LocalToWorld(f.localPos) end
    return f.firePos
end

local function GetSmokeDrawPos(s, life)
    local ent = Entity(s.entIdx)
    local anchor = IsValid(ent) and ent:LocalToWorld(s.localPos) or s.fallback
    return anchor + s.vel * life
end

hook.Add("PostDrawTranslucentRenderables", "bombin_muzzle_fx_draw", function(depth, skybox)
    if depth or skybox then return end

    local ct  = UnPredictedCurTime()
    local eye = EyePos()

    -- GAU SMOKE (unchanged)
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
            render.DrawSprite(GetSmokeDrawPos(s, life), sz, sz, Color(40, 36, 34, alpha))
            keep[#keep + 1] = s
        end
        smoke_particles = keep
    end

    -- 40mm SMOKE (unchanged)
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
            render.DrawSprite(s.pos + s.vel * life, sz, sz, Color(28, 24, 22, alpha))
            keep[#keep + 1] = s
        end
        smoke40_particles = keep
    end

    -- GAU BLOOM + FLAME  — 1/3 of previous sizes
    -- Previous: base = Clamp(300 + dist*0.22, 300, 2000)
    -- Now:      base = Clamp(100 + dist*0.073, 100, 667)
    if #muzzle_flashes > 0 then
        local keep = {}
        render.SetMaterial(mat_flash)
        for _, f in ipairs(muzzle_flashes) do
            if ct > f.expire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local sz   = math.Clamp(100 + dist * 0.073, 100, 667)
            render.DrawSprite(wpos, sz, sz, Color(255, 220, 100, 255))
            keep[#keep + 1] = f
        end
        render.SetMaterial(mat_flame)
        for _, f in ipairs(muzzle_flashes) do
            if ct > f.fexpire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local base = math.Clamp(100 + dist * 0.073, 100, 667)
            local w    = base * 3.2
            local h    = base * 1.4
            render.DrawSprite(wpos, w, h, Color(255, 200, 80, 230))
            render.DrawSprite(wpos, w * 0.35, h * 0.35, Color(255, 255, 220, 255))
        end
        muzzle_flashes = keep
    end

    -- 40mm BLOOM + FLAME  — 2/3 of previous sizes
    -- Previous bloom:  Clamp(400 + dist*0.3,  400, 1600)
    -- Now:             Clamp(267 + dist*0.2,  267, 1067)
    -- Previous corona: Clamp(600 + dist*0.44, 600, 2200)
    -- Now:             Clamp(400 + dist*0.293, 400, 1467)
    -- Previous base:   Clamp(180 + dist*0.13, 180, 1000)
    -- Now:             Clamp(120 + dist*0.087, 120, 667)
    if #flash40_entries > 0 then
        local keep = {}
        render.SetMaterial(mat_flash)
        for _, f in ipairs(flash40_entries) do
            if ct > f.expire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local sz   = math.Clamp(267 + dist * 0.2,   267, 1067)
            render.DrawSprite(wpos, sz, sz, Color(255, 160, 40, 255))
            local szc  = math.Clamp(400 + dist * 0.293, 400, 1467)
            render.DrawSprite(wpos + Vector(0,0,10), szc, szc, Color(255, 120, 20, 90))
            keep[#keep + 1] = f
        end
        render.SetMaterial(mat_flame)
        for _, f in ipairs(flash40_entries) do
            if ct > f.fexpire then continue end
            local wpos = GetLivePos(f)
            local dist = eye:Distance(wpos)
            local base = math.Clamp(120 + dist * 0.087, 120, 667)
            local w    = base * 2.56
            local h    = base * 1.12
            render.DrawSprite(wpos, w, h, Color(255, 140, 30, 240))
            render.DrawSprite(wpos, w * 0.40, h * 0.40, Color(255, 240, 180, 255))
            render.DrawSprite(wpos, w * 0.70, h * 0.70, Color(255, 210, 120, 180))
        end
        flash40_entries = keep
    end
end)
