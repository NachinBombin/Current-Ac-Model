include("shared.lua")

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
-- AMBIENT LOOP — client-side so all players hear it
-- ============================================================
local ClientAmbientLoops = {}

hook.Add("OnEntityCreated", "bombin_plane_ambient_loop", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        if ent:GetClass() ~= "ent_bombin_support_plane" then return end
        local idx = ent:EntIndex()
        if ClientAmbientLoops[idx] then return end
        local path = ent:GetNWString("AmbientSoundPath", "ac/ac-130B.wav")
        local snd  = CreateSound(ent, path)
        if snd then
            snd:SetSoundLevel(80)
            snd:Play()
            ClientAmbientLoops[idx] = snd
        end
    end)
end)

hook.Add("EntityRemoved", "bombin_plane_ambient_loop_cleanup", function(ent)
    if not IsValid(ent) then return end
    local idx = ent:EntIndex()
    local snd = ClientAmbientLoops[idx]
    if snd then
        snd:Stop()
        ClientAmbientLoops[idx] = nil
    end
end)

-- ============================================================
-- DAMAGE STATE VISUALS
-- Tier 0 = healthy  (no FX)
-- Tier 1 = <=75% HP : 1x fire + 1x smoke
-- Tier 2 = <=50% HP : 2x fire + 2x smoke
-- Tier 3 = <=25% HP : 3x fire + 3x smoke
--
-- Particle systems used (all from HL2 Episode 2 base, ship with GMod):
--   fastFire           → particles/largefire.pcf
--   smoke_blackbillow  → particles/largefire.pcf
--   Explosion_2_FireSmoke → particles/explosion.pcf
-- ============================================================

local FIRE_SYSTEMS  = { "fastFire",          "fastFire",          "fastFire"          }
local SMOKE_SYSTEMS = { "smoke_blackbillow",  "smoke_blackbillow",  "Explosion_2_FireSmoke" }

local TIER_BURST_DELAY = { [1] = 4.0, [2] = 2.0, [3] = 0.8 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local FIRE_OFFSETS = {
    Vector(   0,    0,  20 ),
    Vector(  90,    0,   0 ),
    Vector( -90,    0,   0 ),
}
local SMOKE_OFFSETS = {
    Vector(   0, -130,  30 ),
    Vector(  60,  -80,  10 ),
    Vector( -60,  -80,  10 ),
}

local PlaneStates = {}

-- ============================================================
-- BURST EXPLOSION FX  (tier-up moment)
-- ============================================================
local function SpawnBurstFX(ent, count)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    for _ = 1, count do
        local lOff = Vector(
            math.Rand(-120, 120),
            math.Rand(-150,  80),
            math.Rand(   0,  30)
        )
        local wPos = LocalToWorld(lOff, Angle(0,0,0), pos, ang)

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
        if IsValid(p) then
            p:StopEmission(true, true)
        end
    end
    state.particles = {}
end

local function ApplyFlameParticles(ent, state, tier)
    StopParticles(state)
    state.tier = tier

    if not IsValid(ent) or tier == 0 then return end

    for i = 1, tier do
        local pName = FIRE_SYSTEMS[i] or FIRE_SYSTEMS[#FIRE_SYSTEMS]
        local p = ent:CreateParticleEffect(pName, PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(FIRE_OFFSETS[i] or Vector(0,0,0)))
            table.insert(state.particles, p)
        end
    end

    for i = 1, tier do
        local pName = SMOKE_SYSTEMS[i] or SMOKE_SYSTEMS[#SMOKE_SYSTEMS]
        local p = ent:CreateParticleEffect(pName, PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(SMOKE_OFFSETS[i] or Vector(0,0,0)))
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
        if tier > 0 then
            SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1)
        end
    else
        state.tier         = tier
        state.pendingApply = true
    end
end)

-- ============================================================
-- THINK — update control points + burst timer
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
                local pi  = 1
                for i = 1, state.tier do
                    local p = state.particles[pi]
                    if IsValid(p) then
                        p:SetControlPoint(0, LocalToWorld(FIRE_OFFSETS[i] or Vector(0,0,0), Angle(0,0,0), pos, ang))
                    end
                    pi = pi + 1
                end
                for i = 1, state.tier do
                    local p = state.particles[pi]
                    if IsValid(p) then
                        p:SetControlPoint(0, LocalToWorld(SMOKE_OFFSETS[i] or Vector(0,0,0), Angle(0,0,0), pos, ang))
                    end
                    pi = pi + 1
                end

                if ct >= state.nextBurst then
                    SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1)
                    state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
                end
            end
        end
    end
end)
