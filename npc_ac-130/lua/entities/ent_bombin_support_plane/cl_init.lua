include("shared.lua")

-- Receive gunfire / pass sound broadcast from server and play locally
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
-- ============================================================
-- Tier 0 = healthy  (no FX)
-- Tier 1 = 75% HP   (light smoke + occasional small explosion)
-- Tier 2 = 50% HP   (heavier smoke/fire + more frequent explosions)
-- Tier 3 = 25% HP   (full fire + rapid explosions)

-- Local offsets on the model where fire/explosions can appear.
-- These are local-space positions spread across the fuselage, wings, tail.
local DAMAGE_OFFSETS = {
    Vector(  0,    0,   10),   -- centre fuselage top
    Vector( 80,    0,    0),   -- left wing root
    Vector(-80,    0,    0),   -- right wing root
    Vector(  0, -120,   20),   -- tail boom
    Vector( 50,  -60,   15),   -- left rear
    Vector(-50,  -60,   15),   -- right rear
    Vector(  0,   80,    5),   -- nose
}

-- Particle systems available in base GMod (no extra content needed)
local FIRE_PARTICLES = {
    "fire_medium_01",
    "fire_large_01",
    "fire_large_02",
}
local SMOKE_PARTICLES = {
    "smoke_medium",
    "smoke_large",
    "smoke_exhaust01",
}

-- Per-entity client state
local PlaneStates = {}
-- PlaneStates[entIndex] = {
--   tier        : number (0-3)
--   particles   : table of CSEfx handles (from ParticleEffect)
--   nextBurst   : CurTime when to fire next small explosion burst
--   burstDelay  : seconds between bursts
-- }

local TIER_BURST_DELAY = { [1] = 4.0, [2] = 2.0, [3] = 0.8 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

-- Helper: spawn a one-shot small explosion effect at a random local offset
local function SpawnBurstFX(ent, count)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()

    for _ = 1, count do
        local localOff = table.Random(DAMAGE_OFFSETS)
        -- add small random jitter so repeated bursts don't overlap exactly
        local jitter = Vector(
            math.Rand(-20, 20),
            math.Rand(-20, 20),
            math.Rand(  0, 15)
        )
        local worldPos = LocalToWorld(localOff + jitter, Angle(0,0,0), pos, ang)

        local ed = EffectData()
        ed:SetOrigin(worldPos)
        ed:SetScale(math.Rand(0.6, 1.2))
        ed:SetMagnitude(1)
        ed:SetRadius(40)
        util.Effect("Explosion", ed)

        -- small secondary sparks
        local ed2 = EffectData()
        ed2:SetOrigin(worldPos)
        ed2:SetScale(0.5)
        ed2:SetMagnitude(0.5)
        ed2:SetRadius(20)
        util.Effect("ManhackSparks", ed2)
    end
end

-- Helper: create/replace looping particle effects for a given tier
local function ApplyFlameParticles(ent, state, tier)
    -- Stop old particles
    if state.particles then
        for _, p in ipairs(state.particles) do
            if IsValid(p) then p:StopEmission() end
        end
    end
    state.particles = {}

    if not IsValid(ent) or tier == 0 then return end

    local pos = ent:GetPos()
    local ang = ent:GetAngles()

    -- Number of fire/smoke points scales with tier
    local firePts  = tier         -- tier1=1, tier2=2, tier3=3
    local smokePts = tier + 1     -- tier1=2, tier2=3, tier3=4

    -- Choose offset slots deterministically so they don't jump each update
    for i = 1, firePts do
        local off      = DAMAGE_OFFSETS[i]
        local worldPos = LocalToWorld(off, Angle(0,0,0), pos, ang)
        local p = ParticleEffect(table.Random(FIRE_PARTICLES), worldPos, Angle(0,0,0), ent)
        if IsValid(p) then table.insert(state.particles, p) end
    end

    for i = 1, smokePts do
        local off      = DAMAGE_OFFSETS[math.min(i + firePts, #DAMAGE_OFFSETS)]
        local worldPos = LocalToWorld(off, Angle(0,0,0), pos, ang)
        local p = ParticleEffect(table.Random(SMOKE_PARTICLES), worldPos, Angle(0,0,0), ent)
        if IsValid(p) then table.insert(state.particles, p) end
    end

    state.tier      = tier
    state.nextBurst = CurTime() + (TIER_BURST_DELAY[tier] or 4)
end

-- Net message: server tells clients the new damage tier for this plane
net.Receive("bombin_plane_damage_tier", function()
    local entIndex = net.ReadUInt(16)
    local tier     = net.ReadUInt(2)   -- 0-3

    local ent = Entity(entIndex)
    if not IsValid(ent) then return end

    local state = PlaneStates[entIndex]
    if not state then
        state = { tier = 0, particles = {}, nextBurst = 0, burstDelay = 4 }
        PlaneStates[entIndex] = state
    end

    if state.tier == tier then return end  -- no change

    ApplyFlameParticles(ent, state, tier)

    -- Immediately fire one burst when a new tier is reached
    if tier > 0 then
        SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1)
    end
end)

-- Think hook: drive periodic burst explosions and keep particles attached
hook.Add("Think", "bombin_plane_damage_fx", function()
    local ct = CurTime()
    for entIndex, state in pairs(PlaneStates) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            -- clean up stale entries
            if state.particles then
                for _, p in ipairs(state.particles) do
                    if IsValid(p) then p:StopEmission() end
                end
            end
            PlaneStates[entIndex] = nil
        else
            if state.tier > 0 and ct >= state.nextBurst then
                SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1)
                state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
            end
        end
    end
end)
