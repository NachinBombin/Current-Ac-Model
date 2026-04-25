include("shared.lua")

-- ============================================================
-- PRECACHE
-- ============================================================
game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

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
-- Only fire_medium_02 is used (confirmed working in tier 1).
-- Each tier adds more emitters spread across the airframe.
-- Tier 1: 1 emitter  (centre fuselage)
-- Tier 2: 3 emitters (centre + both wing roots)
-- Tier 3: 5 emitters (centre + wings + nose + tail)
-- ============================================================

local TIER_OFFSETS = {
    [1] = {
        Vector(  0,   0,  20),
    },
    [2] = {
        Vector(  0,   0,  20),
        Vector( 90,   0,   0),
        Vector(-90,   0,   0),
    },
    [3] = {
        Vector(  0,   0,  20),
        Vector( 90,   0,   0),
        Vector(-90,   0,   0),
        Vector(  0, 130,  10),
        Vector(  0,-130,  10),
    },
}

local TIER_BURST_DELAY = { [1] = 4.0, [2] = 2.0, [3] = 0.8 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local PlaneStates = {}

-- ============================================================
-- BURST EXPLOSION FX
-- ============================================================
local function SpawnBurstFX(ent, count)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    for _ = 1, count do
        local wPos = LocalToWorld(
            Vector(math.Rand(-120,120), math.Rand(-150,80), math.Rand(0,30)),
            Angle(0,0,0), pos, ang
        )
        local ed = EffectData()
        ed:SetOrigin(wPos)
        ed:SetScale(math.Rand(0.5, 1.0))
        ed:SetMagnitude(1)
        ed:SetRadius(40)
        util.Effect("Explosion", ed)

        local ed2 = EffectData()
        ed2:SetOrigin(wPos)
        ed2:SetNormal(Vector(0,0,1))
        ed2:SetScale(0.4)
        ed2:SetMagnitude(0.4)
        ed2:SetRadius(20)
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

    local offsets = TIER_OFFSETS[tier]
    for i = 1, #offsets do
        local p = ent:CreateParticleEffect("fire_medium_02", PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(offsets[i]))
            table.insert(state.particles, p)
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
-- THINK
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
                local pos     = ent:GetPos()
                local ang     = ent:GetAngles()
                local offsets = TIER_OFFSETS[state.tier]
                for i, p in ipairs(state.particles) do
                    if IsValid(p) and offsets[i] then
                        p:SetControlPoint(0, LocalToWorld(offsets[i], Angle(0,0,0), pos, ang))
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