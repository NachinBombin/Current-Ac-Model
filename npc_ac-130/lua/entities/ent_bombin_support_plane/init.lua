AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

-- Broadcast a sound to all clients so it plays at the world pos regardless of distance
local function NetSound(path, pos, level, pitch, volume)
    net.Start("bombin_plane_sound")
        net.WriteString(path)
        net.WriteVector(pos)
        net.WriteUInt(level, 8)
        net.WriteUInt(pitch, 8)
        net.WriteFloat(volume)
    net.Broadcast()
end

local PASS_SOUNDS = {
    "killstreak_rewards/ac-130_105mm_fire.wav",
    "killstreak_rewards/ac-130_40mm_fire.wav",
    "killstreak_rewards/ac-130_25mm_fire.wav",
}

local GAU_IMPACT_SOUNDS = {
    "gredwitch/impacts/bullet_impact_dirt_01.wav",
    "gredwitch/impacts/bullet_impact_dirt_02.wav",
    "gredwitch/impacts/bullet_impact_dirt_03.wav",
    "gredwitch/impacts/bullet_impact_concrete_01.wav",
    "gredwitch/impacts/bullet_impact_concrete_02.wav",
}

local GAU_BRRT_SOUNDS = {
    "gunsounds/brrt_01.wav",
    "gunsounds/brrt_02.wav",
    "gunsounds/brrt_03.wav",
    "gunsounds/brrt_04.wav",
}

local GAU_CAL_ID = 3

-- Default values used as fallbacks if self.* is nil at call time
local DEFAULT_WEAPON_WINDOW        = 10
local DEFAULT_GAU_FIRST_BURST      = 0
local DEFAULT_GAU_SECOND_BURST     = 5
local DEFAULT_GAU_BURST_COUNT      = 25
local DEFAULT_GAU_BURST_DELAY      = 0.033
local DEFAULT_GAU_SWEEP_HALF       = 600
local DEFAULT_GAU_JITTER           = 200
local DEFAULT_GAU_SPRAY_SOUND_DLY  = 2.4
local DEFAULT_GAU_TARGET_OFF_MIN   = 300
local DEFAULT_GAU_TARGET_OFF_MAX   = 900
local DEFAULT_GAU_HEI_INTERVAL     = 20
local DEFAULT_GAU_BULLET_DAMAGE    = 40
local DEFAULT_GUN40_DELAY          = 0.5
local DEFAULT_GUN105_DELAY         = 6
local DEFAULT_GUN40_VEL            = 6000
local DEFAULT_GUN105_VEL           = 5000
local DEFAULT_GUN40_DMG            = 300
local DEFAULT_GUN105_DMG           = 3700
local DEFAULT_GUN40_TNT            = 0.5
local DEFAULT_GUN105_TNT           = 2.5
local DEFAULT_GUN40_SCATTER        = 600
local DEFAULT_GUN105_SCATTER       = 400
local DEFAULT_GAU_SPRAY_DELAY      = 0.033
local DEFAULT_MUZZLE_FWD           = 250
local DEFAULT_MUZZLE_SIDE          = -60

function ENT:Debug(msg)
    print("[Bombin Support Plane ENT] " .. msg)
end

ENT.WeaponWindow        = DEFAULT_WEAPON_WINDOW
ENT.AimConeDegrees      = 10

ENT.GAU_FirstBurstTime  = DEFAULT_GAU_FIRST_BURST
ENT.GAU_SecondBurstTime = DEFAULT_GAU_SECOND_BURST
ENT.GAU_BurstCount      = DEFAULT_GAU_BURST_COUNT
ENT.GAU_BurstDelay      = DEFAULT_GAU_BURST_DELAY
ENT.GAU_Caliber         = "wac_base_20mm"
ENT.GAU_TracerColor     = nil
ENT.GAU_DamageMul       = 0.5
ENT.GAU_RadiusMul       = 0.05
ENT.GAU_SweepHalfLength = DEFAULT_GAU_SWEEP_HALF
ENT.GAU_JitterAmount    = DEFAULT_GAU_JITTER
ENT.GAU_SpraySoundDelay = DEFAULT_GAU_SPRAY_SOUND_DLY

ENT.GAU_TargetOffsetMin = DEFAULT_GAU_TARGET_OFF_MIN
ENT.GAU_TargetOffsetMax = DEFAULT_GAU_TARGET_OFF_MAX

ENT.GAU_HEI_Interval    = DEFAULT_GAU_HEI_INTERVAL
ENT.GAU_BulletDamage    = DEFAULT_GAU_BULLET_DAMAGE

ENT.GUN40_Delay          = DEFAULT_GUN40_DELAY
ENT.GUN105_Delay         = DEFAULT_GUN105_DELAY
ENT.GUN40_ShellVelocity  = DEFAULT_GUN40_VEL
ENT.GUN105_ShellVelocity = DEFAULT_GUN105_VEL
ENT.GUN40_Damage         = DEFAULT_GUN40_DMG
ENT.GUN105_Damage        = DEFAULT_GUN105_DMG
ENT.GUN40_TNT            = DEFAULT_GUN40_TNT
ENT.GUN105_TNT           = DEFAULT_GUN105_TNT

ENT.GUN40_Scatter        = DEFAULT_GUN40_SCATTER
ENT.GUN105_Scatter       = DEFAULT_GUN105_SCATTER

ENT.GAU_Spray_Delay      = DEFAULT_GAU_SPRAY_DELAY

ENT.MuzzleForwardOffset  = DEFAULT_MUZZLE_FWD
ENT.MuzzleSideOffset     = DEFAULT_MUZZLE_SIDE
ENT.Plane_Ambient_SoundPath = "sounds/ac/ac-130B.wav"

ENT.MaxHP = 8000

ENT.MuzzlePoints = {
    Vector(300, -250, 50),
    Vector(0,   -250, 50),
    Vector(-300,-250, 50),
}

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos", self:GetPos())
    self.CallDir      = self:GetVar("CallDir", Vector(1, 0, 0))
    self.Lifetime     = self:GetVar("Lifetime", 40)
    self.Speed        = self:GetVar("Speed", 300)
    self.OrbitRadius  = self:GetVar("OrbitRadius", 3000)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 6000)

    -- Ensure all tunable fields have values on the instance
    self.WeaponWindow        = self.WeaponWindow        or DEFAULT_WEAPON_WINDOW
    self.GAU_FirstBurstTime  = self.GAU_FirstBurstTime  or DEFAULT_GAU_FIRST_BURST
    self.GAU_SecondBurstTime = self.GAU_SecondBurstTime or DEFAULT_GAU_SECOND_BURST
    self.GAU_BurstCount      = self.GAU_BurstCount      or DEFAULT_GAU_BURST_COUNT
    self.GAU_BurstDelay      = self.GAU_BurstDelay      or DEFAULT_GAU_BURST_DELAY
    self.GAU_SweepHalfLength = self.GAU_SweepHalfLength or DEFAULT_GAU_SWEEP_HALF
    self.GAU_JitterAmount    = self.GAU_JitterAmount    or DEFAULT_GAU_JITTER
    self.GAU_SpraySoundDelay = self.GAU_SpraySoundDelay or DEFAULT_GAU_SPRAY_SOUND_DLY
    self.GAU_TargetOffsetMin = self.GAU_TargetOffsetMin or DEFAULT_GAU_TARGET_OFF_MIN
    self.GAU_TargetOffsetMax = self.GAU_TargetOffsetMax or DEFAULT_GAU_TARGET_OFF_MAX
    self.GAU_HEI_Interval    = self.GAU_HEI_Interval    or DEFAULT_GAU_HEI_INTERVAL
    self.GAU_BulletDamage    = self.GAU_BulletDamage    or DEFAULT_GAU_BULLET_DAMAGE
    self.GUN40_Delay         = self.GUN40_Delay         or DEFAULT_GUN40_DELAY
    self.GUN105_Delay        = self.GUN105_Delay        or DEFAULT_GUN105_DELAY
    self.GUN40_ShellVelocity = self.GUN40_ShellVelocity or DEFAULT_GUN40_VEL
    self.GUN105_ShellVelocity= self.GUN105_ShellVelocity or DEFAULT_GUN105_VEL
    self.GUN40_Damage        = self.GUN40_Damage        or DEFAULT_GUN40_DMG
    self.GUN105_Damage       = self.GUN105_Damage       or DEFAULT_GUN105_DMG
    self.GUN40_TNT           = self.GUN40_TNT           or DEFAULT_GUN40_TNT
    self.GUN105_TNT          = self.GUN105_TNT          or DEFAULT_GUN105_TNT
    self.GUN40_Scatter       = self.GUN40_Scatter       or DEFAULT_GUN40_SCATTER
    self.GUN105_Scatter      = self.GUN105_Scatter      or DEFAULT_GUN105_SCATTER
    self.GAU_Spray_Delay     = self.GAU_Spray_Delay     or DEFAULT_GAU_SPRAY_DELAY
    self.MuzzleForwardOffset = self.MuzzleForwardOffset or DEFAULT_MUZZLE_FWD
    self.MuzzleSideOffset    = self.MuzzleSideOffset    or DEFAULT_MUZZLE_SIDE
    self.MaxHP               = self.MaxHP               or 8000

    if self.CallDir:LengthSqr() <= 1 then
        self.CallDir = Vector(1, 0, 0)
    end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then
        self:Debug("FindGround failed")
        self:Remove()
        return
    end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    self.NextPassSound = CurTime() + math.Rand(3, 6)

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)

    if not util.IsInWorld(spawnPos) then
        self:Debug("Primary spawnPos out of world, trying center fallback")
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end

    if not util.IsInWorld(spawnPos) then
        self:Debug("Fallback spawnPos out of world too")
        self:Remove()
        return
    end

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

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    self.AltDriftRange    = 300
    self.AltDriftLerp     = 0.001

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 5

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0
    self.PrevYaw       = self:GetAngles().y

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    self.IdleLoop = CreateSound(self, "ac-130_kill_sounds/AC130_idle_inside.mp3")
    if self.IdleLoop then
        self.IdleLoop:SetSoundLevel(60)
        self.IdleLoop:Play()
    end

    self.PlaneAmbientLoop = CreateSound(self, self.Plane_Ambient_SoundPath)
    if self.PlaneAmbientLoop then
        self.PlaneAmbientLoop:SetSoundLevel(80)
        self.PlaneAmbientLoop:Play()
    end

    self.NextSpraySoundTime = 0

    NetSound(table.Random(PASS_SOUNDS), self.CenterPos, 110, 100, 1.0)
    self:Debug("Spawned at " .. tostring(spawnPos))

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0

    self.NextShotTime40     = 0
    self.NextShotTime105    = 0
    self.NextShotTimeSpray  = 0
    self.SprayBulletCount   = 0

    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}

    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.GAU_SweepMuzzlePos = nil

    self.MuzzleIndexGlobal  = 1
    self.MuzzleIndexWeapon  = 1

    self.IsDestroyed = false

    if not HasGred() then
        self:Debug("WARNING: Gred base not found; falling back to rpg_missile.")
    end
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    local hp = self:GetNWInt("HP", self.MaxHP or 8000)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)

    self:Debug("Hit! HP remaining: " .. tostring(hp))

    if hp <= 0 then
        self:Debug("Shot down!")
        self:DestroyPlane()
    end
end

function ENT:DestroyPlane()
    if self.IsDestroyed then return end
    self.IsDestroyed = true

    if self.IdleLoop then self.IdleLoop:Stop() end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end
    self:StopSprayLoop()

    local pos = self.LastPos or self:GetPos()

    local ed1 = EffectData()
    ed1:SetOrigin(pos)
    ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600)
    util.Effect("HelicopterMegaBomb", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(pos)
    ed2:SetScale(5) ed2:SetMagnitude(5) ed2:SetRadius(500)
    util.Effect("500lb_air", ed2, true, true)

    local ed3 = EffectData()
    ed3:SetOrigin(pos + Vector(0, 0, 80))
    ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400)
    util.Effect("500lb_air", ed3, true, true)

    local ed4 = EffectData()
    ed4:SetOrigin(pos + Vector(0, 0, 180))
    ed4:SetScale(3) ed4:SetMagnitude(3) ed4:SetRadius(300)
    util.Effect("500lb_air", ed4, true, true)

    NetSound("ambient/explosions/explode_8.wav", pos, 140, 90,  1.0)
    NetSound("weapon_AWP.Single",               pos, 145, 60,  1.0)

    util.BlastDamage(self, self, pos, 400, 200)

    self:Remove()
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

    if ct >= self.DieTime then
        self:Remove()
        return
    end

    if not IsValid(self.PhysObj) then
        self.PhysObj = self:GetPhysicsObject()
    end

    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
        self.PhysObj:Wake()
    end

    if ct >= self.NextPassSound then
        NetSound(table.Random(PASS_SOUNDS), self.CenterPos, 110, math.random(96, 104), 1.0)
        self.NextPassSound = ct + math.Rand(4, 7)
    end

    self:HandleWeaponWindow(ct)
    self:UpdateActiveGAUBursts(ct)

    self:NextThink(ct)
    return true
end

-- ============================================================
-- FLIGHT / ORBIT
-- ============================================================

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end

    if CurTime() >= self.DieTime then
        self:Remove()
        return
    end

    local pos = self:GetPos()
    self.LastPos = pos

    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

    self.JitterPhase = self.JitterPhase + 0.02
    local jitter     = math.sin(self.JitterPhase) * self.JitterAmplitude
    local liveAlt    = self.AltDriftCurrent + jitter

    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)

    local orbitYaw = 0
    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        orbitYaw       = 0.1
        self.TurnDelay = CurTime() + 0.02
    end

    local trSkyCheck = util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self)
    local skyYaw = 0
    if trSkyCheck.HitSky then
        skyYaw = 0.3
    end

    self.ang = self.ang + Angle(0, orbitYaw + skyYaw, 0)

    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw

    local targetRoll  = math.Clamp(rawYawDelta * -18, -15, 15)
    local rollLerp    = rawYawDelta ~= 0 and 0.08 or 0.03
    self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

    local vel          = IsValid(phys) and phys:GetVelocity() or Vector(0, 0, 0)
    local forwardSpeed = vel:Dot(self:GetForward())
    local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
    local targetPitch  = math.Clamp(speedRatio * 6, -8, 8)
    self.SmoothedPitch = Lerp(0.02, self.SmoothedPitch, targetPitch)

    self.ang.p = self.SmoothedPitch
    self.ang.r = self.SmoothedRoll

    self:SetPos(Vector(pos.x, pos.y, liveAlt))
    self:SetAngles(self.ang)

    if IsValid(phys) then
        phys:SetVelocity(self:GetForward() * self.Speed)
    end

    if not self:IsInWorld() then
        self:Debug("Plane moved out of world")
        self:Remove()
    end
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
-- ============================================================

function ENT:HandleWeaponWindow(ct)
    if not self.CurrentWeapon or ct >= (self.WeaponWindowEnd or 0) then
        self:PickNewWeapon(ct)
    end

    if self.CurrentWeapon == "25mm" then
        self:Update25mmBurstsSchedule(ct)
    elseif self.CurrentWeapon == "40mm" then
        self:Update40mm(ct)
    elseif self.CurrentWeapon == "105mm" then
        self:Update105mm(ct)
    elseif self.CurrentWeapon == "25mm_spray" then
        self:Update25mmSpray(ct)
    end
end

function ENT:PickNewWeapon(ct)
    self:StopSprayLoop()

    local roll = math.random(1, 4)
    if roll == 1 then
        self.CurrentWeapon = "25mm"
    elseif roll == 2 then
        self.CurrentWeapon = "40mm"
    elseif roll == 3 then
        self.CurrentWeapon = "105mm"
    else
        self.CurrentWeapon = "25mm_spray"
    end

    local window = self.WeaponWindow or DEFAULT_WEAPON_WINDOW
    self.WeaponWindowEnd = ct + window
    self:Debug("Picked weapon: " .. self.CurrentWeapon)

    if not self.MuzzlePoints then self.MuzzlePoints = ENT.MuzzlePoints end
    local muzzleCount = #self.MuzzlePoints

    if not self.MuzzleIndexGlobal or self.MuzzleIndexGlobal < 1 or self.MuzzleIndexGlobal > muzzleCount then
        self.MuzzleIndexGlobal = 1
    end
    self.MuzzleIndexWeapon = self.MuzzleIndexGlobal
    self.MuzzleIndexGlobal = self.MuzzleIndexGlobal + 1
    if self.MuzzleIndexGlobal > muzzleCount then
        self.MuzzleIndexGlobal = 1
    end

    if self.CurrentWeapon == "25mm" then
        local t1 = self.GAU_FirstBurstTime  or DEFAULT_GAU_FIRST_BURST
        local t2 = self.GAU_SecondBurstTime or DEFAULT_GAU_SECOND_BURST
        self.GAU_BurstTimes   = { ct + t1, ct + t2 }
        self.GAU_BurstsFired  = 0
        self.GAU_ActiveBursts = {}

    elseif self.CurrentWeapon == "40mm" then
        self.NextShotTime40 = ct

    elseif self.CurrentWeapon == "105mm" then
        self.NextShotTime105 = ct + 0.5

    elseif self.CurrentWeapon == "25mm_spray" then
        self.NextShotTimeSpray  = ct
        self.NextSpraySoundTime = ct
        self.SprayBulletCount   = 0
        local targetPos = self:GetTargetGroundPos()
        local sweepDir  = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
        sweepDir:Normalize()
        local half = self.GAU_SweepHalfLength or DEFAULT_GAU_SWEEP_HALF
        self.GAU_SweepStartPos  = targetPos - sweepDir * half
        self.GAU_SweepEndPos    = targetPos + sweepDir * half
        self.GAU_SweepMuzzlePos = self:GetMuzzlePos()
    end
end

-- ============================================================
-- SPRAY SOUND / FLASH WINDOW
-- ============================================================

function ENT:StopSprayLoop()
    self.NextSpraySoundTime = 0
end

function ENT:PlaySpraySoundAndFlash(ct)
    NetSound(table.Random(GAU_BRRT_SOUNDS), self.CenterPos, 110, math.random(96, 104), 1.0)
    self:SpawnWeaponMuzzleFX("cball_explode", 1)
    self.NextSpraySoundTime = ct + (self.GAU_SpraySoundDelay or DEFAULT_GAU_SPRAY_SOUND_DLY)
end

-- ============================================================
-- TARGET / MUZZLE HELPERS
-- ============================================================

function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then
            closestDist = d
            closest = ply
        end
    end
    return closest
end

function ENT:GetTargetGroundPos()
    local target  = self:GetPrimaryTarget()
    local basePos

    if IsValid(target) then
        basePos = target:GetPos()
    else
        local tr = util.QuickTrace(
            Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
            Vector(0, 0, -30000),
            self
        )
        basePos = tr.HitPos
    end

    local offsetDist = math.Rand(
        self.GAU_TargetOffsetMin or DEFAULT_GAU_TARGET_OFF_MIN,
        self.GAU_TargetOffsetMax or DEFAULT_GAU_TARGET_OFF_MAX
    )
    local offsetDir  = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
    if offsetDir:LengthSqr() < 0.01 then offsetDir = Vector(1, 0, 0) end
    offsetDir:Normalize()

    return basePos + offsetDir * offsetDist
end

function ENT:GetMuzzlePos()
    local pos     = self:GetPos()
    local ang     = self:GetAngles()
    local forward = ang:Forward()
    local right   = ang:Right()
    local fwd     = self.MuzzleForwardOffset or DEFAULT_MUZZLE_FWD
    local side    = self.MuzzleSideOffset    or DEFAULT_MUZZLE_SIDE
    local muzzle  = pos + forward * fwd + right * side
    muzzle.z      = self.sky
    return muzzle
end

function ENT:GetWeaponMuzzleWorldPos()
    if not self.MuzzlePoints then self.MuzzlePoints = ENT.MuzzlePoints end
    local muzzleCount = #self.MuzzlePoints
    if not self.MuzzleIndexWeapon or self.MuzzleIndexWeapon < 1 or self.MuzzleIndexWeapon > muzzleCount then
        self.MuzzleIndexWeapon = 1
    end
    return self:LocalToWorld(self.MuzzlePoints[self.MuzzleIndexWeapon])
end

function ENT:SpawnWeaponMuzzleFX(effectName, scale)
    local worldPos = self:GetWeaponMuzzleWorldPos()
    local ang      = self:GetAngles()

    local ed = EffectData()
    ed:SetOrigin(worldPos)
    ed:SetAngles(ang)
    ed:SetScale(scale or 1)
    util.Effect(effectName, ed, true, true)

    for _ = 1, 2 do
        local sp = EffectData()
        sp:SetOrigin(worldPos + Vector(math.Rand(-4, 4), math.Rand(-4, 4), 0))
        sp:SetNormal(ang:Up())
        sp:SetScale(scale or 1)
        sp:SetMagnitude(scale or 1)
        sp:SetRadius(8 * (scale or 1))
        util.Effect("ManhackSparks", sp, true, true)
    end
end

-- ============================================================
-- GAU SHARED HELPERS
-- ============================================================

function ENT:SpawnGAUImpactFX(impactPos)
    local ed1 = EffectData()
    ed1:SetOrigin(impactPos)
    ed1:SetScale(1.5) ed1:SetMagnitude(1.5) ed1:SetRadius(40)
    util.Effect("gred_ground_impact", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(impactPos)
    ed2:SetScale(0.5) ed2:SetMagnitude(0.5) ed2:SetRadius(4)
    util.Effect("Sparks", ed2, true, true)

    net.Start("gred_net_createimpact")
        net.WriteVector(impactPos)
        net.WriteAngle(Angle(0, 0, 0))
        net.WriteUInt(0, 5)
        net.WriteUInt(GAU_CAL_ID, 4)
    net.Broadcast()

    NetSound(table.Random(GAU_IMPACT_SOUNDS), impactPos, 110, math.random(95, 105), 1.0)
end

function ENT:SpawnGAUHEIRound(impactPos)
    if not HasGred() then return end

    local shell = gred.CreateShell(
        impactPos + Vector(0, 0, 30),
        Angle(90, 0, 0),
        self, { self },
        20, "HE", 80, 0.1, nil,
        60, nil, 0.005
    )
    if IsValid(shell) then
        if shell.Arm then shell:Arm() end
        if shell.SetArmed then shell:SetArmed(true) end
        shell.Armed         = true
        shell.ShouldExplode = true
        local phys = shell:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableGravity(true)
            phys:SetVelocity(Vector(0, 0, -8000))
        end
    end
end

-- ============================================================
-- GAU FIRE
-- ============================================================

function ENT:FireGAUBulletAt(impactPos, bulletIndex)
    local traceStart = Vector(impactPos.x, impactPos.y, self.sky + 100)
    local traceEnd   = Vector(impactPos.x, impactPos.y, impactPos.z - 64)

    local tr = util.TraceLine({
        start  = traceStart,
        endpos = traceEnd,
        filter = self,
        mask   = MASK_SHOT,
    })

    local hitPos = tr.HitPos

    self:SpawnGAUImpactFX(hitPos)

    if tr.Hit and IsValid(tr.Entity) and tr.Entity ~= self then
        local ent = tr.Entity
        if ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "nextbot" then
            local dmginfo = DamageInfo()
            dmginfo:SetAttacker(self)
            dmginfo:SetDamage(self.GAU_BulletDamage or DEFAULT_GAU_BULLET_DAMAGE)
            dmginfo:SetDamagePosition(hitPos)
            dmginfo:SetDamageType(DMG_BULLET)
            ent:TakeDamageInfo(dmginfo)
        end
    end

    local hei = self.GAU_HEI_Interval or DEFAULT_GAU_HEI_INTERVAL
    if bulletIndex % hei == 0 then
        self:SpawnGAUHEIRound(hitPos)
    end
end

-- ============================================================
-- SLOT 1 — 25mm GAU BURST
-- ============================================================

function ENT:Update25mmBurstsSchedule(ct)
    if not self.GAU_BurstTimes then return end

    for i, t in ipairs(self.GAU_BurstTimes) do
        if t ~= false and ct >= t and ct < (self.WeaponWindowEnd or 0) then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
            self.GAU_BurstsFired   = (self.GAU_BurstsFired or 0) + 1
        end
    end
end

function ENT:StartGAUBurst()
    local targetPos = self:GetTargetGroundPos()
    local muzzlePos = self:GetMuzzlePos()

    local sweepDir = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
    sweepDir:Normalize()

    local half = self.GAU_SweepHalfLength or DEFAULT_GAU_SWEEP_HALF
    self.GAU_SweepStartPos  = targetPos - sweepDir * half
    self.GAU_SweepEndPos    = targetPos + sweepDir * half
    self.GAU_SweepMuzzlePos = muzzlePos

    if not self.GAU_ActiveBursts then self.GAU_ActiveBursts = {} end
    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })

    self:SpawnWeaponMuzzleFX("cball_explode", 1)
    NetSound(table.Random(GAU_BRRT_SOUNDS), self.CenterPos, 110, math.random(96, 104), 1.0)
end

function ENT:UpdateActiveGAUBursts(ct)
    if not self.GAU_ActiveBursts then return end

    local burstCount = self.GAU_BurstCount or DEFAULT_GAU_BURST_COUNT
    local burstDelay = self.GAU_BurstDelay or DEFAULT_GAU_BURST_DELAY

    for idx = #self.GAU_ActiveBursts, 1, -1 do
        local burst = self.GAU_ActiveBursts[idx]
        if not burst then
            table.remove(self.GAU_ActiveBursts, idx)
        elseif ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + burstDelay
            self:FireSingleGAUBullet(burst.bulletsFired)
            if burst.bulletsFired >= burstCount then
                table.remove(self.GAU_ActiveBursts, idx)
            end
        end
    end
end

function ENT:FireSingleGAUBullet(bulletIndex)
    if not self.GAU_SweepStartPos then return end

    local burstCount = self.GAU_BurstCount or DEFAULT_GAU_BURST_COUNT
    local jitterAmt  = self.GAU_JitterAmount or DEFAULT_GAU_JITTER

    local fraction   = math.Clamp((bulletIndex - 1) / (burstCount - 1), 0, 1)
    local baseImpact = LerpVector(fraction, self.GAU_SweepStartPos, self.GAU_SweepEndPos)
    local jitter     = Vector(
        math.Rand(-jitterAmt, jitterAmt),
        math.Rand(-jitterAmt, jitterAmt),
        0
    )
    self:FireGAUBulletAt(baseImpact + jitter, bulletIndex)
end

-- ============================================================
-- SLOT 2 — 25mm GAU SPRAY
-- ============================================================

function ENT:Update25mmSpray(ct)
    if ct >= (self.WeaponWindowEnd or 0) then
        self:StopSprayLoop()
        return
    end

    if (self.NextSpraySoundTime or 0) > 0 and ct >= self.NextSpraySoundTime then
        self:PlaySpraySoundAndFlash(ct)
    end

    if ct < (self.NextShotTimeSpray or 0) then return end

    local sprayDelay = self.GAU_Spray_Delay or DEFAULT_GAU_SPRAY_DELAY
    self.NextShotTimeSpray = ct + sprayDelay
    self.SprayBulletCount  = (self.SprayBulletCount or 0) + 1

    local jitterAmt = (self.GAU_JitterAmount or DEFAULT_GAU_JITTER) * 2
    local targetPos = self:GetTargetGroundPos()
    local finalImpact = targetPos + Vector(
        math.Rand(-jitterAmt, jitterAmt),
        math.Rand(-jitterAmt, jitterAmt),
        0
    )

    self:FireGAUBulletAt(finalImpact, self.SprayBulletCount)
end

-- ============================================================
-- SLOT 3 — 40mm
-- ============================================================

function ENT:Update40mm(ct)
    if not self.NextShotTime40 or ct < self.NextShotTime40 then return end
    self.NextShotTime40 = ct + (self.GUN40_Delay or DEFAULT_GUN40_DELAY)

    local muzzlePos = self:GetMuzzlePos()
    local scatter   = self.GUN40_Scatter or DEFAULT_GUN40_SCATTER
    local aimTarget = self:GetTargetGroundPos() + Vector(
        math.Rand(-scatter, scatter),
        math.Rand(-scatter, scatter),
        0
    )

    local dir = aimTarget - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    if HasGred() then
        local shell = gred.CreateShell(
            muzzlePos, dir:Angle(), self, { self },
            40, "HE", 800, 0.9, "yellow",
            self.GUN40_Damage or DEFAULT_GUN40_DMG, nil, self.GUN40_TNT or DEFAULT_GUN40_TNT
        )
        if IsValid(shell) then
            if shell.Arm then shell:Arm() end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed         = true
            shell.ShouldExplode = true
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:EnableGravity(true)
                phys:SetVelocity(dir * (self.GUN40_ShellVelocity or DEFAULT_GUN40_VEL))
            end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos) m:SetAngles(dir:Angle()) m:SetOwner(self)
            m:Spawn() m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1600) end
        end
    end

    self:SpawnWeaponMuzzleFX("cball_explode", 2)
    NetSound("killstreak_rewards/ac-130_40mm_fire.wav", self.CenterPos, 110, math.random(96, 104), 1.0)
end

-- ============================================================
-- SLOT 4 — 105mm
-- ============================================================

function ENT:Spawn105mmEffects(pos)
    local ed1 = EffectData()
    ed1:SetOrigin(pos)
    ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600)
    util.Effect("500lb_air", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(pos + Vector(0, 0, 80))
    ed2:SetScale(5) ed2:SetMagnitude(5) ed2:SetRadius(500)
    util.Effect("500lb_air", ed2, true, true)

    local ed3 = EffectData()
    ed3:SetOrigin(pos + Vector(0, 0, 180))
    ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400)
    util.Effect("500lb_air", ed3, true, true)

    local ed4 = EffectData()
    ed4:SetOrigin(pos)
    ed4:SetScale(6) ed4:SetMagnitude(6) ed4:SetRadius(600)
    util.Effect("HelicopterMegaBomb", ed4, true, true)

    local ed5 = EffectData()
    ed5:SetOrigin(pos + Vector(0, 0, 100))
    ed5:SetScale(5) ed5:SetMagnitude(5) ed5:SetRadius(500)
    util.Effect("HelicopterMegaBomb", ed5, true, true)
end

function ENT:Update105mm(ct)
    if not self.NextShotTime105 or ct < self.NextShotTime105 then return end
    self.NextShotTime105 = ct + (self.GUN105_Delay or DEFAULT_GUN105_DELAY)

    local muzzlePos = self:GetMuzzlePos()
    local scatter   = self.GUN105_Scatter or DEFAULT_GUN105_SCATTER
    local aimTarget = self:GetTargetGroundPos() + Vector(
        math.Rand(-scatter, scatter),
        math.Rand(-scatter, scatter),
        0
    )

    local dir = aimTarget - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    if HasGred() then
        local shell = gred.CreateShell(
            muzzlePos, dir:Angle(), self, { self },
            105, "HE", 600, 15, "white",
            self.GUN105_Damage or DEFAULT_GUN105_DMG, nil, self.GUN105_TNT or DEFAULT_GUN105_TNT
        )
        if IsValid(shell) then
            if shell.Arm then shell:Arm() end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed         = true
            shell.ShouldExplode = true

            shell.Shocktime                   = 8
            shell.ShockForce                  = 1200
            shell.DEFAULT_PHYSFORCE_PLYGROUND = 1500
            shell.DEFAULT_PHYSFORCE_PLYAIR    = 80

            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:EnableGravity(true)
                phys:SetVelocity(dir * (self.GUN105_ShellVelocity or DEFAULT_GUN105_VEL))
            end

            local plane = self

            local oldExplode = shell.OnExplode
            shell.OnExplode  = function(s, pos, normal)
                if simfphys and not simfphys.IsCar then
                    simfphys.IsCar = function() return false end
                end
                if oldExplode then oldExplode(s, pos, normal) end
                plane:Spawn105mmEffects(pos or s:GetPos())
            end

            local oldImpact = shell.OnImpact
            shell.OnImpact  = function(s, pos, normal)
                if simfphys and not simfphys.IsCar then
                    simfphys.IsCar = function() return false end
                end
                if oldImpact then oldImpact(s, pos, normal) end
                plane:Spawn105mmEffects(pos or s:GetPos())
            end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos) m:SetAngles(dir:Angle()) m:SetOwner(self)
            m:Spawn() m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1800) end
        end
    end

    self:SpawnWeaponMuzzleFX("cball_explode", 3)
    NetSound("killstreak_rewards/ac-130_105mm_fire.wav", self.CenterPos, 110, math.random(96, 104), 1.0)
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = { self }
    local trace      = { start = startPos, endpos = endPos, filter = filterList }
    local maxNumber  = 0

    while maxNumber < 100 do
        local tr = util.TraceLine(trace)
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else
            break
        end
        maxNumber = maxNumber + 1
    end

    return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
    if self.IdleLoop then self.IdleLoop:Stop() end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end
    if not self.IsDestroyed then
        self:StopSprayLoop()
    end
end
