include("shared.lua")

-- ============================================================
-- PRECACHE — HL2 base .pcf files, always present in GMod
-- ============================================================
game.AddParticles("particles/fire_01.pcf")
game.AddParticles("particles/fire_02.pcf")
game.AddParticles("particles/smoke_01.pcf")
game.AddParticles("particles/smoke_02.pcf")

PrecacheParticleSystem("fire_medium_02")
PrecacheParticleSystem("fire_large_02")
PrecacheParticleSystem("smoke_stack")
PrecacheParticleSystem("smoke_exhaust")

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
-- CreateSound on the server only plays server-side; we create
-- it here so every connected client gets the 3D looping audio.
-- ============================================================
local ClientAmbientLoops = {}   -- [entIndex] = CSoundPatch

hook.Add("OnEntityCreated", "bombin_plane_ambient_loop", function(ent)
    -- Defer one frame so the entity is fully initialised
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        if ent:GetClass() ~= "ent_bombin_support_plane" then return end

        local idx = ent:EntIndex()
        if ClientAmbientLoops[idx] then return end  -- already running

        -- Path is stored as a NW string set by the server, or fall back to default
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
-- ============================================================
-- Tier 0 = healthy   (no FX)
-- Tier 1 = <= 75% HP (1 fire + 1 smoke)
-- Tier 2 = <= 50% HP (2 fire + 2 smoke)
-- Tier 3 = <= 25% HP (3 fire + 3 smoke)

local FIRE_SYSTEMS  = { "fire_medium_02", "fire_large_02", "fire_large_02" }
local SMOKE_SYSTEMS = { "smoke_stack",    "smoke_stack",   "smoke_exhaust"  }

local TIER_BURST_DELAY = { [1] = 4.0, [2] = 2.0, [3] = 0.8 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local FIRE_OFFSETS = {
    Vector(  0,    0,  20),
    Vector( 90,    0,   0),
    Vector(-90,    0,   0),
}
local SMOKE_OFFSETS = {
    Vector(  0, -130,  30),
    Vector( 60,  -80,  10),
    Vector(-60,  -80,  10),
}

local PlaneStates = {}

-- ============================================================
-- BURST EXPLOSION FX
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
            -- true, true = stop immediately + destroy all live particles now
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
            local off = FIRE_OFFSETS[i] or Vector(0,0,0)
            p:SetControlPoint(0, ent:LocalToWorld(off))
            table.insert(state.particles, p)
        end
    end

    for i = 1, tier do
        local pName = SMOKE_SYSTEMS[i] or SMOKE_SYSTEMS[#SMOKE_SYSTEMS]
        local p = ent:CreateParticleEffect(pName, PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            local off = SMOKE_OFFSETS[i] or Vector(0,0,0)
            p:SetControlPoint(0, ent:LocalToWorld(off))
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

    local ent = Entity(entIndex)

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
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                local pi  = 1
                for i = 1, state.tier do
                    local p = state.particles[pi]
                    if IsValid(p) then
                        local off = FIRE_OFFSETS[i] or Vector(0,0,0)
                        p:SetControlPoint(0, LocalToWorld(off, Angle(0,0,0), pos, ang))
                    end
                    pi = pi + 1
                end
                for i = 1, state.tier do
                    local p = state.particles[pi]
                    if IsValid(p) then
                        local off = SMOKE_OFFSETS[i] or Vector(0,0,0)
                        p:SetControlPoint(0, LocalToWorld(off, Angle(0,0,0), pos, ang))
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
