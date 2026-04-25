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
-- Tier 1 = <=75% HP
-- Tier 2 = <=50% HP
-- Tier 3 = <=25% HP
--
-- We use ONLY engine-native util.Effect calls here.
-- Particle systems like smoke_stack / smoke_exhaust are TF2-only
-- and cause pink error textures on servers without TF2 mounted.
-- ============================================================

local TIER_BURST_DELAY = { [1] = 4.0, [2] = 2.0, [3] = 0.8 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

-- Local offsets for the repeating smoke/fire puffs
local DAMAGE_OFFSETS = {
    Vector(   0,    0,  20 ),
    Vector(  80,  -60,   0 ),
    Vector( -80,  -60,   0 ),
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
-- REPEATING DAMAGE SMOKE/FIRE  (runs every N seconds while damaged)
-- Uses HelicopterMegaBomb for heavy black smoke + fire flash.
-- This effect ships with every GMod install (HL2 base).
-- ============================================================
local function SpawnDamagePuff(ent, tier)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()

    -- Number of puff positions scales with tier
    for i = 1, tier do
        local off  = DAMAGE_OFFSETS[i] or Vector(0,0,0)
        local wPos = LocalToWorld(off, Angle(0,0,0), pos, ang)

        -- Black smoke column
        local ed1 = EffectData()
        ed1:SetOrigin(wPos)
        ed1:SetScale(1 + tier * 0.5)
        ed1:SetMagnitude(1 + tier * 0.5)
        ed1:SetRadius(80 + tier * 40)
        util.Effect("HelicopterMegaBomb", ed1)

        -- Small fire flash at same point
        local ed2 = EffectData()
        ed2:SetOrigin(wPos)
        ed2:SetScale(0.6)
        ed2:SetMagnitude(0.6)
        ed2:SetRadius(30)
        util.Effect("Explosion", ed2)
    end
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
        state = { tier = 0, nextPuff = 0 }
        PlaneStates[entIndex] = state
    end

    if state.tier == tier then return end
    state.tier    = tier
    state.nextPuff = CurTime()

    -- Immediate burst on tier transition
    if tier > 0 and IsValid(ent) then
        SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1)
    end
end)

-- ============================================================
-- THINK — drive the repeating puff timer
-- ============================================================
hook.Add("Think", "bombin_plane_damage_fx", function()
    local ct = CurTime()
    for entIndex, state in pairs(PlaneStates) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            PlaneStates[entIndex] = nil
        elseif state.tier > 0 and ct >= state.nextPuff then
            SpawnDamagePuff(ent, state.tier)
            state.nextPuff = ct + (TIER_BURST_DELAY[state.tier] or 4)
        end
    end
end)
