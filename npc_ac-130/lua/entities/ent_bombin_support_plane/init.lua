AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local MODEL_YAW_OFFSET = 0

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

-- ============================================================
-- SOUNDS
-- ============================================================

local SOUNDS_S8_IGNITE   = { "S8.wav",   "S82.wav",   "S83.wav",   "S84.wav"   }
local SOUNDS_ATGM_IGNITE = { "ATGM.wav", "ATGM2.wav", "ATGM3.wav", "ATGM4.wav" }
local SOUNDS_LAUNCH      = { "launch1.wav", "launch2.wav" }
local SOUND_ROCKET_IDLE  = "rocket_idle.wav"

local GAU_CAL_ID = 3

-- ============================================================
-- TUNING
-- ============================================================

local CFG_WeaponWindow = 8

local PEACEFUL_MIN = 4
local PEACEFUL_MAX = 7

local CFG_MuzzlePoints = {
    Vector(110,   0, 93),
    Vector( 57, -84, 40),
    Vector( 57,  84, 40),
    Vector( 87,-111, 37),
    Vector( 87, 111, 37),
}

local CFG_GAU_BurstDelay       = 0.14
local CFG_GAU_TripletCount     = 5
local CFG_GAU_TripletGap_Min   = 0.6
local CFG_GAU_TripletGap_Max   = 1.4

local CFG_GAU_BulletDamage    = 40
local CFG_GAU_BlastRadius     = 140
local CFG_GAU_SweepHalfLength = 300
local CFG_GAU_JitterAmount    = 400
local CFG_GAU_HEI_Interval    = 90

local CFG_GAU_Spray_Delay          = 0.31
local CFG_GAU_SprayJitter          = 120
local CFG_GAU_SprayBurstRounds_Min = 3
local CFG_GAU_SprayBurstRounds_Max = 7
local CFG_GAU_SprayPause_Min       = 0.45
local CFG_GAU_SprayPause_Max       = 0.85

local CFG_S8_Delay   = 0.15
local CFG_S8_Count   = 22
local CFG_S8_Scatter = 1200
local CFG_S8_MuzzlePoints = {
    Vector(57, -84,  40),
    Vector(57,  84,  40),
    Vector(57,-111, 40),
    Vector(57, 111, 40),
}

local CFG_VIKHR_Delay   = 3.0
local CFG_VIKHR_Count   = 2
local CFG_VIKHR_Scatter = 80
local CFG_VIKHR_MuzzlePoints = {
    Vector(87,-111, 37),
    Vector(87, 111, 37),
}

local CFG_FadeDuration = 2.0
local CFG_MaxHP        = 3100

-- ============================================================
-- OBSTACLE EVASION CONSTANTS
-- Polar-free: all 8 headings scored equally, random tiebreak.
-- ============================================================
local PROBE_FORWARD  = 3200
local PROBE_DIAG     = 2400
local PROBE_SIDE     = 1600
local PROBE_UP       = 900
local PROBE_DOWN     = 700
local PROBE_MASK     = MASK_SOLID_BRUSHONLY

local EVASION_BLEND       = 0.14
local EVASION_PITCH_NUDGE = 0.12
local EVASION_PITCH_MAX   = 8
local CLEAR_TIME          = 2.5

local EVASION_CANDIDATES = { 0, 45, 90, 135, 180, 225, 270, 315 }

-- ============================================================
-- NET STRING
-- ============================================================
util.AddNetworkString("bombin_plane_damage_tier")

-- ============================================================
-- DAMAGE TIER HELPERS
-- ============================================================

local function CalcTier(hp, maxHP)
    local frac = hp / maxHP
    if frac > 0.66 then return 0
    elseif frac > 0.33 then return 1
    elseif frac > 0 then return 2
    else return 3
    end
end

local function BroadcastTier(ent, tier)
    net.Start("bombin_plane_damage_tier")
        net.WriteUInt(ent:EntIndex(), 16)
        net.WriteUInt(tier, 2)
    net.Broadcast()
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
    self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
    self.Lifetime     = self:GetVar("Lifetime",     40)
    self.Speed        = self:GetVar("Speed",        250)
    self.OrbitRadius  = self:GetVar("OrbitRadius",  2500)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 2500)

    self.MaxHP        = CFG_MaxHP
    self.FadeDuration = CFG_FadeDuration
    self.WeaponWindow = CFG_WeaponWindow
    self.MuzzlePoints = CFG_MuzzlePoints

    self.GAU_BurstDelay         = CFG_GAU_BurstDelay
    self.GAU_TripletCount       = CFG_GAU_TripletCount
    self.GAU_TripletGap_Min     = CFG_GAU_TripletGap_Min
    self.GAU_TripletGap_Max     = CFG_GAU_TripletGap_Max
    self.GAU_BulletDamage       = CFG_GAU_BulletDamage
    self.GAU_BlastRadius        = CFG_GAU_BlastRadius
    self.GAU_SweepHalfLength    = CFG_GAU_SweepHalfLength
    self.GAU_JitterAmount       = CFG_GAU_JitterAmount
    self.GAU_HEI_Interval       = CFG_GAU_HEI_Interval

    self.GAU_Spray_Delay          = CFG_GAU_Spray_Delay
    self.GAU_SprayJitter          = CFG_GAU_SprayJitter
    self.GAU_SprayBurstRounds_Min = CFG_GAU_SprayBurstRounds_Min
    self.GAU_SprayBurstRounds_Max = CFG_GAU_SprayBurstRounds_Max
    self.GAU_SprayPause_Min       = CFG_GAU_SprayPause_Min
    self.GAU_SprayPause_Max       = CFG_GAU_SprayPause_Max

    self.S8_Delay        = CFG_S8_Delay
    self.S8_Count        = CFG_S8_Count
    self.S8_Scatter      = CFG_S8_Scatter
    self.S8_MuzzlePoints = CFG_S8_MuzzlePoints

    self.VIKHR_Delay        = CFG_VIKHR_Delay
    self.VIKHR_Count        = CFG_VIKHR_Count
    self.VIKHR_Scatter      = CFG_VIKHR_Scatter
    self.VIKHR_MuzzlePoints = CFG_VIKHR_MuzzlePoints

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    -- Orbit direction: random, polar-free.
    self.OrbitDirection = (math.random(2) == 1) and 1 or -1

    local outward = VectorRand()
    outward.z = math.Rand(-0.08, 0.08)
    outward:Normalize()
    local tangent = Vector(0,0,1):Cross(outward)
    tangent.z = 0
    if tangent:LengthSqr() < 0.001 then tangent = Vector(1,0,0) end
    tangent:Normalize()
    if tangent:Dot(self.CallDir) < 0 then tangent = -tangent end
    self.OrbitTangent = tangent * self.OrbitDirection

    self.RadialGain   = 0.42
    self.SkyAvoidGain = 0.65
    self.MaxTurnRate  = 32

    local spawnOffset = self.OrbitTangent * (-self.OrbitRadius * math.Rand(0.55, 0.95))
    local spawnPos    = self.CenterPos + spawnOffset
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then
        self:Debug("Spawn position out of world") self:Remove() return
    end

    self:SetModel("models/heli/rus/ka50/ka50.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    self:SetPos(spawnPos)

    self:SetBodygroup(4, 1)
    self:SetBodygroup(3, 1)
    self:SetBodygroup(5, 2)

    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    self:SetNWInt("HP",    self.MaxHP)
    self:SetNWInt("MaxHP", self.MaxHP)

    self.flightYaw = self.OrbitTangent:Angle().y
    self.PrevYaw   = self.flightYaw
    self.ang       = Angle(0, self.flightYaw + MODEL_YAW_OFFSET, 0)
    self:SetAngles(self.ang)

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 12

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
    self.AltDriftRange    = 700
    self.AltDriftLerp     = 0.003

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0

    -- Evasion state
    self.IsEvading        = false
    self.EvasionYaw       = self.flightYaw
    self.EvasionPitch     = 0
    self.EvasionClearT    = 0

    self.IsTumbling        = false
    self.TumbleLastTime    = 0
    self.TumbleGroundZ     = ground
    self.TumbleCrashed     = false
    self.TumbleVelocity    = Vector(0,0,0)
    self.TumbleAngVelocity = Vector(0,0,0)

    self.IsDestroyed = false
    self.DamageTier  = 0

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
        self.PhysObj:SetMass(1e8)
        self.PhysObj:SetDamping(1, 1)
    end

    self.IdleLoop = CreateSound(self, "npc_ka52/ka50engine.wav")
    if self.IdleLoop then
        self.IdleLoop:SetSoundLevel(110)
        self.IdleLoop:ChangePitch(100, 0)
        self.IdleLoop:ChangeVolume(1.0, 0)
        self.IdleLoop:Play()
    end

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0
    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}
    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.NextShotTimeSpray  = 0
    self.SprayBulletCount   = 0
    self.SprayBurstRoundsLeft = 0
    self.SprayPauseUntil    = 0
    self.S8_ShotsFired      = 0
    self.S8_NextShot        = 0
    self.S8_MuzzleIndex     = 1
    self.VIKHR_ShotsFired   = 0
    self.VIKHR_NextShot     = 0
    self.VIKHR_MuzzleIndex  = 1
    self.MuzzleIndexGlobal  = 1
    self.TracerCounter      = 0
    self.IsPeaceful         = false
    self.PeacefulUntil      = 0
    self._PendingWeapon     = nil

    if not HasGred() then
        self:Debug("WARNING: Gredwitch Base not detected — HEI rounds disabled")
    end

    self:Debug("Spawned at " .. tostring(spawnPos) .. " OrbitDirection=" .. self.OrbitDirection)
end

-- ============================================================
-- OBSTACLE EVASION — POLAR-FREE
-- ============================================================

function ENT:RunObstacleProbes()
    local pos  = self:GetPos()
    local yaw  = Angle(0, self.flightYaw, 0)
    local fwd  = yaw:Forward()
    local rgt  = yaw:Right()
    local up   = Vector(0, 0, 1)

    local fwdL = (fwd - rgt):GetNormalized()
    local fwdR = (fwd + rgt):GetNormalized()

    local function probe(endpos)
        return util.TraceLine({ start = pos, endpos = endpos, filter = self, mask = PROBE_MASK })
    end

    local hitFwd   = probe(pos + fwd  * PROBE_FORWARD).Hit
    local hitFwdL  = probe(pos + fwdL * PROBE_DIAG).Hit
    local hitFwdR  = probe(pos + fwdR * PROBE_DIAG).Hit
    local hitLeft  = probe(pos - rgt  * PROBE_SIDE).Hit
    local hitRight = probe(pos + rgt  * PROBE_SIDE).Hit
    local hitUp    = probe(pos + up   * PROBE_UP).Hit
    local hitDown  = probe(pos - up   * PROBE_DOWN).Hit

    local anyHit = hitFwd or hitFwdL or hitFwdR or hitLeft or hitRight or hitUp or hitDown

    return anyHit, hitUp, hitDown, hitLeft, hitRight, hitFwdL, hitFwdR
end

function ENT:PickBestEvasionYaw(hitLeft, hitRight, hitFwdL, hitFwdR)
    local pos         = self:GetPos()
    local bestPenalty = math.huge
    local bestList    = {}

    local fwdRef = Angle(0, self.flightYaw, 0):Forward(); fwdRef.z = 0; fwdRef:Normalize()
    local rgtRef = Angle(0, self.flightYaw, 0):Right();   rgtRef.z = 0; rgtRef:Normalize()

    for _, offset in ipairs(EVASION_CANDIDATES) do
        local testYaw = math.NormalizeAngle(self.flightYaw + offset)
        local testFwd = Angle(0, testYaw, 0):Forward()
        testFwd.z = 0
        testFwd:Normalize()

        local penalty = 0
        local dotFwd  = testFwd:Dot(fwdRef)
        local dotRgt  = testFwd:Dot(rgtRef)

        if hitFwdL  and dotFwd > 0.3  and dotRgt < -0.3 then penalty = penalty + 2 end
        if hitFwdR  and dotFwd > 0.3  and dotRgt >  0.3 then penalty = penalty + 2 end
        if hitLeft  and dotRgt < -0.6 then penalty = penalty + 3 end
        if hitRight and dotRgt >  0.6 then penalty = penalty + 3 end

        local tr = util.TraceLine({
            start  = pos,
            endpos = pos + testFwd * PROBE_DIAG,
            filter = self,
            mask   = PROBE_MASK,
        })
        if tr.Hit then penalty = penalty + 4 end

        if penalty < bestPenalty then
            bestPenalty = penalty
            bestList    = { testYaw }
        elseif penalty == bestPenalty then
            bestList[#bestList + 1] = testYaw
        end
    end

    return bestList[math.random(#bestList)]
end

function ENT:UpdateEvasion()
    if self.IsTumbling or self.IsDestroyed then return 0 end

    local anyHit, hitUp, hitDown, hitLeft, hitRight, hitFwdL, hitFwdR = self:RunObstacleProbes()
    local ct = CurTime()

    if anyHit then
        self.EvasionClearT = 0

        if not self.IsEvading then
            self.EvasionYaw   = self:PickBestEvasionYaw(hitLeft, hitRight, hitFwdL, hitFwdR)
            self.IsEvading    = true
            self.EvasionPitch = 0
            self:Debug("Evasion started → yaw " .. string.format("%.1f", self.EvasionYaw))
        else
            self.EvasionYaw = self:PickBestEvasionYaw(hitLeft, hitRight, hitFwdL, hitFwdR)
        end

        if hitDown and not hitUp then
            self.EvasionPitch = self.EvasionPitch - EVASION_PITCH_NUDGE
        elseif hitUp and not hitDown then
            self.EvasionPitch = self.EvasionPitch + EVASION_PITCH_NUDGE
        end
        self.EvasionPitch = math.Clamp(self.EvasionPitch, -EVASION_PITCH_MAX, EVASION_PITCH_MAX)
    else
        if self.IsEvading then
            if self.EvasionClearT == 0 then
                self.EvasionClearT = ct
            elseif ct - self.EvasionClearT >= CLEAR_TIME then
                self.IsEvading     = false
                self.EvasionClearT = 0
                self.EvasionPitch  = 0
                self:Debug("Evasion cleared")
            end
        end
    end

    return self.EvasionPitch
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    local hp = self:GetNWInt("HP", self.MaxHP)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    self:Debug("Hit! HP remaining: " .. tostring(hp))

    local tier = CalcTier(hp, self.MaxHP)
    if tier ~= self.DamageTier then
        self.DamageTier = tier
        BroadcastTier(self, tier)
    end

    if hp <= 0 then self:Debug("Shot down!") self:DestroyHeli() end
end

-- ============================================================
-- TUMBLE SYSTEM
-- ============================================================

function ENT:StartTumble()
    self.IsTumbling     = true
    self.TumbleLastTime = CurTime()
    self.TumbleCrashed  = false

    local gnd = self:FindGround(self:GetPos())
    if gnd ~= -1 then self.TumbleGroundZ = gnd end

    local travelFwd = Angle(0, self.flightYaw, 0):Forward()
    local speed     = self.Speed or 250

    self.TumbleVelocity = Vector(travelFwd.x * speed, travelFwd.y * speed, -200)

    local sign = function() return (math.random(2) == 1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand(80,  200) * sign(),
        math.Rand(20,  80)  * sign(),
        math.Rand(150, 400) * sign()
    )

    -- Silence physics so it does not fight the tumble integration
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false)
        phys:SetVelocity(Vector(0,0,0))
        phys:SetAngleVelocity(Vector(0,0,0))
        phys:Sleep()
    end

    local pos = self:GetPos()
    local ed  = EffectData() ed:SetOrigin(pos) ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_4.wav", pos, 135, 95, 1.0)
end

function ENT:UpdateTumble(ct)
    if not self.IsTumbling or self.TumbleCrashed then return end

    local dt = ct - self.TumbleLastTime
    self.TumbleLastTime = ct
    if dt <= 0 or dt > 0.2 then return end

    local gravity = physenv.GetGravity().z
    self.TumbleVelocity.z = self.TumbleVelocity.z + gravity * dt

    local pos    = self:GetPos()
    local newPos = pos + self.TumbleVelocity * dt
    local av     = self.TumbleAngVelocity
    self.ang     = Angle(self.ang.p + av.x*dt, self.ang.y + av.y*dt, self.ang.r + av.z*dt)

    local hitGround = newPos.z <= (self.TumbleGroundZ or -16384) + 200
    local hitWall   = false
    if not hitGround then
        local tr = util.TraceLine({ start = pos, endpos = newPos, filter = self, mask = MASK_SOLID_BRUSHONLY })
        hitWall = tr.HitWorld
    end

    if hitGround or hitWall then
        self:CrashExplode()
        return
    end

    self:SetPos(newPos)
    self:SetAngles(self.ang)
end

function ENT:CrashExplode()
    if self.TumbleCrashed then return end
    self.TumbleCrashed = true

    local pos = self:GetPos()
    local ed1=EffectData() ed1:SetOrigin(pos) ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600) util.Effect("HelicopterMegaBomb",ed1,true,true)
    local ed2=EffectData() ed2:SetOrigin(pos) ed2:SetScale(5) ed2:SetMagnitude(5) ed2:SetRadius(500) util.Effect("500lb_air",ed2,true,true)
    local ed3=EffectData() ed3:SetOrigin(pos+Vector(0,0,80)) ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400) util.Effect("500lb_air",ed3,true,true)
    local ed4=EffectData() ed4:SetOrigin(pos+Vector(0,0,180)) ed4:SetScale(3) ed4:SetMagnitude(3) ed4:SetRadius(300) util.Effect("500lb_air",ed4,true,true)

    sound.Play("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)
    sound.Play("weapon_AWP.Single",               pos, 145, 60, 1.0)
    util.BlastDamage(self, self, pos, 400, 200)
    self:Remove()
end

function ENT:DestroyHeli()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    if self.IdleLoop then self.IdleLoop:Stop() self.IdleLoop = nil end
    self:StartTumble()
    timer.Simple(12, function() if IsValid(self) then self:CrashExplode() end end)
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
    print("[Npc KA-50] " .. tostring(msg))
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime() + 0.1)
        return true
    end

    local ct = CurTime()

    -- Tumble is driven here (not in PhysicsUpdate) so we have a clean dt.
    if self.IsTumbling then
        if not self.TumbleCrashed then
            self:UpdateTumble(ct)
        end
        self:NextThink(ct + 0.015)
        return true
    end

    if ct >= self.DieTime then self:Remove() return end

    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha = 255
    if age < self.FadeDuration then
        alpha = math.Clamp(255 * (age / self.FadeDuration), 0, 255)
    elseif left < self.FadeDuration then
        alpha = math.Clamp(255 * (left / self.FadeDuration), 0, 255)
    end
    self:SetColor(Color(255, 255, 255, math.Round(alpha)))

    self:HandleWeaponWindow(ct)
    self:UpdateActiveGAUBursts(ct)

    self:NextThink(ct)
    return true
end

-- ============================================================
-- FLIGHT PHYSICS
-- KEY RULE (matches AC-130 architecture):
--   During normal flight, only phys:SetPos() and phys:SetAngles()
--   are called. self:SetPos() / self:SetAngles() are NEVER called
--   here — doing both on the same tick is what caused teleporting.
--   The physics engine propagates phys pos → entity transform.
-- Tumble is driven by Think/UpdateTumble using self:SetPos() because
--   the phys object is asleep during tumble.
-- ============================================================

function ENT:PhysicsUpdate(phys)
    -- During tumble the phys object is asleep; bail out completely.
    if self.IsTumbling or self.IsDestroyed then
        phys:SetVelocity(Vector(0,0,0))
        phys:SetAngleVelocity(Vector(0,0,0))
        return
    end

    if not self.DieTime or not self.sky then return end
    if CurTime() >= self.DieTime then self:Remove() return end

    local pos = self:GetPos()
    local ft  = engine.TickInterval()

    -- Altitude drift
    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
    self.JitterPhase     = self.JitterPhase + 0.04
    local liveAlt = self.AltDriftCurrent + math.sin(self.JitterPhase) * self.JitterAmplitude

    -- Evasion probes
    local evasionPitch = self:UpdateEvasion()

    -- Desired yaw: evasion overrides orbit
    local desiredYaw

    if self.IsEvading then
        local delta = math.NormalizeAngle(self.EvasionYaw - self.flightYaw)
        desiredYaw  = self.flightYaw + delta * EVASION_BLEND
    else
        -- Normal orbit
        local flatPos    = Vector(pos.x, pos.y, 0)
        local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
        local toCenter   = flatCenter - flatPos
        local dist       = toCenter:Length()

        local radialDir  = (dist > 1) and (toCenter / dist) or Vector(0,0,0)
        local tangentDir = Vector(-radialDir.y, radialDir.x, 0) * self.OrbitDirection
        if tangentDir:LengthSqr() <= 0.001 then
            tangentDir = Angle(0, self.flightYaw, 0):Forward()
            tangentDir.z = 0
        end
        tangentDir:Normalize()

        local radialError = 0
        if self.OrbitRadius > 0 then
            radialError = math.Clamp((dist - self.OrbitRadius) / self.OrbitRadius, -1, 1)
        end

        local desiredDir = tangentDir + radialDir * radialError * self.RadialGain

        -- Sky avoidance
        local fwdProbe  = Angle(0, self.flightYaw, 0):Forward()
        local probeDist = math.max(1200, self.Speed * 6)
        local trFwd   = util.QuickTrace(pos, fwdProbe * probeDist, self)
        local trLeft  = util.QuickTrace(pos, fwdProbe:Angle():Right() * -900 + fwdProbe * 600, self)
        local trRight = util.QuickTrace(pos, fwdProbe:Angle():Right() *  900 + fwdProbe * 600, self)

        local skyAvoid = Vector(0,0,0)
        if trFwd.HitSky   then skyAvoid = skyAvoid - fwdProbe end
        if trLeft.HitSky  then skyAvoid = skyAvoid + fwdProbe:Angle():Right() end
        if trRight.HitSky then skyAvoid = skyAvoid - fwdProbe:Angle():Right() end
        skyAvoid.z = 0
        if skyAvoid:LengthSqr() > 0.001 then
            skyAvoid:Normalize()
            desiredDir = desiredDir + skyAvoid * self.SkyAvoidGain
        end

        desiredDir.z = 0
        if desiredDir:LengthSqr() <= 0.001 then desiredDir = tangentDir end
        desiredDir:Normalize()
        desiredYaw = desiredDir:Angle().y
    end

    -- Turn-rate clamp
    local yawDiff  = math.NormalizeAngle(desiredYaw - self.flightYaw)
    local maxStep  = self.MaxTurnRate * ft
    self.flightYaw = self.flightYaw + math.Clamp(yawDiff, -maxStep, maxStep)

    local rawYawDelta = math.NormalizeAngle(self.flightYaw - (self.PrevYaw or self.flightYaw))
    self.PrevYaw      = self.flightYaw

    -- Bank & pitch
    local targetRoll  = math.Clamp(rawYawDelta * -20, -20, 20)
    self.SmoothedRoll = Lerp(math.abs(rawYawDelta) > 0.01 and 0.12 or 0.04, self.SmoothedRoll, targetRoll)

    local climbDelta  = math.Clamp((liveAlt - pos.z) / 450, -1, 1)
    local pitchTarget = math.Clamp(climbDelta * 8 + evasionPitch, -8, 8)
    self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, pitchTarget)

    local finalAng = Angle(self.SmoothedPitch, self.flightYaw + MODEL_YAW_OFFSET, self.SmoothedRoll)

    -- Desired next position
    local fwdDir = Angle(0, self.flightYaw, 0):Forward()
    local newPos = Vector(
        pos.x + fwdDir.x * self.Speed * ft,
        pos.y + fwdDir.y * self.Speed * ft,
        liveAlt
    )

    -- Out-of-world guard: discard the move, nudge evasion yaw, keep current pos.
    -- Do NOT teleport to center — that was the source of the teleport loops.
    if not util.IsInWorld(newPos) then
        self:Debug("Out-of-world move discarded")
        if not self.IsEvading then
            self.EvasionYaw   = self:PickBestEvasionYaw(false, false, false, false)
            self.IsEvading    = true
            self.EvasionPitch = 0
        else
            self.EvasionYaw = self:PickBestEvasionYaw(false, false, false, false)
        end
        -- Only update angle; keep pos unchanged.
        phys:SetAngles(finalAng)
        return
    end

    -- Drive position and angle through physics object ONLY.
    -- Never call self:SetPos() here; the engine syncs entity pos from phys.
    phys:SetPos(newPos)
    phys:SetAngles(finalAng)
    phys:SetVelocity(fwdDir * self.Speed)
end

-- ============================================================
-- TARGET / MUZZLE HELPERS
-- ============================================================

function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then closestDist = d closest = ply end
    end
    return closest
end

function ENT:GetTargetGroundPos()
    local target = self:GetPrimaryTarget()
    if IsValid(target) then return target:GetPos() end
    local tr = util.QuickTrace(
        Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
        Vector(0, 0, -30000), self
    )
    return tr.HitPos
end

function ENT:GetMuzzleWorldPos(localPoint)
    return self:LocalToWorld(localPoint)
end

function ENT:SpawnMuzzleFX(worldPos)
    local ed = EffectData()
    ed:SetOrigin(worldPos)
    ed:SetAngles(self:GetAngles())
    ed:SetScale(2)
    ed:SetMagnitude(2)
    util.Effect("MuzzleEffect", ed, true, true)
end

-- ============================================================
-- WEAPON CYCLE WITH PEACEFUL MODE
-- ============================================================

function ENT:HandleWeaponWindow(ct)
    if self.IsPeaceful then
        if ct >= self.PeacefulUntil then
            self.IsPeaceful = false
            self:ArmWeapon(self._PendingWeapon, ct)
            self._PendingWeapon = nil
        end
        return
    end

    if not self.CurrentWeapon then
        self:EnterPeaceful(ct)
        return
    end

    if ct >= self.WeaponWindowEnd then
        self:EnterPeaceful(ct)
        return
    end

    if     self.CurrentWeapon == "30mm_burst"     then self:Update30mmBurstsSchedule(ct)
    elseif self.CurrentWeapon == "30mm_sustained" then self:Update30mmSustained(ct)
    elseif self.CurrentWeapon == "s8_salvo"       then self:UpdateS8Salvo(ct)
    elseif self.CurrentWeapon == "vikhr"          then self:UpdateVikhr(ct)
    end
end

function ENT:EnterPeaceful(ct)
    self.CurrentWeapon  = nil
    self.IsPeaceful     = true
    self.PeacefulUntil  = ct + math.Rand(PEACEFUL_MIN, PEACEFUL_MAX)
    self._PendingWeapon = self:RollWeapon()
    self:Debug("Peaceful for " .. string.format("%.1f", self.PeacefulUntil - ct) .. "s, next: " .. self._PendingWeapon)
end

function ENT:RollWeapon()
    local roll = math.random(1, 4)
    if     roll == 1 then return "30mm_burst"
    elseif roll == 2 then return "30mm_sustained"
    elseif roll == 3 then return "s8_salvo"
    else                   return "vikhr"
    end
end

function ENT:ArmWeapon(weapon, ct)
    weapon = weapon or self:RollWeapon()
    self.CurrentWeapon   = weapon
    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Armed: " .. self.CurrentWeapon)

    if self.CurrentWeapon == "30mm_burst" then
        self.GAU_BurstTimes   = {}
        self.GAU_BurstsFired  = 0
        self.GAU_ActiveBursts = {}
        local t = ct
        for i = 1, self.GAU_TripletCount do
            if i > 1 then
                t = t + (3 * self.GAU_BurstDelay) + math.Rand(self.GAU_TripletGap_Min, self.GAU_TripletGap_Max)
            end
            if t < self.WeaponWindowEnd then
                self.GAU_BurstTimes[i] = t
            end
        end

    elseif self.CurrentWeapon == "30mm_sustained" then
        self.NextShotTimeSpray    = ct
        self.SprayBulletCount     = 0
        self.SprayBurstRoundsLeft = math.random(self.GAU_SprayBurstRounds_Min, self.GAU_SprayBurstRounds_Max)
        self.SprayPauseUntil      = 0

    elseif self.CurrentWeapon == "s8_salvo" then
        self.S8_ShotsFired  = 0
        self.S8_NextShot    = ct + 0.2
        self.S8_MuzzleIndex = 1

    elseif self.CurrentWeapon == "vikhr" then
        self.VIKHR_ShotsFired  = 0
        self.VIKHR_NextShot    = ct + 0.5
        self.VIKHR_MuzzleIndex = 1
    end
end

function ENT:PickNewWeapon(ct)
    self:EnterPeaceful(ct)
end

-- ============================================================
-- PHYSICAL BULLET SPAWNER
-- ============================================================

function ENT:SpawnPhysicalBullet(muzzlePos, impactPos, bulletIndex)
    self.TracerCounter = self.TracerCounter + 1
    if self.TracerCounter >= 3 then self.TracerCounter = 0 end

    local dir = impactPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local bul = ents.Create("ent_ka52_30mm_bullet")
    if not IsValid(bul) then return end

    bul:SetPos(muzzlePos)
    bul:SetAngles(dir:Angle())
    bul.Firer       = self
    bul.MuzzlePos   = muzzlePos
    bul.BulletDmg   = self.GAU_BulletDamage
    bul.BulletRad   = self.GAU_BlastRadius
    bul.BulletIndex = bulletIndex
    bul.HEIInterval = self.GAU_HEI_Interval

    bul:Spawn()
    bul:Activate()

    self:SpawnMuzzleFX(muzzlePos)
end

-- ============================================================
-- SLOT 1 — 30mm BURST
-- ============================================================

function ENT:Update30mmBurstsSchedule(ct)
    if not self.GAU_BurstTimes then return end
    for i, t in ipairs(self.GAU_BurstTimes) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
        end
    end
end

function ENT:StartGAUBurst()
    local targetPos = self:GetTargetGroundPos()

    local sweepDir = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
    sweepDir:Normalize()

    self.GAU_SweepStartPos = targetPos - sweepDir * self.GAU_SweepHalfLength
    self.GAU_SweepEndPos   = targetPos + sweepDir * self.GAU_SweepHalfLength

    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime(), maxBullets = 3 })
end

function ENT:UpdateActiveGAUBursts(ct)
    if not self.GAU_ActiveBursts then return end
    for idx = #self.GAU_ActiveBursts, 1, -1 do
        local burst = self.GAU_ActiveBursts[idx]
        if not burst then
            table.remove(self.GAU_ActiveBursts, idx)
        elseif ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + self.GAU_BurstDelay
            self:FireSingleGAUBullet(burst.bulletsFired)
            if burst.bulletsFired >= burst.maxBullets then
                table.remove(self.GAU_ActiveBursts, idx)
            end
        end
    end
end

function ENT:FireSingleGAUBullet(bulletIndex)
    local muzzlePos = self:GetMuzzleWorldPos(self.MuzzlePoints[1])

    local impactPos
    if not self.GAU_SweepStartPos then
        impactPos = self:GetTargetGroundPos() + Vector(math.Rand(-300,300), math.Rand(-300,300), 0)
    else
        local fraction = math.Clamp((bulletIndex - 1) / 2, 0, 1)
        local base     = LerpVector(fraction, self.GAU_SweepStartPos, self.GAU_SweepEndPos)
        local jitter   = Vector(
            math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
            math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
            0
        )
        impactPos = base + jitter
    end

    self:SpawnPhysicalBullet(muzzlePos, impactPos, bulletIndex)
end

-- ============================================================
-- SLOT 2 — 30mm SUSTAINED
-- ============================================================

function ENT:Update30mmSustained(ct)
    if ct >= self.WeaponWindowEnd then return end
    if ct < self.SprayPauseUntil then return end

    if self.SprayBurstRoundsLeft <= 0 then
        self.SprayPauseUntil      = ct + math.Rand(self.GAU_SprayPause_Min, self.GAU_SprayPause_Max)
        self.SprayBurstRoundsLeft = math.random(self.GAU_SprayBurstRounds_Min, self.GAU_SprayBurstRounds_Max)
        return
    end

    if ct < self.NextShotTimeSpray then return end

    local muzzlePos = self:GetMuzzleWorldPos(self.MuzzlePoints[1])
    self.NextShotTimeSpray    = ct + self.GAU_Spray_Delay
    self.SprayBulletCount     = self.SprayBulletCount + 1
    self.SprayBurstRoundsLeft = self.SprayBurstRoundsLeft - 1

    local jitter      = self.GAU_SprayJitter
    local finalImpact = self:GetTargetGroundPos() + Vector(math.Rand(-jitter, jitter), math.Rand(-jitter, jitter), 0)
    self:SpawnPhysicalBullet(muzzlePos, finalImpact, self.SprayBulletCount)
end

-- ============================================================
-- SLOT 3 — S-8 ROCKET SALVO
-- ============================================================

function ENT:UpdateS8Salvo(ct)
    if self.S8_ShotsFired >= self.S8_Count then return end
    if ct < self.S8_NextShot then return end

    self.S8_NextShot   = ct + self.S8_Delay
    self.S8_ShotsFired = self.S8_ShotsFired + 1

    local muzzleLocal = self.S8_MuzzlePoints[self.S8_MuzzleIndex]
    self.S8_MuzzleIndex = (self.S8_MuzzleIndex % #self.S8_MuzzlePoints) + 1

    local muzzlePos = self:GetMuzzleWorldPos(muzzleLocal)
    local targetPos = self:GetTargetGroundPos() + Vector(math.Rand(-self.S8_Scatter,self.S8_Scatter), math.Rand(-self.S8_Scatter,self.S8_Scatter), 0)
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create("gb_s8kom_rocket")
    if not IsValid(rocket) then self:Debug("gb_s8kom_rocket failed") return end

    rocket:SetPos(muzzlePos) rocket:SetAngles(dir:Angle()) rocket:SetOwner(self)
    rocket.IsOnPlane = true rocket:Spawn() rocket:Activate()
    rocket.Armed = true rocket.ShouldExplode = true rocket:Launch()
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local rPhys = rocket:GetPhysicsObject() local hPhys = self:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(hPhys) then rPhys:AddVelocity(hPhys:GetVelocity()) end

    self:SpawnMuzzleFX(muzzlePos)
    sound.Play(table.Random(SOUNDS_S8_IGNITE), muzzlePos, 110, math.random(95,105), 1.0)
    timer.Simple(0.1, function() if IsValid(rocket) then sound.Play(table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95,105), 1.0) end end)

    rocket.IdleSound = CreateSound(rocket, SOUND_ROCKET_IDLE)
    if rocket.IdleSound then rocket.IdleSound:Play() rocket.IdleSound:ChangePitch(math.random(90,115),0) rocket.IdleSound:ChangeVolume(0.8,0) end
    rocket.OnRemove  = function(s) if s.IdleSound then s.IdleSound:Stop() end end
    rocket.OnExplode = function(s,p,n) if s.IdleSound then s.IdleSound:Stop() end end

    constraint.NoCollide(rocket, self, 0, 0)
    local ref = rocket
    timer.Simple(0.5, function() if IsValid(ref) and IsValid(self) then constraint.RemoveConstraints(ref,"NoCollide") end end)
end

-- ============================================================
-- SLOT 4 — 9K121 VIKHR ATGM
-- ============================================================

function ENT:UpdateVikhr(ct)
    if self.VIKHR_ShotsFired >= self.VIKHR_Count then return end
    if ct < self.VIKHR_NextShot then return end

    self.VIKHR_NextShot   = ct + self.VIKHR_Delay
    self.VIKHR_ShotsFired = self.VIKHR_ShotsFired + 1

    local muzzleLocal = self.VIKHR_MuzzlePoints[self.VIKHR_MuzzleIndex]
    self.VIKHR_MuzzleIndex = (self.VIKHR_MuzzleIndex % #self.VIKHR_MuzzlePoints) + 1

    local muzzlePos = self:GetMuzzleWorldPos(muzzleLocal)
    local targetPos = self:GetTargetGroundPos() + Vector(math.Rand(-self.VIKHR_Scatter,self.VIKHR_Scatter), math.Rand(-self.VIKHR_Scatter,self.VIKHR_Scatter), 0)
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create("gb_9k121_rocket")
    if not IsValid(rocket) then self:Debug("gb_9k121_rocket failed") return end

    rocket:SetPos(muzzlePos) rocket:SetAngles(dir:Angle()) rocket:SetOwner(self)
    rocket.IsOnPlane = true rocket:Spawn() rocket:Activate()
    rocket.Armed = true rocket.ShouldExplode = true rocket.ShouldExplodeOnImpact = true
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local startpos = self:LocalToWorld(self:OBBCenter())
    local tr = util.TraceHull({start=startpos, endpos=startpos+dir*500000, mins=Vector(-25,-25,-25), maxs=Vector(25,25,25), filter=self})

    local rPhys = rocket:GetPhysicsObject() local hPhys = self:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(hPhys) then rPhys:AddVelocity(hPhys:GetVelocity()) end

    constraint.NoCollide(rocket, self, 0, 0)
    local ref = rocket
    timer.Simple(0.25, function()
        if not IsValid(ref) then return end
        if tr.Hit then
            ref.JDAM = true ref.target = tr.Entity
            ref.targetOffset = IsValid(tr.Entity) and tr.Entity:WorldToLocal(tr.HitPos) or tr.HitPos
            ref.dropping = true
        end
        ref.Armed = true ref:Launch() ref:SetCollisionGroup(0)
    end)

    self:SpawnMuzzleFX(muzzlePos)
    sound.Play(table.Random(SOUNDS_ATGM_IGNITE), muzzlePos, 0, 100, 1.0)
    timer.Simple(0.1, function() if IsValid(rocket) then sound.Play(table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95,105), 1.0) end end)

    rocket.IdleSound = CreateSound(rocket, SOUND_ROCKET_IDLE)
    if rocket.IdleSound then rocket.IdleSound:Play() rocket.IdleSound:ChangePitch(math.random(85,110),0) rocket.IdleSound:ChangeVolume(0.9,0) end
    rocket.OnRemove  = function(s) if s.IdleLoop then s.IdleSound:Stop() end end
    rocket.OnExplode = function(s,p,n)
        if s.IdleSound then s.IdleSound:Stop() end
        local hp = p or s:GetPos()
        local e1=EffectData() e1:SetOrigin(hp) e1:SetScale(4) e1:SetMagnitude(4) e1:SetRadius(400) util.Effect("500lb_air",e1,true,true)
        local e2=EffectData() e2:SetOrigin(hp+Vector(0,0,60)) e2:SetScale(3) e2:SetMagnitude(3) e2:SetRadius(300) util.Effect("500lb_air",e2,true,true)
        local e3=EffectData() e3:SetOrigin(hp) e3:SetScale(4) e3:SetMagnitude(4) e3:SetRadius(400) util.Effect("HelicopterMegaBomb",e3,true,true)
    end
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = { self }
    local maxIter    = 0

    while maxIter < 100 do
        local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else break end
        maxIter = maxIter + 1
    end

    return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
    if self.IdleLoop then self.IdleLoop:Stop() self.IdleLoop = nil end
end