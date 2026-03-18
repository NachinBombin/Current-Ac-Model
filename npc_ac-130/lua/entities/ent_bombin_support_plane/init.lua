AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local gred = gred or {}

local function HasGred()
    return gred and gred.CreateShell
end

local PASS_SOUNDS = {
    "killstreak_rewards/ac-130_105mm_fire.wav",
    "killstreak_rewards/ac-130_40mm_fire.wav",
    "killstreak_rewards/ac-130_25mm_fire.wav",
}

function ENT:Debug(msg)
    print("[Bombin Support Plane ENT] " .. msg)
end

ENT.WeaponWindow        = 10
ENT.AimConeDegrees      = 10

ENT.GAU_ConeDegrees     = 600   -- huge cone: spectacle over lethality, both modes use this

ENT.GAU_FirstBurstTime  = 0
ENT.GAU_SecondBurstTime = 5
ENT.GAU_BurstCount      = 25
ENT.GAU_BurstDelay      = 0.033
ENT.GAU_SweepHalfLength = 600
ENT.GAU_JitterAmount    = 200

ENT.GUN40_Delay         = 0.5
ENT.GUN105_Delay        = 6
ENT.GUN40_ShellVelocity = 6000
ENT.GUN105_ShellVelocity= 5000
ENT.GUN40_Damage        = 300
ENT.GUN105_Damage       = 3700
ENT.GUN40_TNT           = 0.5
ENT.GUN105_TNT          = 2.5

ENT.GUN40_Scatter       = 600
ENT.GUN105_Scatter      = 400

ENT.GAU_Spray_Delay     = 0.033

ENT.MuzzleForwardOffset = 250
ENT.MuzzleSideOffset    = -60
ENT.GAU_Loop_SoundPath  = "killstreak_rewards/a10_gatling_loop.wav"
ENT.Plane_Ambient_SoundPath = "sounds/ac/ac-130B.wav"

ENT.FadeDuration        = 2.0

ENT.MuzzlePoints = {
    Vector(300, -250, 50),
    Vector(0,   -250, 50),
    Vector(-300,-250, 50),
}

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos", self:GetPos())
    self.CallDir      = self:GetVar("CallDir", Vector(1, 0, 0))
    self.Lifetime     = self:GetVar("Lifetime", 40)
    self.Speed        = self:GetVar("Speed", 300)
    self.OrbitRadius  = self:GetVar("OrbitRadius", 3000)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 6000)

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

    self.sky           = ground + self.SkyHeightAdd
    self.DieTime       = CurTime() + self.Lifetime
    self.SpawnTime     = CurTime()
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
    self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    self:SetPos(spawnPos)

    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y - 90, 0))
    self.ang = self:GetAngles()

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    self.IdleLoop = CreateSound(game.GetWorld(), "ac-130_kill_sounds/AC130_idle_inside.mp3")
    if self.IdleLoop then
        self.IdleLoop:SetSoundLevel(60)
        self.IdleLoop:Play()
    end

    self.PlaneAmbientLoop = CreateSound(game.GetWorld(), self.Plane_Ambient_SoundPath)
    if self.PlaneAmbientLoop then
        self.PlaneAmbientLoop:SetSoundLevel(80)
        self.PlaneAmbientLoop:Play()
    end

    self.GAUSound = CreateSound(game.GetWorld(), self.GAU_Loop_SoundPath)

    sound.Play(table.Random(PASS_SOUNDS), self.CenterPos, 75, 100, 0.7)
    self:Debug("Spawned at " .. tostring(spawnPos))

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0

    self.NextShotTime40     = 0
    self.NextShotTime105    = 0
    self.NextShotTimeSpray  = 0

    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}

    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.GAU_SweepMuzzlePos = nil

    self.MuzzleIndexGlobal  = 1
    self.MuzzleIndexWeapon  = 1
end

function ENT:Think()
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
        sound.Play(table.Random(PASS_SOUNDS), self.CenterPos, 75, math.random(96, 104), 0.7)
        self.NextPassSound = ct + math.Rand(4, 7)
    end

    local alpha = 255
    local age   = ct - self.SpawnTime
    local left  = self.DieTime - ct

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

function ENT:HandleWeaponWindow(ct)
    if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
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
    if (self.CurrentWeapon == "25mm" or self.CurrentWeapon == "25mm_spray")
        and self.GAUSound and self.GAUSound:IsPlaying() then
        self.GAUSound:Stop()
    end

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

    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Picked weapon: " .. self.CurrentWeapon)

    if self.MuzzleIndexGlobal < 1 or self.MuzzleIndexGlobal > #self.MuzzlePoints then
        self.MuzzleIndexGlobal = 1
    end
    self.MuzzleIndexWeapon = self.MuzzleIndexGlobal
    self.MuzzleIndexGlobal = self.MuzzleIndexGlobal + 1
    if self.MuzzleIndexGlobal > #self.MuzzlePoints then
        self.MuzzleIndexGlobal = 1
    end

    if self.CurrentWeapon == "25mm" then
        self.GAU_BurstTimes   = { ct + self.GAU_FirstBurstTime, ct + self.GAU_SecondBurstTime }
        self.GAU_BurstsFired  = 0
        self.GAU_ActiveBursts = {}
        if self.GAUSound then
            self.GAUSound:SetSoundLevel(100)
            self.GAUSound:Play()
        end
    elseif self.CurrentWeapon == "40mm" then
        self.NextShotTime40 = ct
    elseif self.CurrentWeapon == "105mm" then
        self.NextShotTime105 = ct + 0.5
    elseif self.CurrentWeapon == "25mm_spray" then
        self.NextShotTimeSpray = ct
        local targetPos = self:GetTargetGroundPos()
        local sweepDir  = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
        sweepDir:Normalize()
        self.GAU_SweepStartPos  = targetPos - sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepEndPos    = targetPos + sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepMuzzlePos = self:GetMuzzlePos()
        if self.GAUSound then
            self.GAUSound:SetSoundLevel(100)
            self.GAUSound:Play()
        end
    end
end

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
    local target = self:GetPrimaryTarget()
    if IsValid(target) then
        return target:GetPos()
    end

    local tr = util.QuickTrace(
        Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
        Vector(0, 0, -30000),
        self
    )
    return tr.HitPos
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
    if self.MuzzleIndexWeapon < 1 or self.MuzzleIndexWeapon > #self.MuzzlePoints then
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

-- ===================== GAU SHARED FIRE (TrajSim-GAU) =====================
-- Both 25mm burst and 25mm spray call this.
-- Cone of 600 degrees makes it pure spectacle.

function ENT:FireGAURound(muzzlePos, targetGroundPos)
    -- Apply the huge aim cone by scattering the target point on the ground plane.
    -- We do NOT use GetConeAimedDirection because a 600-degree angular cone
    -- from 6000 HU altitude produces nonsensical downward vectors.
    -- Instead we scatter the ground impact point directly — this is equivalent
    -- and well-behaved regardless of altitude.
    local scatter = self.GAU_ConeDegrees -- reuse field as scatter radius in HU
    local finalImpact = targetGroundPos + Vector(
        math.Rand(-scatter, scatter),
        math.Rand(-scatter, scatter),
        0
    )

    local dir = finalImpact - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    self:FireBullets({
        Src       = muzzlePos,
        Dir       = dir,
        Damage    = TRAJ_GAU and TRAJ_GAU.damage or 35,
        Num       = 1,
        Tracer    = 1,
        Spread    = Vector(0, 0, 0),
        Inflictor = self,
        AmmoType  = "pistol",
    })
end

-- ===================== 25mm GAU (burst) =====================

function ENT:Update25mmBurstsSchedule(ct)
    if not self.GAU_BurstTimes then return end

    for i, t in ipairs(self.GAU_BurstTimes) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
            self.GAU_BurstsFired = self.GAU_BurstsFired + 1
        end
    end

    if ct >= self.WeaponWindowEnd then
        if self.GAUSound and self.GAUSound:IsPlaying() then
            self.GAUSound:Stop()
        end
    end
end

function ENT:StartGAUBurst()
    local targetPos = self:GetTargetGroundPos()
    local muzzlePos = self:GetMuzzlePos()

    local sweepDir = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1, 0, 0) end
    sweepDir:Normalize()

    self.GAU_SweepStartPos  = targetPos - sweepDir * self.GAU_SweepHalfLength
    self.GAU_SweepEndPos    = targetPos + sweepDir * self.GAU_SweepHalfLength
    self.GAU_SweepMuzzlePos = muzzlePos

    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })

    self:SpawnWeaponMuzzleFX("cball_explode", 1)
    sound.Play("killstreak_rewards/ac-130_25mm_fire.wav", self.CenterPos, 110, math.random(96, 104), 1.0)
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

    local muzzlePos = self.GAU_SweepMuzzlePos or self:GetMuzzlePos()
    self:FireGAURound(muzzlePos, baseImpact)
end

-- ===================== 25mm GAU (spray) =====================

function ENT:Update25mmSpray(ct)
    if ct < self.NextShotTimeSpray then return end
    if ct >= self.WeaponWindowEnd then
        if self.GAUSound and self.GAUSound:IsPlaying() then self.GAUSound:Stop() end
        return
    end

    self.NextShotTimeSpray = ct + self.GAU_Spray_Delay

    local targetPos = self:GetTargetGroundPos()
    local muzzlePos = self.GAU_SweepMuzzlePos or self:GetMuzzlePos()
    self:FireGAURound(muzzlePos, targetPos)
end

-- ===================== 40mm =====================

function ENT:Update40mm(ct)
    if not self.NextShotTime40 or ct < self.NextShotTime40 then return end
    self.NextShotTime40 = ct + self.GUN40_Delay

    local muzzlePos = self:GetMuzzlePos()
    local aimTarget = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.GUN40_Scatter, self.GUN40_Scatter),
        math.Rand(-self.GUN40_Scatter, self.GUN40_Scatter),
        0
    )

    local dir = aimTarget - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    if HasGred() then
        local shell = gred.CreateShell(
            muzzlePos, dir:Angle(), self, { self },
            40, "HE", 800, 0.9, "yellow",
            self.GUN40_Damage, nil, self.GUN40_TNT
        )
        if IsValid(shell) then
            if shell.Arm then shell:Arm() end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed         = true
            shell.ShouldExplode = true
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:EnableGravity(true)
                phys:SetVelocity(dir * self.GUN40_ShellVelocity)
            end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos)
            m:SetAngles(dir:Angle())
            m:SetOwner(self)
            m:Spawn()
            m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1600) end
        end
    end

    self:SpawnWeaponMuzzleFX("cball_explode", 2)
    sound.Play("killstreak_rewards/ac-130_40mm_fire.wav", self.CenterPos, 110, math.random(96, 104), 1.0)
end

-- ===================== 105mm =====================

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
    self.NextShotTime105 = ct + self.GUN105_Delay

    local muzzlePos = self:GetMuzzlePos()
    local aimTarget = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.GUN105_Scatter, self.GUN105_Scatter),
        math.Rand(-self.GUN105_Scatter, self.GUN105_Scatter),
        0
    )

    local dir = aimTarget - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    if HasGred() then
        local shell = gred.CreateShell(
            muzzlePos, dir:Angle(), self, { self },
            105, "HE", 600, 15, "white",
            self.GUN105_Damage, nil, self.GUN105_TNT
        )
        if IsValid(shell) then
            if shell.Arm then shell:Arm() end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed         = true
            shell.ShouldExplode = true

            shell.Shocktime  = 8
            shell.ShockForce = 1200
            shell.DEFAULT_PHYSFORCE_PLYGROUND = 1500
            shell.DEFAULT_PHYSFORCE_PLYAIR    = 80

            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:EnableGravity(true)
                phys:SetVelocity(dir * self.GUN105_ShellVelocity)
            end

            local plane      = self
            local oldExplode = shell.OnExplode
            shell.OnExplode  = function(s, pos, normal)
                if oldExplode then oldExplode(s, pos, normal) end
                plane:Spawn105mmEffects(pos or s:GetPos())
            end

            local oldImpact = shell.OnImpact
            shell.OnImpact  = function(s, pos, normal)
                if oldImpact then oldImpact(s, pos, normal) end
                plane:Spawn105mmEffects(pos or s:GetPos())
            end
        end
    else
        local m = ents.Create("rpg_missile")
        if IsValid(m) then
            m:SetPos(muzzlePos)
            m:SetAngles(dir:Angle())
            m:SetOwner(self)
            m:Spawn()
            m:Activate()
            local phys = m:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dir * 1800) end
        end
    end

    self:SpawnWeaponMuzzleFX("cball_explode", 3)
    sound.Play("killstreak_rewards/ac-130_105mm_fire.wav", self.CenterPos, 110, math.random(96, 104), 1.0)
end

-- ===================== FLIGHT / ORBIT =====================

function ENT:PhysicsUpdate(phys)
    if CurTime() >= self.DieTime then
        self:Remove()
        return
    end

    local pos = self:GetPos()
    self:SetPos(Vector(pos.x, pos.y, self.sky))
    self:SetAngles(self.ang)

    if IsValid(phys) then
        phys:SetVelocity(self:GetForward() * self.Speed)
    end

    local flatPos    = Vector(self:GetPos().x, self:GetPos().y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)

    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        self.ang       = self.ang + Angle(0, 0.1, 0)
        self.TurnDelay = CurTime() + 0.02
    end

    local tr = util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self)
    if tr.HitSky then
        self.ang = self.ang + Angle(0, 0.3, 0)
    end

    if not self:IsInWorld() then
        self:Debug("Plane moved out of world")
        self:Remove()
    end
end

function ENT:OnRemove()
    if self.IdleLoop then self.IdleLoop:Stop() end
    if self.PlaneAmbientLoop then self.PlaneAmbientLoop:Stop() end
    if self.GAUSound and self.GAUSound:IsPlaying() then self.GAUSound:Stop() end
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
        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else
            break
        end
        maxNumber = maxNumber + 1
    end

    return -1
end
