AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

local GAU_IMPACT_SOUNDS = {
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
}

local GAU_BRRT_SOUNDS = {
    "gunsounds/brrt_01.wav",
    "gunsounds/brrt_02.wav",
    "gunsounds/brrt_03.wav",
    "gunsounds/brrt_04.wav",
}

local SOUND_105_IMPACT = "killstreak_explosions/105_explosion.wav"

local PEACEFUL_MIN = 4
local PEACEFUL_MAX = 7

local JASSM_MAX_STOCK = 6

local TUMBLE_GRAVITY = 600

-- JASSM drop safety constants (mirrored from C-17)
local JASSM_MIN_FREEFALL_CLEARANCE = 800
local JASSM_SHA_FLOOR              = 400
local JASSM_MIN_DROP_HEIGHT        = JASSM_SHA_FLOOR * 1.25 + JASSM_MIN_FREEFALL_CLEARANCE

util.AddNetworkString("bombin_plane_damage_tier")
util.AddNetworkString("bombin_plane_spatial_sound")
util.AddNetworkString("bombin_105mm_direct_sound")
util.AddNetworkString("bombin_muzzle_flash")
util.AddNetworkString("bombin_muzzle_flash_40mm")

local SOUND_SPEED     = 8200
local MAX_HEAR_DIST   = 88000
local VOL_FALLOFF_EXP = 0.01
local NEAR_OFFSET     = 40
local WEAPON_LEVEL    = 150

local function PrecacheWeaponSounds()
    for _, s in ipairs(GAU_BRRT_SOUNDS) do util.PrecacheSound(s) end
    util.PrecacheSound("killstreak_rewards/ac-130_40mm_fire.wav")
    util.PrecacheSound("killstreak_rewards/ac-130_105mm_fire.wav")
    util.PrecacheSound(SOUND_105_IMPACT)
end
PrecacheWeaponSounds()

local pending_sounds = {}

function ENT:EmitSpatialSound( soundPath, originPos, soundLevel, pitch, baseVol )
    local sendAt = CurTime()
    for _, ply in ipairs( player.GetAll() ) do
        if not IsValid(ply) then continue end
        local plyPos  = ply:GetPos()
        local toPlane = originPos - plyPos
        local dist    = toPlane:Length()
        if dist > MAX_HEAR_DIST then continue end
        local t   = dist / MAX_HEAR_DIST
        local vol = baseVol * ( 1 - t ) ^ VOL_FALLOFF_EXP
        local nearPos
        if dist > 0.1 then
            nearPos = plyPos + ( toPlane / dist ) * NEAR_OFFSET
        else
            nearPos = plyPos
        end
        local delay = dist / SOUND_SPEED
        pending_sounds[ #pending_sounds + 1 ] = {
            sendTime  = sendAt + delay,
            ply       = ply,
            soundPath = soundPath,
            nearPos   = nearPos,
            level     = soundLevel,
            pitch     = pitch,
            volume    = vol,
        }
    end
end

local function FlushPendingSounds()
    if #pending_sounds == 0 then return end
    local ct   = CurTime()
    local keep = {}
    for _, entry in ipairs( pending_sounds ) do
        if ct >= entry.sendTime then
            if IsValid( entry.ply ) then
                net.Start("bombin_plane_spatial_sound")
                    net.WriteString ( entry.soundPath )
                    net.WriteVector ( entry.nearPos   )
                    net.WriteUInt   ( entry.level, 8  )
                    net.WriteUInt   ( entry.pitch, 8  )
                    net.WriteFloat  ( entry.volume    )
                net.Send( entry.ply )
            end
        else
            keep[ #keep + 1 ] = entry
        end
    end
    pending_sounds = keep
end

local Shells105 = {}

hook.Add("EntityRemoved", "bombin_105mm_shell_sound", function(ent)
    if not IsValid(ent) then return end
    local data = Shells105[ent:EntIndex()]
    if not data then return end
    local pos = ent:GetPos()
    Shells105[ent:EntIndex()] = nil
    net.Start("bombin_105mm_direct_sound")
        net.WriteVector( pos )
        net.WriteUInt  ( WEAPON_LEVEL, 8 )
        net.WriteUInt  ( math.random(96, 104), 8 )
    net.Broadcast()
end)

function ENT:Debug(msg)
    print("[Bombin Support Plane ENT] " .. msg)
end

ENT.WeaponWindow        = 10
ENT.AimConeDegrees      = 10

ENT.GAU_FirstBurstTime  = 0
ENT.GAU_SecondBurstTime = 5
ENT.GAU_BurstCount      = 25
ENT.GAU_BurstDelay      = 0.033
ENT.GAU_Caliber         = "wac_base_20mm"
ENT.GAU_TracerColor     = nil
ENT.GAU_DamageMul       = 0.5
ENT.GAU_RadiusMul       = 0.05
ENT.GAU_SweepHalfLength = 600
ENT.GAU_JitterAmount    = 200
ENT.GAU_SpraySoundDelay = 1.3

ENT.GAU_TargetOffsetMin = 300
ENT.GAU_TargetOffsetMax = 900

ENT.GAU_HEI_Interval    = 900
ENT.GAU_BulletDamage    = 40
ENT.GAU_BlastRadius     = 80

ENT.GUN40_Delay          = 0.5
ENT.GUN105_Delay         = 6
ENT.GUN40_ShellVelocity  = 6000
ENT.GUN105_ShellVelocity = 5000
ENT.GUN40_Damage         = 300
ENT.GUN105_Damage        = 3700
ENT.GUN40_TNT            = 0.5
ENT.GUN105_TNT           = 2.5

ENT.GUN40_Scatter        = 600
ENT.GUN105_Scatter       = 400

ENT.GAU_Spray_Delay        = 0.033
ENT.GAU_SprayPauseDuration = 0.6

ENT.MuzzleForwardOffset  = 250
ENT.MuzzleSideOffset     = -60

ENT.GAU_MuzzleForwardOffset = -300
ENT.GAU_MuzzleSideOffset    = -250
ENT.GAU_MuzzleUpOffset      = 50

ENT.Plane_Ambient_SoundPath = "ac/bomber_engine_high.wav"

ENT.JASSM_AltOffset  = 500
ENT.JASSM_TailOffset = Vector(-420, 0, 0)

ENT.MaxHP = 8000
ENT.DamageTierThresholds = { 0.75, 0.50, 0.25 }

-- ============================================================
-- OBSTACLE EVASION CONSTANTS
-- EVADE_PROBE_DIST   : how far each horizontal ray looks ahead
-- EVADE_NUM_RAYS     : angular resolution of the sweep
-- EVADE_PUSH_GAIN    : repulsion weight per blocked ray
-- EVADE_TURN_RATE    : max evasion yaw rate in degrees/second
-- EVADE_SMOOTH       : lerp speed toward desired evasion rate
-- EVADE_INTERVAL     : seconds between full probe sweeps
-- ORBIT_TURN_RATE    : max orbit-correction yaw in degrees/second
--                      (slow, heavy-aircraft feel)
-- ============================================================
local EVADE_PROBE_DIST  = 6000
local EVADE_NUM_RAYS    = 8
local EVADE_PUSH_GAIN   = 2.5
local EVADE_TURN_RATE   = 6.0   -- deg/s max from evasion
local EVADE_SMOOTH      = 0.04  -- low = very gradual banking
local EVADE_INTERVAL    = 0.25

local ORBIT_TURN_RATE   = 3.0   -- deg/s max for orbit correction (slow!)

-- ============================================================
-- ProbeObstacles
-- Casts EVADE_NUM_RAYS horizontal rays at flight altitude.
-- Accumulates a repulsion vector away from blocked directions.
-- Stores a desired signed yaw rate (deg/s) in EvadeYawRate.
-- ============================================================
function ENT:ProbeObstacles()
    local pos    = self:GetPos()
    local skyZ   = self.sky or pos.z
    local origin = Vector(pos.x, pos.y, skyZ)
    local step   = 360 / EVADE_NUM_RAYS

    local pushX, pushY = 0, 0

    for i = 0, EVADE_NUM_RAYS - 1 do
        local rad = math.rad(i * step)
        local dir = Vector(math.cos(rad), math.sin(rad), 0)
        local tr  = util.TraceLine({
            start  = origin,
            endpos = origin + dir * EVADE_PROBE_DIST,
            filter = self,
            mask   = MASK_SOLID_BRUSHONLY,
        })

        if tr.Hit and not tr.HitSky then
            -- Closer hits push harder (fraction=0 is right next to us)
            local weight = (1 - tr.Fraction) * EVADE_PUSH_GAIN
            pushX = pushX - dir.x * weight
            pushY = pushY - dir.y * weight
        end
    end

    local pushLen = math.sqrt(pushX * pushX + pushY * pushY)
    if pushLen > 0.01 then
        -- Desired heading = direction of repulsion vector
        local desiredYaw  = math.deg(math.atan2(pushY, pushX))
        local currentYaw  = self.ang and self.ang.y or self:GetAngles().y
        local delta       = math.NormalizeAngle(desiredYaw - currentYaw)
        -- Convert angular gap into a desired yaw rate (deg/s), capped
        self.EvadeYawRate = math.Clamp(delta * 0.4, -EVADE_TURN_RATE, EVADE_TURN_RATE)
    else
        self.EvadeYawRate = 0
    end
end

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos", self:GetPos())
    self.CallDir      = self:GetVar("CallDir", Vector(1, 0, 0))
    self.Lifetime     = self:GetVar("Lifetime", 40)
    self.Speed        = self:GetVar("Speed", 300)
    self.OrbitRadius  = self:GetVar("OrbitRadius", 3000)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 6000)

    self.MaxHP = self.MaxHP or ENT.MaxHP or 8000

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1, 0, 0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then self:Debug("Fallback spawnPos out of world too") self:Remove() return end

    self:SetModel("models/military2/air/air_130_l.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    self:SetPos(spawnPos)
    self.LastPos = spawnPos

    self:SetNWInt("HP",    self.MaxHP)
    self:SetNWInt("MaxHP", self.MaxHP)

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y - 90, 0))
    self.ang = self:GetAngles()

    self.flightYaw = ang.y - 90

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    self.AltDriftRange    = 300
    self.AltDriftLerp     = 0.001

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 5
    self.SmoothedRoll    = 0
    self.SmoothedPitch   = 0
    self.PrevYaw         = self:GetAngles().y

    -- Evasion state
    self.EvadeYawRate       = 0   -- desired deg/s from obstacle probe
    self.EvadeYawSmoothed   = 0   -- smoothed actual deg/s being applied
    self.NextProbeTime      = CurTime() + EVADE_INTERVAL

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    self.IdleLoop = CreateSound(self, "ac-130_kill_sounds/AC130_idle_inside.mp3")
    if self.IdleLoop then self.IdleLoop:SetSoundLevel(60) self.IdleLoop:Play() end

    self.PlaneAmbientLoop = CreateSound(self, self.Plane_Ambient_SoundPath)
    if self.PlaneAmbientLoop then
        self.PlaneAmbientLoop:SetSoundLevel(120)
        self.PlaneAmbientLoop:Play()
    end

    self:Debug("Spawned at " .. tostring(spawnPos))

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0
    self.NextShotTime40     = 0
    self.NextShotTime105    = 0
    self.NextShotTimeSpray  = 0
    self.NextSpraySoundTime = 0
    self.SprayBulletCount   = 0
    self.GAU_SprayBurstEnd  = 0
    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}
    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.IsDestroyed        = false
    self.DamageTier         = 0
    self.JASSM_DeployCount  = 0
    self.JASSM_Stock        = JASSM_MAX_STOCK
    self.JASSM_SalvoFired   = 0
    self.IsPeaceful         = false
    self.PeacefulUntil      = 0

    self.IsTumbling        = false
    self.TumbleLastTime    = 0
    self.TumbleGroundZ     = ground
    self.TumbleCrashed     = false
    self._CrashFired       = false
    self.TumbleVelocity    = Vector(0, 0, 0)
    self.TumbleAngVelocity = Vector(0, 0, 0)

    self:SetNWInt("JASSM_Spent", 0)
    self:SetNWInt("JASSM_Max",   JASSM_MAX_STOCK)

    if not HasGred() then self:Debug("WARNING: Gred base not found; falling back to rpg_missile.") end
end

function ENT:BroadcastDamageTier(tier)
    net.Start("bombin_plane_damage_tier")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteUInt(tier, 2)
    net.Broadcast()
end

function ENT:CheckDamageTier(hp)
    local fraction = hp / (self.MaxHP or 8000)
    local newTier  = 0
    for i, thresh in ipairs(self.DamageTierThresholds or ENT.DamageTierThresholds) do
        if fraction <= thresh then newTier = i end
    end
    if newTier ~= self.DamageTier then
        self.DamageTier = newTier
        self:BroadcastDamageTier(newTier)
        self:Debug("Damage tier -> " .. tostring(newTier) .. " (HP " .. tostring(hp) .. ")")
    end
end

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end
    local hp = self:GetNWInt("HP", self.MaxHP or 8000)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    self:Debug("Hit! HP remaining: " .. tostring(hp))
    self:CheckDamageTier(hp)
    if hp <= 0 then self:Debug("Shot down!") self:DestroyPlane() end
end

-- ============================================================
-- TUMBLE
-- ============================================================
function ENT:StartTumble()
    self.IsTumbling     = true
    self.TumbleLastTime = CurTime()
    self.TumbleCrashed  = false

    local gnd = self:FindGround(self:GetPos())
    if gnd ~= -1 then self.TumbleGroundZ = gnd end

    local fwd = Angle(0, self.flightYaw or self.ang.y, 0):Forward()
    local spd = self.Speed or 300
    self.TumbleVelocity = Vector(fwd.x * spd, fwd.y * spd, -80)

    local function sign() return (math.random(2) == 1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand(8,  18) * sign(),
        math.Rand(3,   8) * sign(),
        math.Rand(20, 40) * sign()
    )

    self:SetMoveType(MOVETYPE_NONE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(false)
        phys:SetVelocity(Vector(0, 0, 0))
        phys:SetAngleVelocity(Vector(0, 0, 0))
        phys:Sleep()
    end

    local pos = self:GetPos()
    local ed  = EffectData()
    ed:SetOrigin(pos) ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_4.wav", pos, 135, 95, 1.0)
end

function ENT:UpdateTumble(ct)
    if not IsValid(self) then return end
    if not self.IsTumbling or self.TumbleCrashed then return end

    local dt = ct - self.TumbleLastTime
    self.TumbleLastTime = ct
    if dt <= 0 or dt > 0.2 then return end

    self.TumbleVelocity.z = self.TumbleVelocity.z - TUMBLE_GRAVITY * dt

    local pos    = self:GetPos()
    local newPos = pos + self.TumbleVelocity * dt

    local av = self.TumbleAngVelocity
    self.ang = Angle(
        self.ang.p + av.x * dt,
        self.ang.y + av.y * dt,
        self.ang.r + av.z * dt
    )

    local hitGround = newPos.z <= (self.TumbleGroundZ or -16384) + 200
    local hitWall   = false
    if not hitGround then
        local tr = util.TraceLine({ start = pos, endpos = newPos, filter = self, mask = MASK_SOLID_BRUSHONLY })
        hitWall = tr.HitWorld
    end

    if hitGround or hitWall then
        self.TumbleCrashed = true
        self:CrashExplode()
        return
    end

    self:SetPos(newPos)
    self:SetAngles(self.ang)
end

-- ============================================================
-- GIB SPAWNER
-- ============================================================
local GIB_MODELS = {
    "models/fonv/vehicles/b29/parts/b29_partwing.mdl",
    "models/fonv/vehicles/b29/parts/b29_partwing.mdl",
    "models/fonv/vehicles/b29/parts/b29_partnose.mdl",
    "models/fonv/vehicles/b29/parts/b29_partprop.mdl",
    "models/fonv/vehicles/b29/parts/b29_partprop.mdl",
    "models/fonv/vehicles/b29/parts/b29_partprop.mdl",
    "models/fonv/vehicles/b29/parts/b29_parttube.mdl",
}

local GIB_LIFETIME = 40

local function SpawnGibs(origin)
    for idx, mdl in ipairs(GIB_MODELS) do
        timer.Simple((idx - 1) * 0.1, function()
            local gib = ents.Create("prop_physics")
            if not IsValid(gib) then return end

            local pos = origin + Vector(
                math.Rand(-150, 150),
                math.Rand(-150, 150),
                math.Rand(  20, 100)
            )
            if not util.IsInWorld(pos) then pos = origin end

            gib:SetModel(mdl)
            gib:SetPos(pos)
            gib:SetAngles(Angle(math.Rand(0, 360), math.Rand(0, 360), math.Rand(0, 360)))
            gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            gib:Spawn()
            gib:Activate()

            local phys = gib:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetMass(2000)
                phys:SetDragCoefficient(0)
                phys:SetAngleDragCoefficient(0)
                phys:EnableGravity(true)
                phys:Wake()
                phys:ApplyForceCenter(Vector(
                    math.Rand(-400, 400),
                    math.Rand(-400, 400),
                    math.Rand( 300, 900)
                ) * 2000)
                phys:ApplyTorqueCenter(Vector(
                    math.Rand(-2000, 2000),
                    math.Rand(-2000, 2000),
                    math.Rand(-2000, 2000)
                ))
            end

            timer.Simple(0, function()
                if IsValid(gib) then gib:Ignite(GIB_LIFETIME, 0) end
            end)

            timer.Simple(GIB_LIFETIME, function()
                if IsValid(gib) then gib:Remove() end
            end)
        end)
    end
end

function ENT:CrashExplode()
    if self._CrashFired then return end
    self._CrashFired   = true
    self.TumbleCrashed = true

    local pos    = Vector(self:GetPos())
    local entIdx = self:EntIndex()

    local function BigBlast(bpos)
        local ed1 = EffectData()
        ed1:SetOrigin(bpos) ed1:SetScale(7) ed1:SetMagnitude(7) ed1:SetRadius(700)
        util.Effect("HelicopterMegaBomb", ed1, true, true)

        local ed2 = EffectData()
        ed2:SetOrigin(bpos + Vector(0, 0, 90)) ed2:SetScale(6) ed2:SetMagnitude(6) ed2:SetRadius(600)
        util.Effect("500lb_air", ed2, true, true)

        local ed3 = EffectData()
        ed3:SetOrigin(bpos + Vector(0, 0, 200)) ed3:SetScale(5) ed3:SetMagnitude(5) ed3:SetRadius(500)
        util.Effect("500lb_air", ed3, true, true)

        sound.Play("ambient/explosions/explode_8.wav", bpos, 145, math.random(85, 95),  1.0)
        sound.Play("ambient/explosions/explode_4.wav", bpos, 140, math.random(90, 105), 0.9)
        util.BlastDamage(game.GetWorld(), game.GetWorld(), bpos, 350, 180)
    end

    BigBlast(pos)
    SpawnGibs(pos)

    local delays  = { 0.9, 1.9, 3.1 }
    local offsets = {
        Vector( 280,   0,   0),
        Vector(-300,   0,  60),
        Vector(   0, 150, -40),
    }
    for i, delay in ipairs(delays) do
        local off = offsets[i]
        timer.Simple(delay, function()
            local ent = Entity(entIdx)
            local bpos
            if IsValid(ent) and not ent:IsMarkedForDeletion() then
                bpos = ent:GetPos()
                    + ent:GetAngles():Forward() * off.x
                    + ent:GetAngles():Right()   * off.y
                    + ent:GetAngles():Up()      * off.z
            else
                bpos = pos + Vector(0, 0, -300 * delay)
            end
            BigBlast(bpos)
        end)
    end

    timer.Simple(3.5, function()
        local ent = Entity(entIdx)
        if IsValid(ent) then ent:Remove() end
    end)
end

-- ============================================================
-- DESTROY
-- ============================================================
function ENT:DestroyPlane()
    if self.IsDestroyed then return end
    self.IsDestroyed = true

    if self.IdleLoop         then self.IdleLoop:Stop()         self.IdleLoop         = nil end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() self.PlaneAmbientLoop = nil end
    self:StopSprayLoop()
    self:BroadcastDamageTier(0)

    self:StartTumble()

    local entIdx = self:EntIndex()
    timer.Simple(20, function()
        local ent = Entity(entIdx)
        if IsValid(ent)
            and not ent:IsMarkedForDeletion()
            and ent:GetClass() == "ent_bombin_support_plane"
            and not ent._CrashFired
        then
            ent:CrashExplode()
        end
    end)
end

-- ============================================================
-- THINK
-- ============================================================
function ENT:Think()
    if not self.DieTime or not self.SpawnTime then self:NextThink(CurTime() + 0.1) return true end
    local ct = CurTime()

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
    FlushPendingSounds()

    -- Obstacle probe on its own interval
    if ct >= (self.NextProbeTime or 0) then
        self:ProbeObstacles()
        self.NextProbeTime = ct + EVADE_INTERVAL
    end

    self:HandleWeaponWindow(ct)
    self:UpdateActiveGAUBursts(ct)
    self:NextThink(ct)
    return true
end

function ENT:PhysicsUpdate(phys)
    if self.IsTumbling or self.IsDestroyed then return end
    if not self.DieTime or not self.sky then return end
    if CurTime() >= self.DieTime then self:Remove() return end

    local dt  = engine.TickInterval()
    local pos = self:GetPos()
    self.LastPos = pos

    -- Altitude drift
    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
    self.JitterPhase     = self.JitterPhase + 0.02
    local liveAlt        = self.AltDriftCurrent + math.sin(self.JitterPhase) * self.JitterAmplitude

    -- --------------------------------------------------------
    -- ORBIT CORRECTION
    -- dt-scaled so it is independent of tick rate.
    -- ORBIT_TURN_RATE deg/s = very slow, heavy-aircraft feel.
    -- Only fires when outside the orbit radius.
    -- --------------------------------------------------------
    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)
    local orbitYaw   = 0
    if dist > self.OrbitRadius then
        orbitYaw = ORBIT_TURN_RATE * dt  -- degrees this tick
    end

    -- --------------------------------------------------------
    -- EVASION
    -- EvadeYawRate is desired deg/s set by ProbeObstacles.
    -- EvadeYawSmoothed lerps toward it slowly (heavy banking).
    -- Multiply by dt to get degrees this tick.
    -- --------------------------------------------------------
    self.EvadeYawSmoothed = Lerp(EVADE_SMOOTH, self.EvadeYawSmoothed or 0, self.EvadeYawRate or 0)
    local evasionYaw      = self.EvadeYawSmoothed * dt

    -- --------------------------------------------------------
    -- NOTE: skyYaw block removed.
    -- util.QuickTrace toward sky on maps with a sky ceiling
    -- returned HitSky=true almost every tick, adding 0.3 deg
    -- per tick (~20 deg/s) regardless of direction, which spun
    -- the plane into the skybox wall. The probe system handles
    -- solid walls; the sky ceiling is never a solid brush so
    -- it will never appear in MASK_SOLID_BRUSHONLY traces.
    -- --------------------------------------------------------

    self.ang = self.ang + Angle(0, orbitYaw + evasionYaw, 0)

    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw
    self.flightYaw    = currentYaw

    local targetRoll  = math.Clamp(rawYawDelta * -18, -15, 15)
    local rollLerp    = rawYawDelta ~= 0 and 0.08 or 0.04
    self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

    local forward      = self.ang:Forward()
    local vel          = forward * self.Speed
    local targetPitch  = math.Clamp(-vel.z * 0.02, -8, 8)
    self.SmoothedPitch = Lerp(0.03, self.SmoothedPitch, targetPitch)

    local finalAng = Angle(self.SmoothedPitch, self.ang.y, self.SmoothedRoll)
    phys:SetAngles(finalAng)
    phys:SetPos(Vector(pos.x + vel.x * dt, pos.y + vel.y * dt, liveAlt))
    phys:SetVelocity(vel)
end

function ENT:HandleWeaponWindow(ct)
    if self.IsPeaceful then
        if ct >= self.PeacefulUntil then
            self.IsPeaceful = false
            self:ArmWeapon(self._PendingWeapon, ct)
            self._PendingWeapon = nil
        end
        return
    end
    if not self.CurrentWeapon then self:EnterPeaceful(ct) return end
    if ct >= self.WeaponWindowEnd then self:EnterPeaceful(ct) return end
    if     self.CurrentWeapon == "25mm"       then self:Update25mmBurstsSchedule(ct)
    elseif self.CurrentWeapon == "40mm"       then self:Update40mm(ct)
    elseif self.CurrentWeapon == "105mm"      then self:Update105mm(ct)
    elseif self.CurrentWeapon == "25mm_spray" then self:Update25mmSpray(ct)
    elseif self.CurrentWeapon == "jassm"      then self:UpdateJASSM(ct) end
end

function ENT:EnterPeaceful(ct)
    self:StopSprayLoop()
    self.CurrentWeapon  = nil
    self.IsPeaceful     = true
    self.PeacefulUntil  = ct + math.Rand(PEACEFUL_MIN, PEACEFUL_MAX)
    self._PendingWeapon = self:RollWeapon()
    self:Debug("Peaceful mode for " .. string.format("%.1f", self.PeacefulUntil - ct) .. "s, next: " .. self._PendingWeapon)
end

function ENT:RollWeapon()
    if (self.JASSM_Stock or 0) <= 0 then
        local roll = math.random(1, 4)
        if     roll == 1 then return "25mm"
        elseif roll == 2 then return "40mm"
        elseif roll == 3 then return "105mm"
        else                   return "25mm_spray" end
    end
    local roll = math.random(1, 5)
    if     roll == 1 then return "25mm"
    elseif roll == 2 then return "40mm"
    elseif roll == 3 then return "105mm"
    elseif roll == 4 then return "25mm_spray"
    else                   return "jassm" end
end

function ENT:ArmWeapon(weapon, ct)
    weapon = weapon or self:RollWeapon()
    if weapon == "jassm" and (self.JASSM_Stock or 0) <= 0 then weapon = self:RollWeapon() end
    self.CurrentWeapon   = weapon
    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Armed: " .. self.CurrentWeapon)
    if self.CurrentWeapon == "25mm" then
        self.GAU_BurstTimes   = { ct + self.GAU_FirstBurstTime, ct + self.GAU_SecondBurstTime }
        self.GAU_BurstsFired  = 0
        self.GAU_ActiveBursts = {}
    elseif self.CurrentWeapon == "40mm" then
        self.NextShotTime40 = ct + 0.3
    elseif self.CurrentWeapon == "105mm" then
        self.NextShotTime105 = ct + 0.5
    elseif self.CurrentWeapon == "25mm_spray" then
        self.NextShotTimeSpray  = ct
        self.NextSpraySoundTime = ct
        self.SprayBulletCount   = 0
        self.GAU_SprayBurstEnd  = 0
        local targetPos = self:GetTargetGroundPos()
        local sweepDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
        sweepDir:Normalize()
        self.GAU_SweepStartPos = targetPos - sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepEndPos   = targetPos + sweepDir * self.GAU_SweepHalfLength
    elseif self.CurrentWeapon == "jassm" then
        self.JASSM_SalvoFired = 0
    end
end

function ENT:PickNewWeapon(ct) self:EnterPeaceful(ct) end

function ENT:StartSprayLoop() self.NextSpraySoundTime = CurTime() end
function ENT:StopSprayLoop()
    self.NextSpraySoundTime = 0
    self.GAU_SprayBurstEnd  = 0
end

function ENT:PlaySpraySoundAndFlash(ct)
    self:EmitSpatialSound(
        table.Random(GAU_BRRT_SOUNDS), self.CenterPos, WEAPON_LEVEL, math.random(96, 104), 1.0
    )
    self:SpawnGAUMuzzleFX()
    local fireDuration      = self.GAU_SpraySoundDelay - self.GAU_SprayPauseDuration
    self.GAU_SprayBurstEnd  = ct + fireDuration
    self.NextShotTimeSpray  = ct
    self.NextSpraySoundTime = ct + self.GAU_SpraySoundDelay
end

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
    local target  = self:GetPrimaryTarget()
    local basePos
    if IsValid(target) then
        basePos = target:GetPos()
    else
        local tr = util.QuickTrace(Vector(self.CenterPos.x, self.CenterPos.y, self.sky), Vector(0,0,-30000), self)
        basePos = tr.HitPos
    end
    local offsetDist = math.Rand(self.GAU_TargetOffsetMin, self.GAU_TargetOffsetMax)
    local offsetDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if offsetDir:LengthSqr() < 0.01 then offsetDir = Vector(1,0,0) end
    offsetDir:Normalize()
    return basePos + offsetDir * offsetDist
end

function ENT:GetGAUMuzzlePos()
    local pos   = self:GetPos()
    local ang   = self:GetAngles()
    return pos
        + ang:Forward() * self.GAU_MuzzleForwardOffset
        + ang:Right()   * self.GAU_MuzzleSideOffset
        + ang:Up()      * self.GAU_MuzzleUpOffset
end

function ENT:GetMuzzlePos()
    local pos     = self:GetPos()
    local ang     = self:GetAngles()
    local forward = ang:Forward()
    local right   = ang:Right()
    local muzzle  = pos + forward * self.MuzzleForwardOffset + right * self.MuzzleSideOffset
    muzzle.z      = self.sky
    return muzzle
end

function ENT:SpawnGAUMuzzleFX()
    local worldPos = self:GetGAUMuzzlePos()
    local localPos = self:WorldToLocal(worldPos)
    local ang      = self:GetAngles()

    net.Start("bombin_muzzle_flash")
        net.WriteUInt  (self:EntIndex(), 16)
        net.WriteVector(localPos)
        net.WriteVector(worldPos)
    net.Broadcast()

    for _ = 1, 2 do
        local sp = EffectData()
        sp:SetOrigin(worldPos + Vector(math.Rand(-4,4), math.Rand(-4,4), 0))
        sp:SetNormal(ang:Up()) sp:SetScale(1) sp:SetMagnitude(1) sp:SetRadius(8)
        util.Effect("ManhackSparks", sp, true, true)
    end
end

function ENT:Spawn40mmMuzzleFX()
    local worldPos = self:GetMuzzlePos()
    local localPos = self:WorldToLocal(worldPos)
    local ang      = self:GetAngles()

    net.Start("bombin_muzzle_flash_40mm")
        net.WriteUInt  (self:EntIndex(), 16)
        net.WriteVector(localPos)
        net.WriteVector(worldPos)
    net.Broadcast()

    for _ = 1, 3 do
        local sp = EffectData()
        sp:SetOrigin(worldPos + Vector(math.Rand(-8,8), math.Rand(-8,8), math.Rand(-4,4)))
        sp:SetNormal(ang:Up()) sp:SetScale(2) sp:SetMagnitude(2) sp:SetRadius(20)
        util.Effect("ManhackSparks", sp, true, true)
    end
end

function ENT:SpawnHeavyMuzzleFX(scale)
    local worldPos = self:GetMuzzlePos()
    local ang      = self:GetAngles()
    local ed = EffectData()
    ed:SetOrigin(worldPos)
    ed:SetNormal(ang:Forward())
    ed:SetScale(scale)
    ed:SetMagnitude(scale)
    ed:SetRadius(20 * scale)
    util.Effect("cball_explode", ed, true, true)
end

function ENT:FireGAUBulletAt(muzzlePos, impactPos, bulletIndex)
    local dir = impactPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()
    local bullet = ents.Create("ent_bombin_gau_bullet")
    if not IsValid(bullet) then return end
    bullet:SetPos(muzzlePos)
    bullet:SetAngles(dir:Angle())
    bullet.Firer       = self
    bullet.MuzzlePos   = muzzlePos
    bullet.BulletIndex = bulletIndex or 1
    bullet.HEIInterval = self.GAU_HEI_Interval
    bullet.BulletRad   = self.GAU_BlastRadius
    bullet.BulletDmg   = self.GAU_BulletDamage
    bullet:Spawn()
    bullet:Activate()
end

function ENT:Update25mmBurstsSchedule(ct)
    if not self.GAU_BurstTimes then return end
    for i, t in ipairs(self.GAU_BurstTimes) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
            self.GAU_BurstsFired   = self.GAU_BurstsFired + 1
        end
    end
end

function ENT:StartGAUBurst()
    local targetPos = self:GetTargetGroundPos()
    local sweepDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
    sweepDir:Normalize()
    self.GAU_SweepStartPos = targetPos - sweepDir * self.GAU_SweepHalfLength
    self.GAU_SweepEndPos   = targetPos + sweepDir * self.GAU_SweepHalfLength
    self:SpawnGAUMuzzleFX()
    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })
    self:EmitSpatialSound(
        table.Random(GAU_BRRT_SOUNDS), self.CenterPos, WEAPON_LEVEL, math.random(96, 104), 1.0
    )
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
            self:SpawnGAUMuzzleFX()
            self:FireSingleGAUBullet(burst.bulletsFired)
            if burst.bulletsFired >= self.GAU_BurstCount then
                table.remove(self.GAU_ActiveBursts, idx)
            end
        end
    end
end

function ENT:FireSingleGAUBullet(bulletIndex)
    if not self.GAU_SweepStartPos then return end
    local fraction   = math.Clamp((bulletIndex - 1) / (self.GAU_BurstCount - 1), 0, 1)
    local baseImpact = LerpVector(fraction, self.GAU_SweepStartPos, self.GAU_SweepEndPos)
    local jitter     = Vector(
        math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
        math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount), 0
    )
    local muzzlePos = self:GetGAUMuzzlePos()
    self:FireGAUBulletAt(muzzlePos, baseImpact + jitter, bulletIndex)
end

function ENT:Update25mmSpray(ct)
    if ct >= self.WeaponWindowEnd then self:StopSprayLoop() return end
    if self.NextSpraySoundTime > 0 and ct >= self.NextSpraySoundTime then
        self:PlaySpraySoundAndFlash(ct)
    end
    if ct >= (self.GAU_SprayBurstEnd or 0) then return end
    if ct < self.NextShotTimeSpray then return end
    self.NextShotTimeSpray = ct + self.GAU_Spray_Delay
    self.SprayBulletCount  = self.SprayBulletCount + 1
    self:SpawnGAUMuzzleFX()
    local targetPos   = self:GetTargetGroundPos()
    local finalImpact = targetPos + Vector(
        math.Rand(-self.GAU_JitterAmount * 2, self.GAU_JitterAmount * 2),
        math.Rand(-self.GAU_JitterAmount * 2, self.GAU_JitterAmount * 2), 0
    )
    self:FireGAUBulletAt(self:GetGAUMuzzlePos(), finalImpact, self.SprayBulletCount)
end

function ENT:Update40mm(ct)
    if not self.NextShotTime40 or ct < self.NextShotTime40 then return end
    self.NextShotTime40 = ct + self.GUN40_Delay
    local muzzlePos = self:GetMuzzlePos()
    local aimTarget = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.GUN40_Scatter, self.GUN40_Scatter),
        math.Rand(-self.GUN40_Scatter, self.GUN40_Scatter), 0)
    local dir = aimTarget - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()
    if HasGred() then
        local shell = gred.CreateShell(muzzlePos, dir:Angle(), self, { self }, 40, "HE", 800, 0.9, "yellow", self.GUN40_Damage, nil, self.GUN40_TNT)
        if IsValid(shell) then
            if shell.Arm then shell:Arm() end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed = true shell.ShouldExplode = true
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then phys:EnableGravity(true) phys:SetVelocity(dir * self.GUN40_ShellVelocity) end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos) m:SetAngles(dir:Angle()) m:SetOwner(self) m:Spawn() m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1600) end
        end
    end
    self:Spawn40mmMuzzleFX()
    self:EmitSpatialSound(
        "killstreak_rewards/ac-130_40mm_fire.wav", self.CenterPos, WEAPON_LEVEL, math.random(96,104), 1.0
    )
end

function ENT:Spawn105mmEffects(pos)
    local ed1 = EffectData() ed1:SetOrigin(pos) ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600) util.Effect("500lb_air", ed1, true, true)
    local ed2 = EffectData() ed2:SetOrigin(pos + Vector(0,0,80)) ed2:SetScale(5) ed2:SetMagnitude(5) ed2:SetRadius(500) util.Effect("500lb_air", ed2, true, true)
    local ed3 = EffectData() ed3:SetOrigin(pos + Vector(0,0,180)) ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400) util.Effect("500lb_air", ed3, true, true)
    local ed4 = EffectData() ed4:SetOrigin(pos) ed4:SetScale(6) ed4:SetMagnitude(6) ed4:SetRadius(600) util.Effect("HelicopterMegaBomb", ed4, true, true)
    local ed5 = EffectData() ed5:SetOrigin(pos + Vector(0,0,100)) ed5:SetScale(5) ed5:SetMagnitude(5) ed5:SetRadius(500) util.Effect("HelicopterMegaBomb", ed5, true, true)
end

function ENT:Update105mm(ct)
    if not self.NextShotTime105 or ct < self.NextShotTime105 then return end
    self.NextShotTime105 = ct + self.GUN105_Delay
    local muzzlePos = self:GetMuzzlePos()
    local aimTarget = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.GUN105_Scatter, self.GUN105_Scatter),
        math.Rand(-self.GUN105_Scatter, self.GUN105_Scatter), 0)
    local dir = aimTarget - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()
    if HasGred() then
        local shell = gred.CreateShell(muzzlePos, dir:Angle(), self, { self }, 105, "HE", 600, 15, "white", self.GUN105_Damage, nil, self.GUN105_TNT)
        if IsValid(shell) then
            if shell.Arm then shell:Arm() end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed = true shell.ShouldExplode = true
            shell.Shocktime = 8 shell.ShockForce = 1200
            shell.DEFAULT_PHYSFORCE_PLYGROUND = 1500
            shell.DEFAULT_PHYSFORCE_PLYAIR    = 80
            Shells105[shell:EntIndex()] = { plane = self }
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then phys:EnableGravity(true) phys:SetVelocity(dir * self.GUN105_ShellVelocity) end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos) m:SetAngles(dir:Angle()) m:SetOwner(self) m:Spawn() m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1800) end
        end
    end
    self:SpawnHeavyMuzzleFX(3)
    self:EmitSpatialSound(
        "killstreak_rewards/ac-130_105mm_fire.wav", self.CenterPos, WEAPON_LEVEL, math.random(96,104), 1.0
    )
end

-- ============================================================
-- W1: JASSM
-- ============================================================
function ENT:SpawnOneJASSM(dropIndex)
    dropIndex = dropIndex or 0

    if not scripted_ents.GetStored("ent_bombin_jassm_owned") then
        self:Debug("JASSM: ent_bombin_jassm_owned not registered, skipping") return false
    end
    if (self.JASSM_Stock or 0) <= 0 then self:Debug("JASSM: bay empty") return false end

    local tailWorld = self:LocalToWorld(self.JASSM_TailOffset)
    local dropPos   = Vector(tailWorld.x, tailWorld.y, tailWorld.z - (dropIndex * self.JASSM_AltOffset))
    if not util.IsInWorld(dropPos) then
        dropPos = Vector(self.CenterPos.x, self.CenterPos.y, self:GetPos().z - (dropIndex * self.JASSM_AltOffset))
    end

    local groundZ    = self:FindGround(dropPos)
    if groundZ == -1 then groundZ = self.CenterPos.z end
    local dropHeight = math.max(dropPos.z - groundZ, 0)
    if dropHeight < JASSM_MIN_DROP_HEIGHT then
        self:Debug("JASSM: altitude too low (" .. math.Round(dropHeight) .. "u), aborting drop #" .. (dropIndex + 1))
        return false
    end

    local shaMax = (dropHeight - JASSM_MIN_FREEFALL_CLEARANCE) / 1.25
    local sha    = math.max(shaMax, JASSM_SHA_FLOOR)

    local callDir = self:GetForward()
    callDir.z = 0
    if callDir:LengthSqr() < 0.01 then callDir = Vector(1, 0, 0) end
    callDir:Normalize()

    local jassm = ents.Create("ent_bombin_jassm_owned")
    if not IsValid(jassm) then self:Debug("JASSM: ents.Create failed") return false end

    jassm:SetPos(dropPos)
    jassm:SetAngles(callDir:Angle())
    jassm.SpawnedFromPlane = true
    jassm.CenterPos        = self.CenterPos
    jassm.CallDir          = callDir
    jassm.Lifetime         = math.min(self.Lifetime, 35)
    jassm.Speed            = 250
    jassm.OrbitRadius      = self.OrbitRadius * 0.75
    jassm.SkyHeightAdd     = sha
    jassm:SetOwner(self)
    jassm.IsOnPlane        = true
    jassm.Launcher         = self

    jassm:Spawn()
    jassm:Activate()

    if not IsValid(jassm) then return false end

    local mHandle = constraint.NoCollide(jassm, self, 0, 0)
    timer.Simple(1.25, function()
        if IsValid(mHandle) then mHandle:Remove() end
    end)

    self.JASSM_Stock       = self.JASSM_Stock - 1
    self.JASSM_DeployCount = self.JASSM_DeployCount + 1
    self:SetNWInt("JASSM_Spent", JASSM_MAX_STOCK - self.JASSM_Stock)
    self:Debug(string.format("JASSM drop #%d SHA=%.0f stock=%d", self.JASSM_DeployCount, sha, self.JASSM_Stock))
    return true
end

function ENT:UpdateJASSM(ct)
    if self.JASSM_SalvoFired >= 1 then return end
    if self.JASSM_Stock <= 0 then self.JASSM_SalvoFired = 1 return end

    self.JASSM_SalvoFired = 1

    local tripleRoll = math.random() < 0.20
    local salvoCount = tripleRoll and math.min(3, self.JASSM_Stock) or 1
    self:Debug(string.format("JASSM window: salvo=%d triple=%s stock=%d", salvoCount, tostring(tripleRoll), self.JASSM_Stock))

    local entIdx = self:EntIndex()

    self:SpawnOneJASSM(0)

    if salvoCount >= 2 then
        timer.Simple(1.0, function()
            local p = Entity(entIdx)
            if not IsValid(p) or p:IsMarkedForDeletion() or p.JASSM_Stock <= 0 then return end
            p:SpawnOneJASSM(1)
        end)
    end

    if salvoCount >= 3 then
        timer.Simple(2.0, function()
            local p = Entity(entIdx)
            if not IsValid(p) or p:IsMarkedForDeletion() or p.JASSM_Stock <= 0 then return end
            p:SpawnOneJASSM(2)
        end)
    end
end

function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = { self }
    local trace      = { start = startPos, endpos = endPos, filter = filterList }
    local maxNumber  = 0
    while maxNumber < 100 do
        local tr = util.TraceLine(trace)
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then table.insert(filterList, tr.Entity)
        else break end
        maxNumber = maxNumber + 1
    end
    return -1
end

function ENT:OnRemove()
    if self.IdleLoop         then self.IdleLoop:Stop()         self.IdleLoop         = nil end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() self.PlaneAmbientLoop = nil end
    if not self.IsDestroyed then self:StopSprayLoop() end
    pending_sounds = {}
end
