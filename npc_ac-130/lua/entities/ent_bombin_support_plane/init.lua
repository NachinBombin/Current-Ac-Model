AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("bombin_plane_sound")
util.AddNetworkString("gred_net_createimpact")

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

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
    "physics/concrete/impact_concrete_bullet1.wav",
    "physics/concrete/impact_concrete_bullet2.wav",
    "physics/concrete/impact_concrete_bullet3.wav",
    "physics/dirt/impact_dirt_bullet1.wav",
    "physics/dirt/impact_dirt_bullet2.wav",
}

local GAU_BRRT_SOUNDS = {
    "gunsounds/brrt_01.wav",
    "gunsounds/brrt_02.wav",
    "gunsounds/brrt_03.wav",
    "gunsounds/brrt_04.wav",
}

local GAU_CAL_ID = 3

local DEFAULT_WEAPON_WINDOW       = 10
local DEFAULT_GAU_FIRST_BURST     = 0
local DEFAULT_GAU_SECOND_BURST    = 5
local DEFAULT_GAU_BURST_COUNT     = 25
local DEFAULT_GAU_BURST_DELAY     = 0.033
local DEFAULT_GAU_SWEEP_HALF      = 600
local DEFAULT_GAU_JITTER          = 200
local DEFAULT_GAU_SPRAY_SOUND_DLY = 2.4
local DEFAULT_GAU_TARGET_OFF_MIN  = 300
local DEFAULT_GAU_TARGET_OFF_MAX  = 900
local DEFAULT_GAU_HEI_INTERVAL    = 20
local DEFAULT_GAU_BULLET_DAMAGE   = 40
local DEFAULT_GUN40_DELAY         = 0.5
local DEFAULT_GUN105_DELAY        = 6
local DEFAULT_GUN40_VEL           = 6000
local DEFAULT_GUN105_VEL          = 5000
local DEFAULT_GUN40_DMG           = 300
local DEFAULT_GUN105_DMG          = 3700
local DEFAULT_GUN40_TNT           = 0.5
local DEFAULT_GUN105_TNT          = 2.5
local DEFAULT_GUN40_SCATTER       = 600
local DEFAULT_GUN105_SCATTER      = 400
local DEFAULT_GAU_SPRAY_DELAY     = 0.033
local DEFAULT_MUZZLE_FWD          = 250
local DEFAULT_MUZZLE_SIDE         = -60

function ENT:Debug(msg)
    print("[Npc AC 130 ABOVE] " .. msg)
end

ENT.WeaponWindow        = DEFAULT_WEAPON_WINDOW
ENT.GAU_FirstBurstTime  = DEFAULT_GAU_FIRST_BURST
ENT.GAU_SecondBurstTime = DEFAULT_GAU_SECOND_BURST
ENT.GAU_BurstCount      = DEFAULT_GAU_BURST_COUNT
ENT.GAU_BurstDelay      = DEFAULT_GAU_BURST_DELAY
ENT.GAU_SweepHalfLength = DEFAULT_GAU_SWEEP_HALF
ENT.GAU_JitterAmount    = DEFAULT_GAU_JITTER
ENT.GAU_SpraySoundDelay = DEFAULT_GAU_SPRAY_SOUND_DLY
ENT.GAU_TargetOffsetMin = DEFAULT_GAU_TARGET_OFF_MIN
ENT.GAU_TargetOffsetMax = DEFAULT_GAU_TARGET_OFF_MAX
ENT.GAU_HEI_Interval    = DEFAULT_GAU_HEI_INTERVAL
ENT.GAU_BulletDamage    = DEFAULT_GAU_BULLET_DAMAGE
ENT.GUN40_Delay         = DEFAULT_GUN40_DELAY
ENT.GUN105_Delay        = DEFAULT_GUN105_DELAY
ENT.GUN40_ShellVelocity = DEFAULT_GUN40_VEL
ENT.GUN105_ShellVelocity= DEFAULT_GUN105_VEL
ENT.GUN40_Damage        = DEFAULT_GUN40_DMG
ENT.GUN105_Damage       = DEFAULT_GUN105_DMG
ENT.GUN40_TNT           = DEFAULT_GUN40_TNT
ENT.GUN105_TNT          = DEFAULT_GUN105_TNT
ENT.GUN40_Scatter       = DEFAULT_GUN40_SCATTER
ENT.GUN105_Scatter      = DEFAULT_GUN105_SCATTER
ENT.GAU_Spray_Delay     = DEFAULT_GAU_SPRAY_DELAY
ENT.MuzzleForwardOffset = DEFAULT_MUZZLE_FWD
ENT.MuzzleSideOffset    = DEFAULT_MUZZLE_SIDE
ENT.Plane_Ambient_SoundPath = "sounds/ac/ac-130B.wav"
ENT.MaxHP = 8000

ENT.MuzzlePoints = {
    Vector(300,  -250, 50),
    Vector(0,    -250, 50),
    Vector(-300, -250, 50),
}

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
    self.CallDir      = self:GetVar("CallDir",      Vector(1, 0, 0))
    self.Lifetime     = self:GetVar("Lifetime",     40)
    self.Speed        = self:GetVar("Speed",        300)
    self.OrbitRadius  = self:GetVar("OrbitRadius",  3000)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 6000)

    self.WeaponWindow        = DEFAULT_WEAPON_WINDOW
    self.GAU_FirstBurstTime  = DEFAULT_GAU_FIRST_BURST
    self.GAU_SecondBurstTime = DEFAULT_GAU_SECOND_BURST
    self.GAU_BurstCount      = DEFAULT_GAU_BURST_COUNT
    self.GAU_BurstDelay      = DEFAULT_GAU_BURST_DELAY
    self.GAU_SweepHalfLength = DEFAULT_GAU_SWEEP_HALF
    self.GAU_JitterAmount    = DEFAULT_GAU_JITTER
    self.GAU_SpraySoundDelay = DEFAULT_GAU_SPRAY_SOUND_DLY
    self.GAU_TargetOffsetMin = DEFAULT_GAU_TARGET_OFF_MIN
    self.GAU_TargetOffsetMax = DEFAULT_GAU_TARGET_OFF_MAX
    self.GAU_HEI_Interval    = DEFAULT_GAU_HEI_INTERVAL
    self.GAU_BulletDamage    = DEFAULT_GAU_BULLET_DAMAGE
    self.GUN40_Delay         = DEFAULT_GUN40_DELAY
    self.GUN105_Delay        = DEFAULT_GUN105_DELAY
    self.GUN40_ShellVelocity = DEFAULT_GUN40_VEL
    self.GUN105_ShellVelocity= DEFAULT_GUN105_VEL
    self.GUN40_Damage        = DEFAULT_GUN40_DMG
    self.GUN105_Damage       = DEFAULT_GUN105_DMG
    self.GUN40_TNT           = DEFAULT_GUN40_TNT
    self.GUN105_TNT          = DEFAULT_GUN105_TNT
    self.GUN40_Scatter       = DEFAULT_GUN40_SCATTER
    self.GUN105_Scatter      = DEFAULT_GUN105_SCATTER
    self.GAU_Spray_Delay     = DEFAULT_GAU_SPRAY_DELAY
    self.MuzzleForwardOffset = DEFAULT_MUZZLE_FWD
    self.MuzzleSideOffset    = DEFAULT_MUZZLE_SIDE
    self.MaxHP               = 8000

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1, 0, 0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    self.NextPassSound = CurTime() + math.Rand(3, 6)

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then self:Debug("spawnPos out of world") self:Remove() return end

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
    self.JitterPhase      = math.Rand(0, math.pi * 2)
    self.JitterAmplitude  = 5
    self.SmoothedRoll     = 0
    self.SmoothedPitch    = 0
    self.PrevYaw          = self:GetAngles().y

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    self.IdleLoop = CreateSound(self, "ac-130_kill_sounds/AC130_idle_inside.mp3")
    if self.IdleLoop then self.IdleLoop:SetSoundLevel(60) self.IdleLoop:Play() end

    self.PlaneAmbientLoop = CreateSound(self, self.Plane_Ambient_SoundPath)
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:SetSoundLevel(80) self.PlaneAmbientLoop:Play() end

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0
    self.NextShotTime40     = 0
    self.NextShotTime105    = 0
    self.NextShotTimeSpray  = 0
    self.SprayBulletCount   = 0
    self.NextSpraySoundTime = 0
    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}
    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.GAU_SprayTarget    = nil
    self.MuzzleIndexGlobal  = 1
    self.MuzzleIndexWeapon  = 1
    self.IsDestroyed        = false

    NetSound(table.Random(PASS_SOUNDS), self.CenterPos, 110, 100, 1.0)
    self:Debug("Spawned at " .. tostring(spawnPos))

    if not HasGred() then self:Debug("WARNING: Gred base not found; rpg_missile fallback active.") end
end

-- ============================================================
-- DAMAGE
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end
    local hp = self:GetNWInt("HP", self.MaxHP) - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    if hp <= 0 then self:DestroyPlane() end
end

function ENT:DestroyPlane()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    if self.IdleLoop         then self.IdleLoop:Stop()         end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end

    local pos = self.LastPos or self:GetPos()
    local function FX(name, o, sc)
        local ed = EffectData() ed:SetOrigin(o) ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc*100)
        util.Effect(name, ed, true, true)
    end
    FX("HelicopterMegaBomb", pos,                   6)
    FX("500lb_air",          pos,                   5)
    FX("500lb_air",          pos + Vector(0,0,80),  4)
    FX("500lb_air",          pos + Vector(0,0,180), 3)
    NetSound("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)
    NetSound("weapon_AWP.Single",               pos, 145, 60, 1.0)
    util.BlastDamage(self, self, pos, 400, 200)
    self:Remove()
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then self:NextThink(CurTime() + 0.1) return true end
    local ct = CurTime()
    if ct >= self.DieTime then self:Remove() return end

    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end

    if ct >= self.NextPassSound then
        NetSound(table.Random(PASS_SOUNDS), self.CenterPos, 110, math.random(96, 104), 1.0)
        self.NextPassSound = ct + math.Rand(4, 7)
    end

    self:HandleWeaponWindow(ct)

    if self.CurrentWeapon == "25mm" then
        self:UpdateActiveGAUBursts(ct)
    end

    self:NextThink(ct)
    return true
end

-- ============================================================
-- FLIGHT / ORBIT
-- ============================================================

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end
    if CurTime() >= self.DieTime then self:Remove() return end

    local pos = self:GetPos()
    self.LastPos = pos

    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

    self.JitterPhase = self.JitterPhase + 0.02
    local liveAlt    = self.AltDriftCurrent + math.sin(self.JitterPhase) * self.JitterAmplitude

    local dist = Vector(pos.x, pos.y, 0):Distance(Vector(self.CenterPos.x, self.CenterPos.y, 0))

    local orbitYaw = 0
    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        orbitYaw = 0.1
        self.TurnDelay = CurTime() + 0.02
    end

    local skyYaw = 0
    if util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self).HitSky then
        skyYaw = 0.3
    end

    self.ang = self.ang + Angle(0, orbitYaw + skyYaw, 0)

    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw

    self.SmoothedRoll  = Lerp(rawYawDelta ~= 0 and 0.08 or 0.03, self.SmoothedRoll, math.Clamp(rawYawDelta * -18, -15, 15))

    local vel          = IsValid(phys) and phys:GetVelocity() or Vector(0,0,0)
    local speedRatio   = math.Clamp(vel:Dot(self:GetForward()) / self.Speed, 0, 1)
    self.SmoothedPitch = Lerp(0.02, self.SmoothedPitch, math.Clamp(speedRatio * 6, -8, 8))

    self.ang.p = self.SmoothedPitch
    self.ang.r = self.SmoothedRoll

    self:SetPos(Vector(pos.x, pos.y, liveAlt))
    self:SetAngles(self.ang)
    if IsValid(phys) then phys:SetVelocity(self:GetForward() * self.Speed) end
    if not self:IsInWorld() then self:Debug("Plane out of world") self:Remove() end
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
-- ============================================================

function ENT:HandleWeaponWindow(ct)
    if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
        self:PickNewWeapon(ct)
    end

    local w = self.CurrentWeapon
    if     w == "25mm"       then self:Update25mmBurstsSchedule(ct)
    elseif w == "25mm_spray" then self:Update25mmSpray(ct)
    elseif w == "40mm"       then self:Update40mm(ct)
    elseif w == "105mm"      then self:Update105mm(ct)
    end
end

function ENT:PickNewWeapon(ct)
    self.GAU_ActiveBursts   = {}
    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.NextSpraySoundTime = 0
    self.GAU_SprayTarget    = nil

    local roll = math.random(1, 4)
    if     roll == 1 then self.CurrentWeapon = "25mm"
    elseif roll == 2 then self.CurrentWeapon = "40mm"
    elseif roll == 3 then self.CurrentWeapon = "105mm"
    else                  self.CurrentWeapon = "25mm_spray"
    end

    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Weapon: " .. self.CurrentWeapon)

    local muzzleCount      = #self.MuzzlePoints
    self.MuzzleIndexWeapon = self.MuzzleIndexGlobal
    self.MuzzleIndexGlobal = (self.MuzzleIndexGlobal % muzzleCount) + 1

    if self.CurrentWeapon == "25mm" then
        self.GAU_BurstTimes = { ct + self.GAU_FirstBurstTime, ct + self.GAU_SecondBurstTime }

    elseif self.CurrentWeapon == "40mm" then
        self.NextShotTime40 = ct

    elseif self.CurrentWeapon == "105mm" then
        self.NextShotTime105 = ct + 0.5

    elseif self.CurrentWeapon == "25mm_spray" then
        self.NextShotTimeSpray  = ct
        self.NextSpraySoundTime = ct
        self.SprayBulletCount   = 0
        self.GAU_SprayTarget    = self:GetPrimaryTargetPos()
        local sweepDir = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
        sweepDir:Normalize()
        self.GAU_SweepStartPos = self.GAU_SprayTarget - sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepEndPos   = self.GAU_SprayTarget + sweepDir * self.GAU_SweepHalfLength
    end
end

-- ============================================================
-- TARGET / MUZZLE HELPERS
-- ============================================================

function ENT:GetPrimaryTargetPos()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then closestDist = d closest = ply end
    end
    if IsValid(closest) then return closest:GetPos() end
    return util.QuickTrace(
        Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
        Vector(0, 0, -30000), self
    ).HitPos
end

function ENT:GetMuzzlePos()
    local pos    = self:GetPos()
    local ang    = self:GetAngles()
    local muzzle = pos + ang:Forward() * self.MuzzleForwardOffset + ang:Right() * self.MuzzleSideOffset
    muzzle.z     = self.sky
    return muzzle
end

function ENT:GetWeaponMuzzleWorldPos()
    local idx = math.Clamp(self.MuzzleIndexWeapon or 1, 1, #self.MuzzlePoints)
    return self:LocalToWorld(self.MuzzlePoints[idx])
end

function ENT:SpawnWeaponMuzzleFX(effectName, scale)
    local worldPos = self:GetWeaponMuzzleWorldPos()
    local ang      = self:GetAngles()
    local ed = EffectData()
    ed:SetOrigin(worldPos) ed:SetAngles(ang) ed:SetScale(scale or 1)
    util.Effect(effectName, ed, true, true)
    for _ = 1, 2 do
        local sp = EffectData()
        sp:SetOrigin(worldPos + Vector(math.Rand(-4,4), math.Rand(-4,4), 0))
        sp:SetNormal(ang:Up()) sp:SetScale(scale or 1) sp:SetMagnitude(scale or 1) sp:SetRadius(8*(scale or 1))
        util.Effect("ManhackSparks", sp, true, true)
    end
end

-- ============================================================
-- GAU IMPACT FX
-- ============================================================

function ENT:SpawnGAUImpactFX(impactPos)
    local ed1 = EffectData()
    ed1:SetOrigin(impactPos) ed1:SetScale(1.5) ed1:SetMagnitude(1.5) ed1:SetRadius(40)
    util.Effect("gred_ground_impact", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(impactPos) ed2:SetScale(0.5) ed2:SetMagnitude(0.5) ed2:SetRadius(4)
    util.Effect("Sparks", ed2, true, true)

    if HasGred() then
        net.Start("gred_net_createimpact")
            net.WriteVector(impactPos)
            net.WriteAngle(Angle(0,0,0))
            net.WriteUInt(0, 5)
            net.WriteUInt(GAU_CAL_ID, 4)
        net.Broadcast()
    end

    util.EmitSound(table.Random(GAU_IMPACT_SOUNDS), impactPos, -1, CHAN_AUTO, 1.0, 80, 0, math.random(95, 105))
end

function ENT:SpawnGAUHEIRound(impactPos)
    if not HasGred() then return end
    local shell = gred.CreateShell(
        impactPos + Vector(0,0,30), Angle(90,0,0), self, {self},
        20, "HE", 80, 0.1, nil, 60, nil, 0.005
    )
    if IsValid(shell) then
        if shell.Arm       then shell:Arm()          end
        if shell.SetArmed  then shell:SetArmed(true) end
        shell.Armed = true shell.ShouldExplode = true
        local phys = shell:GetPhysicsObject()
        if IsValid(phys) then phys:EnableGravity(true) phys:SetVelocity(Vector(0,0,-8000)) end
    end
end

-- ============================================================
-- GAU BULLET FIRE
-- ============================================================

function ENT:FireGAUBulletAt(impactPos, bulletIndex)
    local tr = util.TraceLine({
        start  = Vector(impactPos.x, impactPos.y, self.sky + 100),
        endpos = Vector(impactPos.x, impactPos.y, impactPos.z - 64),
        filter = self,
        mask   = MASK_SHOT,
    })

    self:SpawnGAUImpactFX(tr.HitPos)

    if tr.Hit and IsValid(tr.Entity) and tr.Entity ~= self then
        local ent = tr.Entity
        if ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "nextbot" then
            local dmginfo = DamageInfo()
            dmginfo:SetAttacker(self)
            dmginfo:SetDamage(self.GAU_BulletDamage)
            dmginfo:SetDamagePosition(tr.HitPos)
            dmginfo:SetDamageType(DMG_BULLET)
            ent:TakeDamageInfo(dmginfo)
        end
    end

    if bulletIndex % self.GAU_HEI_Interval == 0 then
        self:SpawnGAUHEIRound(tr.HitPos)
    end
end

-- ============================================================
-- SLOT 1 — 25mm GAU BURST
-- ============================================================

function ENT:Update25mmBurstsSchedule(ct)
    for i, t in ipairs(self.GAU_BurstTimes) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
        end
    end
end

function ENT:StartGAUBurst()
    local targetPos = self:GetPrimaryTargetPos()
    local sweepDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
    sweepDir:Normalize()
    local half = self.GAU_SweepHalfLength
    self.GAU_SweepStartPos = targetPos - sweepDir * half
    self.GAU_SweepEndPos   = targetPos + sweepDir * half

    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })
    self:SpawnWeaponMuzzleFX("cball_explode", 1)
    NetSound(table.Random(GAU_BRRT_SOUNDS), self.CenterPos, 110, math.random(96, 104), 1.0)
end

function ENT:UpdateActiveGAUBursts(ct)
    for idx = #self.GAU_ActiveBursts, 1, -1 do
        local burst = self.GAU_ActiveBursts[idx]
        if not burst then table.remove(self.GAU_ActiveBursts, idx) continue end
        if ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + self.GAU_BurstDelay
            self:FireSingleGAUBullet(burst.bulletsFired)
            if burst.bulletsFired >= self.GAU_BurstCount then
                table.remove(self.GAU_ActiveBursts, idx)
            end
        end
    end
end

function ENT:FireSingleGAUBullet(bulletIndex)
    if not self.GAU_SweepStartPos then return end
    local fraction   = math.Clamp((bulletIndex - 1) / math.max(self.GAU_BurstCount - 1, 1), 0, 1)
    local baseImpact = LerpVector(fraction, self.GAU_SweepStartPos, self.GAU_SweepEndPos)
    local jitter     = Vector(math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
                              math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount), 0)
    self:FireGAUBulletAt(baseImpact + jitter, bulletIndex)
end

-- ============================================================
-- SLOT 2 — 25mm GAU SPRAY
-- ============================================================

function ENT:Update25mmSpray(ct)
    if self.NextSpraySoundTime > 0 and ct >= self.NextSpraySoundTime then
        NetSound(table.Random(GAU_BRRT_SOUNDS), self.CenterPos, 110, math.random(96, 104), 1.0)
        self:SpawnWeaponMuzzleFX("cball_explode", 1)
        self.NextSpraySoundTime = ct + self.GAU_SpraySoundDelay
    end

    if ct < self.NextShotTimeSpray then return end
    self.NextShotTimeSpray = ct + self.GAU_Spray_Delay
    self.SprayBulletCount  = self.SprayBulletCount + 1

    local target = self.GAU_SprayTarget or self:GetPrimaryTargetPos()
    local jitter = self.GAU_JitterAmount * 2
    self:FireGAUBulletAt(
        target + Vector(math.Rand(-jitter, jitter), math.Rand(-jitter, jitter), 0),
        self.SprayBulletCount
    )
end

-- ============================================================
-- SLOT 3 — 40mm
-- ============================================================

function ENT:Update40mm(ct)
    if ct < self.NextShotTime40 then return end
    self.NextShotTime40 = ct + self.GUN40_Delay

    local muzzlePos = self:GetMuzzlePos()
    local scatter   = self.GUN40_Scatter
    local target    = self:GetPrimaryTargetPos()
    local aimTarget = target + Vector(math.Rand(-scatter,scatter), math.Rand(-scatter,scatter), 0)
    local dir = (aimTarget - muzzlePos):GetNormalized()
    if dir:LengthSqr() < 0.01 then return end

    if HasGred() then
        local shell = gred.CreateShell(
            muzzlePos, dir:Angle(), self, {self},
            40, "HE", 800, 0.9, "yellow",
            self.GUN40_Damage, nil, self.GUN40_TNT
        )
        if IsValid(shell) then
            if shell.Arm      then shell:Arm()          end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed = true shell.ShouldExplode = true
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then phys:EnableGravity(true) phys:SetVelocity(dir * self.GUN40_ShellVelocity) end
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
    local function FX(name, o, sc)
        local ed = EffectData() ed:SetOrigin(o) ed:SetScale(sc) ed:SetMagnitude(sc) ed:SetRadius(sc*100)
        util.Effect(name, ed, true, true)
    end
    FX("500lb_air",          pos,                   6)
    FX("500lb_air",          pos + Vector(0,0,80),  5)
    FX("500lb_air",          pos + Vector(0,0,180), 4)
    FX("HelicopterMegaBomb", pos,                   6)
    FX("HelicopterMegaBomb", pos + Vector(0,0,100), 5)
end

function ENT:Update105mm(ct)
    if ct < self.NextShotTime105 then return end
    self.NextShotTime105 = ct + self.GUN105_Delay

    local muzzlePos = self:GetMuzzlePos()
    local scatter   = self.GUN105_Scatter
    local target    = self:GetPrimaryTargetPos()
    local aimTarget = target + Vector(math.Rand(-scatter,scatter), math.Rand(-scatter,scatter), 0)
    local dir = (aimTarget - muzzlePos):GetNormalized()
    if dir:LengthSqr() < 0.01 then return end

    if HasGred() then
        local shell = gred.CreateShell(
            muzzlePos, dir:Angle(), self, {self},
            105, "HE", 600, 15, "white",
            self.GUN105_Damage, nil, self.GUN105_TNT
        )
        if IsValid(shell) then
            if shell.Arm      then shell:Arm()          end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed = true shell.ShouldExplode = true
            shell.Shocktime = 8 shell.ShockForce = 1200
            shell.DEFAULT_PHYSFORCE_PLYGROUND = 1500
            shell.DEFAULT_PHYSFORCE_PLYAIR    = 80
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then phys:EnableGravity(true) phys:SetVelocity(dir * self.GUN105_ShellVelocity) end
            local plane = self
            local function wrapCB(orig)
                return function(s, pos2, normal)
                    if simfphys and not simfphys.IsCar then simfphys.IsCar = function() return false end end
                    if orig then orig(s, pos2, normal) end
                    plane:Spawn105mmEffects(pos2 or s:GetPos())
                end
            end
            shell.OnExplode = wrapCB(shell.OnExplode)
            shell.OnImpact  = wrapCB(shell.OnImpact)
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
    local filterList = {self}
    local trace = {start = Vector(centerPos.x, centerPos.y, centerPos.z+64), endpos = Vector(centerPos.x, centerPos.y, -16384), filter = filterList}
    for _ = 1, 100 do
        local tr = util.TraceLine(trace)
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then table.insert(filterList, tr.Entity) else break end
    end
    return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
    if self.IdleLoop         then self.IdleLoop:Stop()         end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end
end
