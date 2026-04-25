include("shared.lua")

-- ============================================================
-- PRECACHE — confirmed vanilla GMod PCFs only
-- fire_01.pcf     : fire_medium_02
-- burning_fx.pcf  : burning_engine_fire, fire_small_01, fire_small_02
-- ============================================================
game.AddParticles("particles/fire_01.pcf")
game.AddParticles("particles/burning_fx.pcf")

PrecacheParticleSystem("fire_medium_02")
PrecacheParticleSystem("burning_engine_fire")
PrecacheParticleSystem("fire_small_01")
PrecacheParticleSystem("fire_small_02")

-- ============================================================
-- SOUND BROADCAST
-- ============================================================
net.Receive("bombin_plane_sound", function()
    local path   = net.ReadString()
    local pos    = net.ReadVector()
    local level  = net.ReadUInt(8)
    local pitch  = net.ReadUInt(8)
    local volume = net.ReadFloat()
    sound.Play(path, pos, level, pitch, volume)
end)

-- ============================================================
-- DAMAGE STATE VISUALS
--
-- Each tier entry is a flat list of { particleName, localOffset }
-- All names are confirmed present in vanilla GMod base PCFs.
--
-- Tier 1 (~75% HP): small engine fire at centre — subtle
-- Tier 2 (~50% HP): engine fire + burning small flames on wings
-- Tier 3 (~25% HP): full burn — large fire centre, engine fires
--                   on both wings, small fires at nose & tail
-- ============================================================
local TIER_EMITTERS = {
    [1] = {
        { "fire_medium_02",     Vector(  0,   0,  20) },
    },
    [2] = {
        { "fire_medium_02",     Vector(  0,   0,  20) },
        { "burning_engine_fire",Vector( 80,   0,   0) },
        { "burning_engine_fire",Vector(-80,   0,   0) },
        { "fire_small_01",      Vector(  0,-100,  15) },
    },
    [3] = {
        { "fire_medium_02",     Vector(  0,   0,  25) },
        { "fire_medium_02",     Vector( 60,  30,   5) },
        { "burning_engine_fire",Vector( 90,   0,   0) },
        { "burning_engine_fire",Vector(-90,   0,   0) },
        { "fire_small_02",      Vector(  0, 130,  10) },
        { "fire_small_01",      Vector(  0,-130,  10) },
        { "fire_small_01",      Vector( 50, -60,   0) },
        { "fire_small_01",      Vector(-50, -60,   0) },
    },
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 1.0 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local PlaneStates = {}

-- ============================================================
-- BURST FX — util.Effect only, no PCF needed
-- ============================================================
local function SpawnBurstFX(ent, count)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    for _ = 1, count do
        local wPos = LocalToWorld(
            Vector(math.Rand(-120,120), math.Rand(-150,80), math.Rand(0,40)),
            Angle(0,0,0), pos, ang
        )
        local ed = EffectData()
        ed:SetOrigin(wPos)
        ed:SetScale(math.Rand(0.6, 1.2))
        ed:SetMagnitude(1)
        ed:SetRadius(50)
        util.Effect("Explosion", ed)

        local ed2 = EffectData()
        ed2:SetOrigin(wPos)
        ed2:SetNormal(Vector(0,0,1))
        ed2:SetScale(0.5)
        ed2:SetMagnitude(0.5)
        ed2:SetRadius(24)
        util.Effect("ManhackSparks", ed2)
    end
end

-- ============================================================
-- PARTICLE MANAGEMENT
-- ============================================================
local function StopParticles(state)
    if not state.particles then return end
    for _, p in ipairs(state.particles) do
        if IsValid(p) then p:StopEmission() end
    end
    state.particles = {}
end

local function ApplyFlameParticles(ent, state, tier)
    StopParticles(state)
    state.tier = tier
    if not IsValid(ent) or tier == 0 then return end

    local emitters = TIER_EMITTERS[tier]
    for _, em in ipairs(emitters) do
        local p = ent:CreateParticleEffect(em[1], PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(em[2]))
            table.insert(state.particles, { fx = p, offset = em[2] })
        end
    end

    state.nextBurst = CurTime() + (TIER_BURST_DELAY[tier] or 4)
end

-- ============================================================
-- NET
-- ============================================================
net.Receive("bombin_plane_damage_tier", function()
    local entIndex = net.ReadUInt(16)
    local tier     = net.ReadUInt(2)
    local ent      = Entity(entIndex)

    local state = PlaneStates[entIndex]
    if not state then
        state = { tier = 0, particles = {}, nextBurst = 0 }
        PlaneStates[entIndex] = state
    end

    if state.tier == tier then return end

    if IsValid(ent) then
        ApplyFlameParticles(ent, state, tier)
        if tier > 0 then SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1) end
    else
        state.tier         = tier
        state.pendingApply = true
    end
end)

-- ============================================================
-- THINK — re-sync control points every frame
-- ============================================================
hook.Add("Think", "bombin_plane_damage_fx", function()
    local ct = CurTime()
    for entIndex, state in pairs(PlaneStates) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            StopParticles(state)
            PlaneStates[entIndex] = nil
        else
            if state.pendingApply then
                state.pendingApply = false
                ApplyFlameParticles(ent, state, state.tier)
            end

            if state.tier > 0 then
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                for _, entry in ipairs(state.particles) do
                    if IsValid(entry.fx) then
                        entry.fx:SetControlPoint(0, LocalToWorld(entry.offset, Angle(0,0,0), pos, ang))
                    end
                end

                if ct >= state.nextBurst then
                    SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1)
                    state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
                end
            end
        end
    end
end)
