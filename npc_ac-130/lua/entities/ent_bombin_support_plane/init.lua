AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ===================== GRED DEPENDENCY =====================

local gred = gred or {}

local function HasGred()
    return gred and gred.CreateBullet and gred.STRIKE and gred.STRIKE.ARTILLERY
end

local PASS_SOUNDS = {
    "killstreak_rewards/ac-130_105mm_fire.wav",
    "killstreak_rewards/ac-130_40mm_fire.wav",
    "killstreak_rewards/ac-130_25mm_fire.wav",
}

function ENT:Debug(msg)
    print("[Bombin Support Plane ENT] " .. msg)
end

-- =============== GUNSHIP CONFIG =====================

ENT.WeaponWindow       = 10      -- seconds per chosen weapon
ENT.AimConeDegrees     = 10      -- cone for 40/105mm aim jitter

-- GAU as two scripted bursts per window (now 20mm, softer)
ENT.GAU_FirstBurstTime  = 0
ENT.GAU_SecondBurstTime = 5
ENT.GAU_BurstCount      = 25
ENT.GAU_BurstDelay      = 0.02
ENT.GAU_Caliber         = "wac_base_20mm"
ENT.GAU_TracerColor     = "red"
ENT.GAU_DamageMul       = 0.5
ENT.GAU_RadiusMul       = 0.5

-- 40mm / 105mm cadence
ENT.GUN40_Delay        = 0.5
ENT.GUN105_Delay       = 6

-- Muzzle offsets
ENT.MuzzleForwardOffset = 250
ENT.MuzzleSideOffset    = -60

ENT.GAU_Loop_SoundPath     = "killstreak_rewards/a10_gatling_loop.wav"
ENT.Plane_Ambient_SoundPath = "sounds/ac/ac-130B.wav"

ENT.MuzzlePoints = {
    Vector(300, -250, 50),
    Vector(0,   -250, 50),
    Vector(-300,-250, 50),
}

-- ===================================================

function ENT:Initialize()
    self.CenterPos     = self:GetVar("CenterPos", self:GetPos())
    self.CallDir       = self:GetVar("CallDir", Vector(1, 0, 0))
    self.Lifetime      = self:GetVar("Lifetime", 40)
    self.Speed         = self:GetVar("Speed", 300)
    self.OrbitRadius   = self:GetVar("OrbitRadius", 3000)
    self.SkyHeightAdd  = self:GetVar("SkyHeightAdd", 6000)

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

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y - 90, 0))
    self.ang = self:GetAngles()

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    -- Interior idle loop
    self.IdleLoop = CreateSound(game.GetWorld(), "ac-130_kill_sounds/AC130_idle_inside.mp3")
    if self.IdleLoop then
        self.IdleLoop:SetSoundLevel(60)
        self.IdleLoop:Play()
    end

    -- Exterior ambient plane loop
    self.PlaneAmbientLoop = CreateSound(game.GetWorld(), self.Plane_Ambient_SoundPath)
    if self.PlaneAmbientLoop then
        self.PlaneAmbientLoop:SetSoundLevel(80)
        self.PlaneAmbientLoop:Play()
    end

    -- GAU loop
    self.GAUSound = CreateSound(game.GetWorld(), self.GAU_Loop_SoundPath)

    sound.Play(table.Random(PASS_SOUNDS), self.CenterPos, 75, 100, 0.7)
    self:Debug("Spawned at " .. tostring(spawnPos))

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0

    self.NextShotTime40     = 0
    self.NextShotTime105    = 0

    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}

    self.MuzzleIndexGlobal  = 1
    self.MuzzleIndexWeapon  = 1

    if not HasGred() then
        self:Debug("WARNING: Gred base not found; AC-130 will use fallback bullets/rockets.")
    end
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

    self:HandleWeaponWindow(ct)
    self:UpdateActiveGAUBursts(ct)

    self:NextThink(ct)
    return true
end

-- ===================== WEAPON WINDOW / PICK =====================

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
    end
end

function ENT:PickNewWeapon(ct)
    if self.CurrentWeapon == "25mm" and self.GAUSound and self.GAUSound:IsPlaying() then
        self.GAUSound:Stop()
    end

    local roll = math.random(1, 3)
    if roll == 1 then
        self.CurrentWeapon = "25mm"
    elseif roll == 2 then
        self.CurrentWeapon = "40mm"
    else
        self.CurrentWeapon = "105mm"
    end

    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Picked weapon: " .. self.CurrentWeapon .. " until " .. tostring(self.WeaponWindowEnd))

    if self.MuzzleIndexGlobal < 1 or self.MuzzleIndexGlobal > #self.MuzzlePoints then
        self.MuzzleIndexGlobal = 1
    end
    self.MuzzleIndexWeapon = self.MuzzleIndexGlobal
    self.MuzzleIndexGlobal = self.MuzzleIndexGlobal + 1
    if self.MuzzleIndexGlobal > #self.MuzzlePoints then
        self.MuzzleIndexGlobal = 1
    end

    if self.CurrentWeapon == "25mm" then
        self.GAU_BurstTimes = {
            ct + self.GAU_FirstBurstTime,
            ct + self.GAU_SecondBurstTime
        }
        self.GAU_BurstsFired = 0
        self.GAU_ActiveBursts = {}

        if self.GAUSound then
            self.GAUSound:SetSoundLevel(100)
            self.GAUSound:Play()
        end

    elseif self.CurrentWeapon == "40mm" then
        self.NextShotTime40 = ct

    elseif self.CurrentWeapon == "105mm" then
        self.NextShotTime105 = ct
    end
end

-- ===================== TARGET / MUZZLE HELPERS =====================

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

function ENT:GetMuzzlePos()
    local pos = self:GetPos()
    local ang = self:GetAngles()

    local forward = ang:Forward()
    local right   = ang:Right()

    local muzzle = pos
    muzzle = muzzle + forward * self.MuzzleForwardOffset
    muzzle = muzzle + right   * self.MuzzleSideOffset
    muzzle.z = self.sky

    return muzzle
end

function ENT:GetConeAimedDirection(baseConeDeg)
    local muzzlePos = self:GetMuzzlePos()

    local target = self:GetPrimaryTarget()
    local targetPos
    if IsValid(target) then
        targetPos = target:EyePos()
    else
        targetPos = Vector(self.CenterPos.x, self.CenterPos.y, self.CenterPos.z + 8)
    end

    local aimDir = targetPos - muzzlePos
    if aimDir:LengthSqr() <= 1 then
        aimDir = self:GetAngles():Forward()
    end
    aimDir:Normalize()

    local cone  = math.rad(baseConeDeg)
    local yaw   = math.Rand(-cone, cone)
    local pitch = math.Rand(-cone * 0.5, cone * 0.5)

    local ang = aimDir:Angle()
    ang:RotateAroundAxis(ang:Up(), yaw)
    ang:RotateAroundAxis(ang:Right(), pitch)

    local dir = ang:Forward()
    dir:Normalize()

    return dir, muzzlePos
end

function ENT:GetWeaponMuzzleWorldPos()
    if self.MuzzleIndexWeapon < 1 or self.MuzzleIndexWeapon > #self.MuzzlePoints then
        self.MuzzleIndexWeapon = 1
    end
    local localPos = self.MuzzlePoints[self.MuzzleIndexWeapon]
    return self:LocalToWorld(localPos)
end

function ENT:SpawnWeaponMuzzleFX(effectName, scale)
    scale = scale or 1
    local ang = self:GetAngles()
    local worldPos = self:GetWeaponMuzzleWorldPos()

    local ed = EffectData()
    ed:SetOrigin(worldPos)
    ed:SetAngles(ang)
    ed:SetScale(scale)
    util.Effect(effectName, ed, true, true)
end

-- ===================== 25mm: TWO SCRIPTED BURSTS =====================

function ENT:Update25mmBurstsSchedule(ct)
    if not HasGred() then return end
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
    if not HasGred() then return end

    local dir, muzzlePos = self:GetConeAimedDirection(self.AimConeDegrees)
    local burst = {
        dir       = dir,
        muzzlePos = muzzlePos,
        bulletsFired = 0,
        nextTime  = CurTime(),
    }
    table.insert(self.GAU_ActiveBursts, burst)

    self:SpawnWeaponMuzzleFX("cball_explode", 2)
    sound.Play("killstreak_rewards/ac-130_25mm_fire.wav", self.CenterPos, 95, math.random(96, 104), 1.0)
end

function ENT:UpdateActiveGAUBursts(ct)
    if not HasGred() then return end
    if not self.GAU_ActiveBursts then return end

    for idx = #self.GAU_ActiveBursts, 1, -1 do
        local burst = self.GAU_ActiveBursts[idx]
        if not burst then
            table.remove(self.GAU_ActiveBursts, idx)
        else
            if ct >= burst.nextTime then
                burst.bulletsFired = burst.bulletsFired + 1
                burst.nextTime = ct + self.GAU_BurstDelay

                self:FireSingleGAUBullet(burst.muzzlePos, burst.dir)

                if burst.bulletsFired >= self.GAU_BurstCount then
                    table.remove(self.GAU_ActiveBursts, idx)
                end
            end
        end
    end
end

function ENT:FireSingleGAUBullet(muzzlePos, dir)
    if HasGred() then
        local ang = dir:Angle()
        gred.CreateBullet(
            self,
            muzzlePos,
            ang,
            self.GAU_Caliber,
            { self },
            nil,
            false,
            self.GAU_TracerColor,
            self.GAU_DamageMul,
            self.GAU_RadiusMul,
            false
        )
    else
        local bullet = {}
        bullet.Src        = muzzlePos
        bullet.Dir        = dir
        bullet.Spread     = Vector(0.002, 0.002, 0)
        bullet.Num        = 1
        bullet.Damage     = 10
        bullet.Force      = 3
        bullet.Tracer     = 1
        bullet.TracerName = "HelicopterTracer"
        self:FireBullets(bullet)
    end
end

-- ===================== 40mm: MEDIUM ARTILLERY =====================

function ENT:Update40mm(ct)
    if not self.NextShotTime40 or ct < self.NextShotTime40 then return end
    self.NextShotTime40 = ct + self.GUN40_Delay

    local dir, muzzlePos = self:GetConeAimedDirection(self.AimConeDegrees)

    if HasGred() then
        local tr = util.QuickTrace(muzzlePos, dir * 99999, self)

        timer.Simple(0, function()
            if not IsValid(self) then return end
            gred.STRIKE.ARTILLERY(
                self,
                tr,
                "ARTILLERY",
                "ARTILLERY",
                1,
                105,
                "HE",
                200,
                500
            )
        end)
    else
        local shell = ents.Create("rpg_missile")
        if IsValid(shell) then
            shell:SetPos(muzzlePos)
            shell:SetAngles(dir:Angle())
            shell:SetOwner(self)
            shell:Spawn()
            shell:Activate()

            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(dir * 1600)
            end
        end
    end

    self:SpawnWeaponMuzzleFX("cball_explode", 3)

    -- Distinct 40mm sound
    sound.Play("killstreak_rewards/ac-130_40mm_fire.wav", self.CenterPos, 90, math.random(96, 104), 1.0)
end

-- ===================== 105mm: BIGARTILLERY SHOT =====================

function ENT:Update105mm(ct)
    if not self.NextShotTime105 or ct < self.NextShotTime105 then return end
    self.NextShotTime105 = ct + self.GUN105_Delay

    local dir, muzzlePos = self:GetConeAimedDirection(self.AimConeDegrees)

    if HasGred() then
        local tr = util.QuickTrace(muzzlePos, dir * 99999, self)

        timer.Simple(0, function()
            if not IsValid(self) then return end
            gred.STRIKE.ARTILLERY(
                self,
                tr,
                "ARTILLERY",
                "BIGARTILLERY",
                1,
                155,
                "HE",
                10,
                1500
            )
        end)
    else
        local shell = ents.Create("rpg_missile")
        if IsValid(shell) then
            shell:SetPos(muzzlePos)
            shell:SetAngles(dir:Angle())
            shell:SetOwner(self)
            shell:Spawn()
            shell:Activate()

            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(dir * 1800)
            end
        end
    end

    self:SpawnWeaponMuzzleFX("cball_explode", 3)
    sound.Play("killstreak_rewards/ac-130_105mm_fire.wav", self.CenterPos, 95, math.random(96, 104), 1.0)
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

    local flatPos    = Vector(self.GetPos(self).x, self.GetPos(self).y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)

    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        self.ang = self.ang + Angle(0, 0.1, 0)
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
    if self.IdleLoop then
        self.IdleLoop:Stop()
    end
    if self.PlaneAmbientLoop then
        self.PlaneAmbientLoop:Stop()
    end
    if self.GAUSound and self.GAUSound:IsPlaying() then
        self.GAUSound:Stop()
    end
end

function ENT:FindGround(centerPos)
    local minheight = -16384
    local startPos  = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos    = Vector(centerPos.x, centerPos.y, minheight)
    local filterList = { self }

    local trace = {
        start  = startPos,
        endpos = endPos,
        filter = filterList
    }

    local maxNumber = 0
    local groundLocation = -1

    while maxNumber < 100 do
        local tr = util.TraceLine(trace)

        if tr.HitWorld then
            groundLocation = tr.HitPos.z
            break
        end

        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else
            break
        end

        maxNumber = maxNumber + 1
    end

    return groundLocation
end
