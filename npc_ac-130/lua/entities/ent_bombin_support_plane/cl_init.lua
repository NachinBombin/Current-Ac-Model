include("shared.lua")
include("cl_trailsystem.lua")

game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- ============================================================
-- SOUND LEVEL CONSTANTS (client)
-- sound.Play on the client ignores the level parameter for
-- volume rolloff — the engine treats it as a 2D non-spatialized
-- call regardless. We pass 255 to ensure the engine never
-- silences the sound due to level math, and rely on the
-- distance-based delay alone for spatial perception.
-- For ambient/pass sounds we use 160 so they still fade
-- naturally with distance (those go through EmitSound on an ent).
-- ============================================================
local SND_LEVEL_GAU    = 255   -- brrt: 2D, ignore rolloff, full volume always
local SND_LEVEL_WEAPON = 255   -- 40mm / 105mm / pass / destruct: same reason
local SOUND_SPEED_UNITS = 34300
local GAU_SOUND_SPEED   = 8000

-- ============================================================
-- GENERIC PLANE SOUND (40mm, 105mm, pass, destruction)
-- ============================================================
net.Receive("bombin_plane_sound", function()
    local path       = net.ReadString()
    local pos        = net.ReadVector()
    local level      = net.ReadUInt(8)   -- server hint; we override to SND_LEVEL_WEAPON
    local pitch      = net.ReadUInt(8)
    local volume     = net.ReadFloat()
    local extraDelay = net.ReadFloat()

    local distDelay  = EyePos():Distance(pos) / SOUND_SPEED_UNITS
    local totalDelay = math.max(0, extraDelay) + distDelay

    local function play()
        sound.Play(path, pos, SND_LEVEL_WEAPON, pitch, volume)
    end

    if totalDelay < 0.05 then
        play()
    else
        timer.Simple(totalDelay, play)
    end
end)

-- ============================================================
-- GAU MUZZLE FLASH + BRRT
-- Flash: immediate. Brrt: delayed by dist / GAU_SOUND_SPEED.
-- sound.Play is used (not EmitSound) because we need the sound
-- to play at FULL volume regardless of player distance —
-- the delay is the only spatial cue we rely on.
-- Level 255 prevents the engine from rolling off the sound.
-- ============================================================
net.Receive("bombin_gau_muzzle_flash", function()
    local muzzlePos  = net.ReadVector()
    local scale      = net.ReadFloat()
    local soundPath  = net.ReadString()
    local soundSpeed = net.ReadFloat()

    -- Flash: immediate
    local ed = EffectData()
    ed:SetOrigin(muzzlePos)
    ed:SetScale(scale)
    ed:SetMagnitude(scale)
    ed:SetRadius(8 * scale)
    util.Effect("cball_explode", ed)

    for _ = 1, 2 do
        local sp = EffectData()
        sp:SetOrigin(muzzlePos + Vector(math.Rand(-4,4), math.Rand(-4,4), 0))
        sp:SetNormal(Vector(0,0,1))
        sp:SetScale(scale)
        sp:SetMagnitude(scale)
        sp:SetRadius(8 * scale)
        util.Effect("ManhackSparks", sp)
    end

    if soundPath == "" then return end

    local dist  = EyePos():Distance(muzzlePos)
    local delay = dist / math.max(soundSpeed, 100)

    -- pitch varies slightly per-shot for organic feel
    local pitch = math.random(90, 105)

    local capPath  = soundPath
    local capPos   = Vector(muzzlePos.x, muzzlePos.y, muzzlePos.z)

    local function playBrrt()
        -- Level 255: engine will not attenuate this sound by distance.
        -- Volume 1.0: full amplitude. This ensures the brrt is always
        -- loud and clear; only the delay gives the player distance info.
        sound.Play(capPath, capPos, SND_LEVEL_GAU, pitch, 1.0)
    end

    if delay < 0.05 then
        playBrrt()
    else
        timer.Simple(delay, playBrrt)
    end
end)

-- ============================================================
-- DAMAGE TIERS
-- ============================================================
local TIER_OFFSETS = {
    [1] = { Vector(  0,   0,  20) },
    [2] = { Vector(  0,   0,  20), Vector( 90, 0, 5), Vector(-90, 0, 5) },
    [3] = { Vector(  0,   0,  20), Vector( 80, 0, 5), Vector(-80, 0, 5),
            Vector(  0, 130,  10), Vector(  0,-130,10), Vector(0, 0, -10) },
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 4   }

local PlaneStates = {}

local function BurstAt(wPos, tier)
    local ed = EffectData()
    ed:SetOrigin(wPos) ed:SetScale(tier == 3 and math.Rand(0.8,1.4) or math.Rand(0.4,0.9))
    ed:SetMagnitude(1) ed:SetRadius(tier * 20)
    util.Effect("Explosion", ed)

    local ed2 = EffectData()
    ed2:SetOrigin(wPos) ed2:SetNormal(Vector(0,0,1))
    ed2:SetScale(tier * 0.3) ed2:SetMagnitude(tier * 0.4) ed2:SetRadius(18)
    util.Effect("ManhackSparks", ed2)

    if tier >= 2 then
        local ed3 = EffectData()
        ed3:SetOrigin(wPos) ed3:SetNormal(VectorRand()) ed3:SetScale(0.6)
        util.Effect("ElectricSpark", ed3)
    end
end

local function SpawnBurstFX(ent, count, tier)
    if not IsValid(ent) then return end
    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    for _ = 1, count do
        local wPos = LocalToWorld(
            Vector(math.Rand(-100,100), math.Rand(-140,80), math.Rand(0,35)),
            Angle(0,0,0), pos, ang
        )
        BurstAt(wPos, tier)
    end
    if tier == 3 then
        for _, side in ipairs({ Vector(130,0,0), Vector(-130,0,0) }) do
            local wPos = LocalToWorld(side, Angle(0,0,0), pos, ang)
            local ed = EffectData()
            ed:SetOrigin(wPos) ed:SetScale(0.7) ed:SetMagnitude(1) ed:SetRadius(30)
            util.Effect("Explosion", ed)
        end
    end
end

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
    for _, off in ipairs(TIER_OFFSETS[tier]) do
        local p = ent:CreateParticleEffect("fire_medium_02", PATTACH_ABSORIGIN_FOLLOW, 0)
        if IsValid(p) then
            p:SetControlPoint(0, ent:LocalToWorld(off))
            table.insert(state.particles, p)
        end
    end
    state.nextBurst = CurTime() + (TIER_BURST_DELAY[tier] or 4)
end

net.Receive("bombin_plane_damage_tier", function()
    local entIndex = net.ReadUInt(16)
    local tier     = net.ReadUInt(2)
    local ent      = Entity(entIndex)

    PlaneTrailSystem_SetTier(entIndex, tier)

    local state = PlaneStates[entIndex]
    if not state then
        state = { tier = 0, particles = {}, nextBurst = 0 }
        PlaneStates[entIndex] = state
    end

    if state.tier == tier then return end

    if IsValid(ent) then
        ApplyFlameParticles(ent, state, tier)
        if tier > 0 then SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1, tier) end
    else
        state.tier         = tier
        state.pendingApply = true
    end
end)

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
                    SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1, state.tier)
                    state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
                end
            end
        end
    end
end)
