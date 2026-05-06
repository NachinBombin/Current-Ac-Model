AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

-- Real speed of sound in GMod units (343 m/s, 1 unit = 1 cm => 34300 u/s).
-- GAU_SOUND_SPEED is intentionally reduced for exaggerated gameplay feel:
-- at 6000 units altitude, the brrt arrives ~0.75s after the flash instead of 0.17s.
local SOUND_SPEED_UNITS = 34300
local GAU_SOUND_SPEED   = 8000  -- exaggerated: ~1/4 real speed, big delay at altitude

-- Sound levels (Source engine dB scale):
--   75  = heard ~500u   (footsteps)
--   110 = heard ~2000u  (gunshots)
--   160 = heard across the full map (~16000u+)
-- Weapon fire at 6000+ unit altitude MUST use 160 to reach ground-level players.
local SND_LEVEL_AMBIENT  = 90   -- idle/ambient loops on the plane entity
local SND_LEVEL_WEAPONS  = 160  -- all weapon fire (GAU, 40mm, 105mm)
local SND_LEVEL_PASS     = 155  -- random flyover pass sounds
local SND_LEVEL_DESTRUCT = 160  -- destruction explosion

local PRECALC_SOUNDS = {
    "killstreak_rewards/ac-130_105mm_fire.wav",
    "killstreak_rewards/ac-130_40mm_fire.wav",
    "killstreak_rewards/ac-130_25mm_fire.wav",
    "gunsounds/brrt_01.wav",
    "gunsounds/brrt_02.wav",
    "gunsounds/brrt_03.wav",
    "gunsounds/brrt_04.wav",
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
    "ambient/explosions/explode_8.wav",
    "weapon_AWP.Single",
    "ac/ac -130B.wav",
}

for _, s in ipairs(PRECALC_SOUNDS) do
    util.PrecacheSound(s)
end

local PASS_SOUNDS = {
    "killstreak_rewards/ac-130_105mm_fire.wav",
    "killstreak_rewards/ac-130_40mm_fire.wav",
    "killstreak_rewards/ac-130_25mm_fire.wav",
}

local GAU_BRRT_SOUNDS = {
    "gunsounds/brrt_01.wav",
    "gunsounds/brrt_02.wav",
    "gunsounds/brrt_03.wav",
    "gunsounds/brrt_04.wav",
}

local GAU_CAL_ID = 3

util.AddNetworkString("bombin_plane_damage_tier")
util.AddNetworkString("bombin_plane_sound")
-- Flash event: carries muzzle world pos + scale so the client renders it
-- immediately (no delay), while the sound arrives later via bombin_plane_sound.
util.AddNetworkString("bombin_gau_muzzle_flash")

function ENT:Debug(msg)
    print("[Bombin Support Plane ENT] " .. msg)
end

ENT.WeaponWindow        = 10
ENT.AimConeDegrees      = 10
ENT.SoundSpeedUnits     = SOUND_SPEED_UNITS

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

ENT.GAU_HEI_Interval    = 90
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

ENT.GAU_Spray_Delay      = 0.033

ENT.MuzzleForwardOffset  = 250
ENT.MuzzleSideOffset     = -60
ENT.Plane_Ambient_SoundPath = "ac/ac -130B.wav"

ENT.JASSM_AltOffset = 1500

-- How far behind the model origin the tail sits (tune to match the mdl).
-- air_130_l.mdl nose-to-tail is roughly 840u; tail socket is ~420u behind origin.
local PLANE_TAIL_BACK = 420

ENT.MaxHP = 8000
ENT.DamageTierThresholds = { 0.75, 0.50, 0.25 }

ENT.MuzzlePoints = {
    Vector(300, -250, 50),
    Vector(0,   -250, 50),
    Vector(-300,-250, 50),
}

-- ============================================================
-- SOUND BROADCAST HELPER
-- Clients compute their own travel delay: dist / SOUND_SPEED_UNITS.
-- extraDelay: optional additional fixed delay on top.
-- ============================================================
function ENT:EmitPlaneSound(path, pos, level, pitch, volume, extraDelay)
    if not path then return end
    net.Start("bombin_plane_sound")
        net.WriteString(path)
        net.WriteVector(pos or self:GetPos())
        net.WriteUInt(math.Clamp(level  or 75,  0, 255), 8)
        net.WriteUInt(math.Clamp(pitch  or 100, 0, 255), 8)
        net.WriteFloat(math.max(0, volume or 1))
        net.WriteFloat(math.max(0, extraDelay or 0))
    net.Broadcast()
end

-- ============================================================
-- GAU MUZZLE FLASH BROADCAST
-- Flash is sent separately from sound so the client can:
--   1. Draw the flash IMMEDIATELY (no delay - light travels instantly).
--   2. Play the brrt sound AFTER a travel delay via bombin_plane_sound.
-- soundSpeed: the (exaggerated) speed constant clients use to delay the brrt.
-- ============================================================
function ENT:BroadcastGAUFlash(muzzlePos, scale, soundPath, soundSpeed)
    net.Start("bombin_gau_muzzle_flash")
        net.WriteVector(muzzlePos)
        net.WriteFloat(scale or 1)
        net.WriteString(soundPath or "")
        net.WriteFloat(soundSpeed or GAU_SOUND_SPEED)
    net.Broadcast()
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
    self.NextPassSound = CurTime() + math.Rand(3, 6)

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

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    -- Ambient loops: raised to SND_LEVEL_AMBIENT (90) so they're audible
    -- from the ground without dominating over weapon fire.
    self.IdleLoop = CreateSound(self, "ac-130_kill_sounds/AC130_idle_inside.mp3")
    if self.IdleLoop then
        self.IdleLoop:SetSoundLevel(SND_LEVEL_AMBIENT)
        self.IdleLoop:Play()
    end

    self.PlaneAmbientLoop = CreateSound(self, self.Plane_Ambient_SoundPath)
    if self.PlaneAmbientLoop then
        self.PlaneAmbientLoop:SetSoundLevel(SND_LEVEL_AMBIENT)
        self.PlaneAmbientLoop:Play()
    end

    self.NextSpraySoundTime = 0
    -- Pass sound on spawn: full weapon-level volume so players hear the arrival.
    self:EmitPlaneSound(table.Random(PASS_SOUNDS), spawnPos, SND_LEVEL_PASS, 100, 1.0, 0)
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
    self.MuzzleIndexGlobal  = 1
    self.MuzzleIndexWeapon  = 1
    self.IsDestroyed        = false
    self.DamageTier         = 0
    self.JASSM_DeployCount  = 0

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

function ENT:DestroyPlane()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    if self.IdleLoop then self.IdleLoop:Stop() end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end
    self:StopSprayLoop()
    self:BroadcastDamageTier(0)
    local pos = self.LastPos or self:GetPos()
    local ed1 = EffectData() ed1:SetOrigin(pos) ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600) util.Effect("HelicopterMegaBomb", ed1, true, true)
    local ed2 = EffectData() ed2:SetOrigin(pos) ed2:SetScale(5) ed2:SetMagnitude(5) ed2:SetRadius(500) util.Effect("500lb_air", ed2, true, true)
    local ed3 = EffectData() ed3:SetOrigin(pos + Vector(0,0,80)) ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400) util.Effect("500lb_air", ed3, true, true)
    local ed4 = EffectData() ed4:SetOrigin(pos + Vector(0,0,180)) ed4:SetScale(3) ed4:SetMagnitude(3) ed4:SetRadius(300) util.Effect("500lb_air", ed4, true, true)
    self:EmitPlaneSound("ambient/explosions/explode_8.wav", pos, SND_LEVEL_DESTRUCT, 90,  1.0, 0)
    self:EmitPlaneSound("weapon_AWP.Single",               pos, SND_LEVEL_DESTRUCT, 60,  1.0, 0)
    util.BlastDamage(self, self, pos, 400, 200)
    self:Remove()
end

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then self:NextThink(CurTime() + 0.1) return true end
    local ct = CurTime()
    if ct >= self.DieTime then self:Remove() return end
    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end
    if ct >= self.NextPassSound then
        self:EmitPlaneSound(table.Random(PASS_SOUNDS), self:GetPos(), SND_LEVEL_PASS, math.random(96, 104), 1.0, 0)
        self.NextPassSound = ct + math.Rand(4, 7)
    end
    self:HandleWeaponWindow(ct)
    self:UpdateActiveGAUBursts(ct)
    self:NextThink(ct)
    return true
end

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
    local jitter     = math.sin(self.JitterPhase) * self.JitterAmplitude
    local liveAlt    = self.AltDriftCurrent + jitter
    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)
    local orbitYaw = 0
    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        orbitYaw = 0.1 self.TurnDelay = CurTime() + 0.02
    end
    local trSkyCheck = util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self)
    local skyYaw = 0
    if trSkyCheck.HitSky then skyYaw = 0.3 end
    self.ang = self.ang + Angle(0, orbitYaw + skyYaw, 0)
    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw
    local targetRoll  = math.Clamp(rawYawDelta * -18, -15, 15)
    local rollLerp    = rawYawDelta ~= 0 and 0.08 or 0.03
    self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)
    local vel          = IsValid(phys) and phys:GetVelocity() or Vector(0,0,0)
    local forwardSpeed = vel:Dot(self:GetForward())
    local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
    local targetPitch  = math.Clamp(speedRatio * 6, -8, 8)
    self.SmoothedPitch = Lerp(0.02, self.SmoothedPitch, targetPitch)
    self.ang.p = self.SmoothedPitch
    self.ang.r = self.SmoothedRoll
    self:SetPos(Vector(pos.x, pos.y, liveAlt))
    self:SetAngles(self.ang)
    if IsValid(phys) then phys:SetVelocity(self:GetForward() * self.Speed) end
    if not self:IsInWorld() then self:Debug("Plane moved out of world") self:Remove() end
end

function ENT:HandleWeaponWindow(ct)
    if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then self:PickNewWeapon(ct) end
    if self.CurrentWeapon == "25mm"           then self:Update25mmBurstsSchedule(ct)
    elseif self.CurrentWeapon == "40mm"       then self:Update40mm(ct)
    elseif self.CurrentWeapon == "105mm"      then self:Update105mm(ct)
    elseif self.CurrentWeapon == "25mm_spray" then self:Update25mmSpray(ct)
    elseif self.CurrentWeapon == "jassm"      then self:UpdateJASSM(ct) end
end

function ENT:PickNewWeapon(ct)
    self:StopSprayLoop()
    local roll = math.random(1, 5)
    if     roll == 1 then self.CurrentWeapon = "25mm"
    elseif roll == 2 then self.CurrentWeapon = "40mm"
    elseif roll == 3 then self.CurrentWeapon = "105mm"
    elseif roll == 4 then self.CurrentWeapon = "25mm_spray"
    else                   self.CurrentWeapon = "jassm" end
    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Picked weapon: " .. self.CurrentWeapon)
    if self.MuzzleIndexGlobal < 1 or self.MuzzleIndexGlobal > #self.MuzzlePoints then self.MuzzleIndexGlobal = 1 end
    self.MuzzleIndexWeapon = self.MuzzleIndexGlobal
    self.MuzzleIndexGlobal = self.MuzzleIndexGlobal + 1
    if self.MuzzleIndexGlobal > #self.MuzzlePoints then self.MuzzleIndexGlobal = 1 end
    if self.CurrentWeapon == "25mm" then
        self.GAU_BurstTimes   = { ct + self.GAU_FirstBurstTime, ct + self.GAU_SecondBurstTime }
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
        local sweepDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
        sweepDir:Normalize()
        self.GAU_SweepStartPos = targetPos - sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepEndPos   = targetPos + sweepDir * self.GAU_SweepHalfLength
    elseif self.CurrentWeapon == "jassm" then
        self.JASSM_Fired = false
    end
end

function ENT:StartSprayLoop() self.NextSpraySoundTime = CurTime() end
function ENT:StopSprayLoop()  self.NextSpraySoundTime = 0 end

-- ============================================================
-- GAU MUZZLE FX  (server side)
-- Flash is broadcast immediately via bombin_gau_muzzle_flash.
-- Sound is broadcast via bombin_plane_sound (each client adds its own
-- travel delay from the flash position).
-- ============================================================
function ENT:FireGAUFlashAndSound(muzzlePos, scale)
    local snd = table.Random(GAU_BRRT_SOUNDS)
    self:BroadcastGAUFlash(muzzlePos, scale or 1, snd, GAU_SOUND_SPEED)
end

function ENT:PlaySpraySoundAndFlash(ct)
    local muzzlePos = self:GetWeaponMuzzleWorldPos()
    self:FireGAUFlashAndSound(muzzlePos, 1)
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
        local tr = util.QuickTrace(Vector(self.CenterPos.x, self.CenterPos.y, self.sky), Vector(0, 0, -30000), self)
        basePos = tr.HitPos
    end
    local offsetDist = math.Rand(self.GAU_TargetOffsetMin, self.GAU_TargetOffsetMax)
    local offsetDir  = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if offsetDir:LengthSqr() < 0.01 then offsetDir = Vector(1,0,0) end
    offsetDir:Normalize()
    return basePos + offsetDir * offsetDist
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

function ENT:GetWeaponMuzzleWorldPos()
    if self.MuzzleIndexWeapon < 1 or self.MuzzleIndexWeapon > #self.MuzzlePoints then self.MuzzleIndexWeapon = 1 end
    return self:LocalToWorld(self.MuzzlePoints[self.MuzzleIndexWeapon])
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
    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })
    local muzzlePos = self:GetWeaponMuzzleWorldPos()
    self:FireGAUFlashAndSound(muzzlePos, 1)
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
        math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
        0
    )
    local muzzlePos = self:GetWeaponMuzzleWorldPos()
    self:FireGAUBulletAt(muzzlePos, baseImpact + jitter, bulletIndex)
end

function ENT:Update25mmSpray(ct)
    if ct >= self.WeaponWindowEnd then self:StopSprayLoop() return end
    if self.NextSpraySoundTime > 0 and ct >= self.NextSpraySoundTime then self:PlaySpraySoundAndFlash(ct) end
    if ct < self.NextShotTimeSpray then return end
    self.NextShotTimeSpray = ct + self.GAU_Spray_Delay
    self.SprayBulletCount  = self.SprayBulletCount + 1
    local targetPos   = self:GetTargetGroundPos()
    local finalImpact = targetPos + Vector(
        math.Rand(-self.GAU_JitterAmount * 2, self.GAU_JitterAmount * 2),
        math.Rand(-self.GAU_JitterAmount * 2, self.GAU_JitterAmount * 2),
        0
    )
    local muzzlePos = self:GetWeaponMuzzleWorldPos()
    self:FireGAUBulletAt(muzzlePos, finalImpact, self.SprayBulletCount)
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
    local ed = EffectData() ed:SetOrigin(muzzlePos) ed:SetAngles(self:GetAngles()) ed:SetScale(2)
    util.Effect("cball_explode", ed, true, true)
    -- 40mm: level 160 so it's heard from the ground at full altitude
    self:EmitPlaneSound("killstreak_rewards/ac-130_40mm_fire.wav", muzzlePos, SND_LEVEL_WEAPONS, math.random(96, 104), 1.0, 0)
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
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then phys:EnableGravity(true) phys:SetVelocity(dir * self.GUN105_ShellVelocity) end
            local plane = self
            local oldExplode = shell.OnExplode
            shell.OnExplode = function(s, pos, normal)
                if simfphys and not simfphys.IsCar then simfphys.IsCar = function() return false end end
                if oldExplode then oldExplode(s, pos, normal) end
                plane:Spawn105mmEffects(pos or s:GetPos())
            end
            local oldImpact = shell.OnImpact
            shell.OnImpact = function(s, pos, normal)
                if simfphys and not simfphys.IsCar then simfphys.IsCar = function() return false end end
                if oldImpact then oldImpact(s, pos, normal) end
                plane:Spawn105mmEffects(pos or s:GetPos())
            end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos) m:SetAngles(dir:Angle()) m:SetOwner(self) m:Spawn() m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1800) end
        end
    end
    local ed = EffectData() ed:SetOrigin(muzzlePos) ed:SetAngles(self:GetAngles()) ed:SetScale(3)
    util.Effect("cball_explode", ed, true, true)
    -- 105mm: level 160 so it's heard from the ground at full altitude
    self:EmitPlaneSound("killstreak_rewards/ac-130_105mm_fire.wav", muzzlePos, SND_LEVEL_WEAPONS, math.random(96, 104), 1.0, 0)
end

function ENT:UpdateJASSM(ct)
    if self.JASSM_Fired then return end
    self.JASSM_Fired = true

    if not scripted_ents.GetStored("ent_bombin_jassm") then
        self:Debug("JASSM: ent_bombin_jassm not registered, skipping")
        return
    end

    -- ----------------------------------------------------------------
    -- Compute the AC-130's tail position in world space.
    -- The plane's forward vector points toward its nose, so the tail
    -- is directly behind the origin by PLANE_TAIL_BACK units.
    -- We keep the Z from the live altitude (self.sky / jitter already
    -- applied via self:GetPos()) so the JASSM spawns at exactly the
    -- same altitude the plane is flying at right now.
    -- ----------------------------------------------------------------
    local planePos  = self:GetPos()
    local planeFwd  = self:GetForward()
    planeFwd.z      = 0
    if planeFwd:LengthSqr() < 0.01 then planeFwd = Vector(1, 0, 0) end
    planeFwd:Normalize()

    local tailPos = planePos + (-planeFwd) * PLANE_TAIL_BACK
    -- Keep the same Z as the plane's current live altitude.
    tailPos.z = planePos.z

    self.JASSM_DeployCount = (self.JASSM_DeployCount or 0) + 1
    local jassmAlt = self.sky - (self.JASSM_DeployCount * self.JASSM_AltOffset)
    -- Clamp so we never go underground (fix for uncapped DeployCount).
    local groundZ  = self.sky - self.SkyHeightAdd
    jassmAlt       = math.max(jassmAlt, groundZ + 800)

    -- The JASSM freefall spawn is FREEFALL_DROP (900u) ABOVE its orbit
    -- altitude, so add that on top of jassmAlt here.
    local spawnZ = jassmAlt + 900  -- mirrors FREEFALL_DROP in jassm/init.lua

    local spawnPos = Vector(tailPos.x, tailPos.y, spawnZ)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, spawnZ)
    end

    local callDir = planeFwd

    local jassm = ents.Create("ent_bombin_jassm")
    if not IsValid(jassm) then self:Debug("JASSM: ents.Create failed") return end

    jassm:SetPos(spawnPos)
    jassm:SetAngles(callDir:Angle())
    jassm:SetVar("CenterPos",    self.CenterPos)
    jassm:SetVar("CallDir",      callDir)
    jassm:SetVar("Lifetime",     math.min(self.Lifetime, 35))
    jassm:SetVar("Speed",        250)
    jassm:SetVar("OrbitRadius",  self.OrbitRadius * 0.75)
    jassm:SetVar("SkyHeightAdd", math.max(jassmAlt - groundZ, 800))
    -- Tell the JASSM to use the tail position as its freefall spawn origin.
    -- The JASSM's Initialize() checks for this var and skips its own
    -- orbit-entry position calculation when it is set.
    jassm:SetVar("PlaneTailPos",  spawnPos)

    jassm:Spawn()
    jassm:Activate()

    self:Debug("JASSM deployed from plane tail at " .. tostring(spawnPos))
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
    if self.IdleLoop then self.IdleLoop:Stop() end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end
    if not self.IsDestroyed then self:StopSprayLoop() end
end
