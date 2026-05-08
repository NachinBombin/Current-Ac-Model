-- Realm: SERVER
-- Standalone AGM-158 JASSM owned by the AC-130 addon.
-- Spawned exclusively by ent_bombin_support_plane:UpdateJASSM().
-- No menu / no admin spawner.
--
-- Freefall phase uses MOVETYPE_NONE so we own the velocity completely.
-- We apply gravity manually each Think() tick and subtract a drag force
-- proportional to downward speed to produce true parachute dampening.
-- At FREEFALL_MAX_FALL the drag exactly cancels gravity = terminal velocity.
--
-- Ignition fires when pos.z reaches self.IgnitionAlt (checked every Think
-- tick at FREEFALL_THINK_DT = 1/66 s so overshoot is at most ~5 u).
-- After ignition the missile climbs 600 u to self.OrbitAlt and loiters there.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ================================================================
--  CONSTANTS
-- ================================================================

local PASS_SOUNDS = {
	"ambient/wind/wind_generic_loop1.wav",
	"ambient/wind/wind_generic_loop2.wav",
}

local ENGINE_LOOP_SOUND = "^jet/luxor/external.wav"
local SHARD_MODEL       = "models/props_c17/FurnitureDrawer001a_Shard01.mdl"
local GRAVITY_MULT      = 1.5
local SHARD_LIFE        = 8

-- Freefall physics constants.
-- GRAVITY         : Source default (600 u/s²) applied manually each tick.
-- FREEFALL_MAX_FALL: terminal velocity downward (u/s).  Drag coefficient is
--                   derived so that at this speed drag == gravity, giving
--                   a true asymptotic terminal velocity.
-- FREEFALL_THINK_DT: Think() interval during freefall (≈66 Hz).
local FREEFALL_GRAVITY    = 600
local FREEFALL_MAX_FALL   = 320
local FREEFALL_DRAG_K     = FREEFALL_GRAVITY / FREEFALL_MAX_FALL  -- k = g / v_terminal
local FREEFALL_THINK_DT   = 1 / 66

local CHUTE_ABOVE    = 105   -- chute floats this many units above missile origin
local ORBIT_ALT_RISE = 600   -- orbit band sits this many units above ignition altitude

ENT.WeaponWindow       = 8
ENT.DIVE_Speed         = 2200
ENT.DIVE_TrackInterval = 0.1

-- ================================================================
--  DEBUG
-- ================================================================

function ENT:Debug(msg)
	print("[Bombin JASSM Owned] " .. tostring(msg))
end

-- ================================================================
--  INITIALIZE
-- ================================================================

function ENT:Initialize()
	self.CenterPos    = self.CenterPos    or self:GetPos()
	self.CallDir      = self.CallDir      or Vector(1, 0, 0)
	self.Lifetime     = self.Lifetime     or 40
	self.SkyHeightAdd = self.SkyHeightAdd or 2500

	self.DIVE_ExplosionDamage = self.DIVE_ExplosionDamage or 1200
	self.DIVE_ExplosionRadius = self.DIVE_ExplosionRadius or 1200

	self.MaxHP = 200

	if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1, 0, 0) end
	self.CallDir.z = 0
	self.CallDir:Normalize()

	local ground = self:FindGround(self.CenterPos)
	if ground == -1 then
		self:Debug("FindGround failed")
		self:Remove()
		return
	end

	local altVariance    = self.SkyHeightAdd * 0.25
	-- IgnitionAlt: altitude at which the chute decouples and engine fires.
	-- OrbitAlt:    target loiter altitude, 600 u above ignition point.
	self.IgnitionAlt = ground + self.SkyHeightAdd + math.Rand(-altVariance, altVariance)
	self.OrbitAlt    = self.IgnitionAlt + ORBIT_ALT_RISE

	self.DieTime   = CurTime() + self.Lifetime
	self.SpawnTime = CurTime()

	local baseRadius = self.OrbitRadius or 2500
	local baseSpeed  = self.Speed       or 250
	self.OrbitRadius = baseRadius * math.Rand(0.82, 1.18)
	self.Speed       = baseSpeed  * math.Rand(0.85, 1.15)

	self.OrbitDir      = (math.random(0, 1) == 0) and 1 or -1
	self.OrbitAngle    = math.Rand(0, math.pi * 2)
	self.OrbitAngSpeed = (self.Speed / self.OrbitRadius) * self.OrbitDir

	-- ----------------------------------------------------------------
	--  Spawn position
	-- ----------------------------------------------------------------
	local spawnPos

	if self.SpawnedFromPlane then
		spawnPos = self:GetPos()
		self:Debug("SpawnedFromPlane: using tail pos " .. tostring(spawnPos))
	else
		local entryRad    = self.OrbitAngle
		local entryOffset = Vector(math.cos(entryRad), math.sin(entryRad), 0)
		local orbitXY     = self.CenterPos + entryOffset * (self.OrbitRadius * 1.05)
		spawnPos = Vector(orbitXY.x, orbitXY.y, self.IgnitionAlt + 900)
		if not util.IsInWorld(spawnPos) then
			spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.IgnitionAlt + 900)
		end
		self:Debug("Standalone: orbit-entry spawn " .. tostring(spawnPos))
	end

	if not util.IsInWorld(spawnPos) then
		self:Debug("Spawn position out of world")
		self:Remove()
		return
	end

	self:SetModel("models/sw/usa/missiles/agm/agm158.mdl")
	self:SetModelScale(1.6, 0)
	self:SetBodygroup(1, 0)   -- wings FOLDED during freefall
	self:SetRenderMode(RENDERMODE_NORMAL)
	self:SetPos(spawnPos)

	-- MOVETYPE_NONE: we own every byte of velocity during freefall.
	-- The engine will not apply gravity; we do it manually in Think().
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)

	self:SetNWInt("HP",         self.MaxHP)
	self:SetNWInt("MaxHP",      self.MaxHP)
	self:SetNWBool("Destroyed", false)
	self:SetNWBool("EngineOn",  false)

	local entryOffset = Vector(math.cos(self.OrbitAngle), math.sin(self.OrbitAngle), 0)
	local tangent     = Vector(-entryOffset.y, entryOffset.x, 0) * self.OrbitDir
	local startAng    = tangent:Angle()
	self:SetAngles(Angle(0, startAng.y, 0))
	self.ang = self:GetAngles()

	self.SmoothedRoll  = 0
	self.SmoothedPitch = 0
	self.PrevYaw       = self:GetAngles().y

	self.JitterPhase  = math.Rand(0, math.pi * 2)
	self.JitterPhase2 = math.Rand(0, math.pi * 2)
	self.JitterAmp1   = math.Rand(8,  18)
	self.JitterAmp2   = math.Rand(20, 45)
	self.JitterRate1  = math.Rand(0.030, 0.060)
	self.JitterRate2  = math.Rand(0.007, 0.015)

	-- AltDrift starts centred on OrbitAlt so the missile climbs there immediately.
	self.AltDriftCurrent  = self.OrbitAlt
	self.AltDriftTarget   = self.OrbitAlt
	self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
	self.AltDriftRange    = 700
	self.AltDriftLerp     = 0.003

	self.BaseCenterPos = Vector(self.CenterPos.x, self.CenterPos.y, self.CenterPos.z)
	self.WanderPhaseX  = math.Rand(0, math.pi * 2)
	self.WanderPhaseY  = math.Rand(0, math.pi * 2)
	self.WanderAmp     = math.Rand(60, 160)
	self.WanderRateX   = math.Rand(0.004, 0.010)
	self.WanderRateY   = math.Rand(0.003, 0.009)

	self.PhysObj = nil

	-- Freefall state: velocity is tracked in self.FreefallVelZ (u/s, negative = downward).
	self.FreefallVelZ  = 0

	self.EngineLoop    = nil
	self.NextPassSound = CurTime() + math.Rand(5, 10)

	self.CurrentWeapon   = nil
	self.WeaponWindowEnd = 0

	self.Diving           = false
	self.DiveTarget       = nil
	self.DiveTargetPos    = nil
	self.DiveNextTrack    = 0
	self.DiveExploded     = false
	self.DiveAimOffset    = Vector(0, 0, 0)

	self.DiveWobblePhase  = 0
	self.DiveWobbleAmp    = 180
	self.DiveWobbleSpeed  = 4.5
	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveWobbleAmpV   = 130
	self.DiveWobbleSpeedV = 3.1

	self.DiveSpeedMin     = self.DIVE_Speed * 0.55
	self.DiveSpeedCurrent = self.DIVE_Speed * 0.55
	self.DiveSpeedLerp    = 0.018

	self.DivePitchTelegraph = 0

	self.Destroyed       = false
	self.DestroyedTime   = nil
	self.TumbleAngVel    = Vector(0, 0, 0)
	self.ExplodeTimer    = nil
	self.ExplodedAlready = false

	self.EngineIgnited = false
	self.ChuteEnt      = nil

	-- Chute spawns directly above the missile's spawn position.
	local chute = ents.Create("ent_bombin_jassm_chute_owned")
	if IsValid(chute) then
		chute:SetOwner(self)
		chute:SetPos(Vector(spawnPos.x, spawnPos.y, spawnPos.z + CHUTE_ABOVE))
		chute:SetAngles(Angle(0, startAng.y, 0))
		chute:Spawn()
		chute:Activate()
		self.ChuteEnt = chute
	end

	self:Debug("Spawned at " .. tostring(spawnPos) ..
		", ignition alt " .. math.Round(self.IgnitionAlt) ..
		", orbit alt "    .. math.Round(self.OrbitAlt))
end

-- ================================================================
--  IGNITION
-- ================================================================

function ENT:IgniteEngine()
	if self.EngineIgnited then return end
	self.EngineIgnited = true
	self:SetNWBool("EngineOn", true)

	self:SetBodygroup(1, 1)   -- wings extended

	local pos = self:GetPos()

	-- Switch to VPHYSICS so PhysicsUpdate() can drive the climb + orbit.
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)

	self.PhysObj = self:GetPhysicsObject()
	if IsValid(self.PhysObj) then
		self.PhysObj:Wake()
		self.PhysObj:EnableGravity(false)
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		-- Launch forward at cruise speed; the altitude error (OrbitAlt - pos.z)
		-- in PhysicsUpdate will immediately generate upward vel.z to climb.
		self.PhysObj:SetVelocity(fwd * self.Speed)
	end

	-- Ignition burst cloud
	local ed = EffectData()
	ed:SetOrigin(pos + self:GetForward() * -55)
	ed:SetScale(2)
	ed:SetMagnitude(2)
	ed:SetRadius(200)
	util.Effect("HelicopterMegaBomb", ed, true, true)

	sound.Play("ambient/fire/gas_burst1.wav",       pos, 100, math.random(90, 110), 1.0)
	sound.Play("ambient/fire/fire_large_loop1.wav", pos, 85,  130,                  0.6)

	self.EngineLoop = CreateSound(self, ENGINE_LOOP_SOUND)
	if self.EngineLoop then
		self.EngineLoop:SetSoundLevel(130)
		self.EngineLoop:ChangePitch(100, 0)
		self.EngineLoop:ChangeVolume(1.0, 0.5)
		self.EngineLoop:Play()
	end

	self:Debug("Engine ignited -- climbing to orbit alt " .. math.Round(self.OrbitAlt))
end

-- ================================================================
--  DEATH STATE
-- ================================================================

function ENT:IsDestroyedState()
	return self.Destroyed == true
end

function ENT:SpawnDebrisShards()
	local count   = math.random(1, 2)
	local origin  = self:GetPos()
	local baseVel = self:GetVelocity()

	for i = 1, count do
		local shard = ents.Create("prop_physics")
		if not IsValid(shard) then continue end

		shard:SetModel(SHARD_MODEL)
		shard:SetPos(origin + Vector(math.Rand(-30, 30), math.Rand(-30, 30), math.Rand(-20, 20)))
		shard:SetAngles(Angle(math.Rand(0, 360), math.Rand(0, 360), math.Rand(0, 360)))
		shard:Spawn()
		shard:Activate()
		shard:SetColor(Color(15, 10, 10, 255))
		shard:SetMaterial("models/debug/debugwhite")

		local phys = shard:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:SetVelocity(baseVel * 0.3 + Vector(
				math.Rand(-300, 300),
				math.Rand(-300, 300),
				math.Rand(50,  250)
			))
			phys:AddAngleVelocity(Vector(
				math.Rand(-200, 200),
				math.Rand(-200, 200),
				math.Rand(-200, 200)
			))
		end

		shard:Ignite(SHARD_LIFE, 0)
		timer.Simple(SHARD_LIFE, function()
			if IsValid(shard) then shard:Remove() end
		end)
	end
end

function ENT:SetDestroyedState()
	if self.Destroyed then return end
	self.Destroyed = true
	self:SetNWBool("Destroyed", true)
	self.DestroyedTime = CurTime()

	if IsValid(self.ChuteEnt) then
		self.ChuteEnt:Remove()
		self.ChuteEnt = nil
	end

	if IsValid(self.PhysObj) then
		local existing = self.PhysObj:GetAngleVelocity()
		self.TumbleAngVel = existing + Vector(
			math.Rand(-120, 120),
			math.Rand(-120, 120),
			math.Rand(-120, 120)
		)
		self.PhysObj:EnableGravity(true)
		self.PhysObj:AddAngleVelocity(self.TumbleAngVel)
	end

	self:Ignite(20, 0)
	self:SpawnDebrisShards()

	if self.EngineLoop then
		self.EngineLoop:ChangeVolume(0, 1.5)
		self.EngineLoop:ChangePitch(55, 2.5)
	end

	local altAboveGround = self:GetPos().z - self.IgnitionAlt
	local delay = math.Clamp(altAboveGround / 600, 3, 12)
	self.ExplodeTimer = CurTime() + delay

	if not self.Diving then
		self.CurrentWeapon = nil
	end

	self:Debug("DESTROYED -- boom in " .. math.Round(delay, 1) .. "s")
end

-- ================================================================
--  DAMAGE
-- ================================================================

function ENT:OnTakeDamage(dmginfo)
	if self.ExplodedAlready then return end
	if dmginfo:IsDamageType(DMG_CRUSH) then return end

	local hp = self:GetNWInt("HP", self.MaxHP or 200)
	hp = hp - dmginfo:GetDamage()
	self:SetNWInt("HP", hp)

	if hp <= 0 and not self:IsDestroyedState() then
		self:Debug("Shot down!")
		self:SetDestroyedState()
	end
end

-- ================================================================
--  THINK
-- ================================================================

function ENT:Think()
	if not self.DieTime or not self.SpawnTime then
		self:NextThink(CurTime() + 0.1)
		return true
	end

	local ct = CurTime()
	if ct >= self.DieTime then self:Remove() return end

	-- ---- Destroyed (pre-ignition or post-ignition) ----
	if self:IsDestroyedState() then
		if self.ExplodeTimer and ct >= self.ExplodeTimer then
			self:CrashExplode(self:GetPos())
			return true
		end
		self:NextThink(ct + 0.05)
		return true
	end

	-- ================================================================
	--  FREEFALL PHASE  (MOVETYPE_NONE, we own the velocity)
	-- ================================================================
	if not self.EngineIgnited then
		local dt = FREEFALL_THINK_DT

		-- Step 1: apply gravity, then apply upward drag.
		-- Net acceleration = -g + k*v  (v is negative when falling)
		-- This gives true terminal velocity: at v = -g/k = -FREEFALL_MAX_FALL
		-- drag exactly cancels gravity, acceleration goes to zero.
		self.FreefallVelZ = self.FreefallVelZ - FREEFALL_GRAVITY * dt
		local drag = FREEFALL_DRAG_K * (-self.FreefallVelZ)  -- drag magnitude (positive)
		self.FreefallVelZ = self.FreefallVelZ + drag * dt

		-- Hard clamp as a safety net (floating point drift).
		if self.FreefallVelZ < -FREEFALL_MAX_FALL then
			self.FreefallVelZ = -FREEFALL_MAX_FALL
		end

		-- Step 2: integrate position.
		local pos = self:GetPos()
		local newZ = pos.z + self.FreefallVelZ * dt
		self:SetPos(Vector(pos.x, pos.y, newZ))

		-- Step 3: nose-down attitude during freefall (cosmetic).
		local ang = self:GetAngles()
		self:SetAngles(Angle(
			Lerp(0.12, ang.p, -15),
			ang.y,
			Lerp(0.12, ang.r, 0)
		))

		-- Step 4: check for ignition altitude.
		-- Snap to IgnitionAlt so we never overshoot by more than one tick.
		if newZ <= self.IgnitionAlt then
			self:SetPos(Vector(pos.x, pos.y, self.IgnitionAlt))
			self:IgniteEngine()
			-- Fall through to post-ignition logic below.
		else
			self:NextThink(ct + FREEFALL_THINK_DT)
			return true
		end
	end

	-- ================================================================
	--  POST-IGNITION PHASE
	-- ================================================================
	if not IsValid(self.PhysObj) then
		self.PhysObj = self:GetPhysicsObject()
	end
	if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
		self.PhysObj:Wake()
	end

	if ct >= self.NextPassSound then
		sound.Play(
			table.Random(PASS_SOUNDS),
			self:GetPos(), 90, math.random(96, 104), 0.7
		)
		self.NextPassSound = ct + math.Rand(8, 16)
	end

	if self.Diving then
		self:UpdateDive(ct)
	else
		self:HandleWeaponWindow(ct)
	end

	self:NextThink(ct)
	return true
end

-- ================================================================
--  PHYSICS UPDATE  (only active after ignition / vphysics)
-- ================================================================

function ENT:PhysicsUpdate(phys)
	if not self.DieTime or not self.IgnitionAlt then return end
	if CurTime() >= self.DieTime then self:Remove() return end
	if not self.EngineIgnited then return end

	-- ---- Destroyed: tumble under gravity ----
	if self:IsDestroyedState() then
		local dt = FrameTime()
		if dt <= 0 then dt = 0.01 end

		local angVel = phys:GetAngleVelocity()
		phys:AddAngleVelocity(angVel * 0.08 * dt * 60)

		local extraG = -600 * (GRAVITY_MULT - 1) * phys:GetMass()
		phys:ApplyForceCenter(Vector(0, 0, extraG))

		local pos  = self:GetPos()
		local vel  = phys:GetVelocity()
		local dt2  = FrameTime()
		if dt2 <= 0 then dt2 = 0.01 end
		local next = pos + vel * dt2 + Vector(0, 0, -24)
		local tr = util.TraceLine({
			start  = pos,
			endpos = next,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		if tr.Hit then self:CrashExplode(tr.HitPos) end
		return
	end

	-- ---- Normal orbit / climb to OrbitAlt (non-dive) ----
	if self.Diving then return end

	local pos = self:GetPos()
	local dt  = FrameTime()
	if dt <= 0 then dt = 0.01 end

	self.WanderPhaseX = self.WanderPhaseX + self.WanderRateX
	self.WanderPhaseY = self.WanderPhaseY + self.WanderRateY
	self.CenterPos = Vector(
		self.BaseCenterPos.x + math.sin(self.WanderPhaseX) * self.WanderAmp,
		self.BaseCenterPos.y + math.sin(self.WanderPhaseY) * self.WanderAmp,
		self.BaseCenterPos.z
	)

	self.OrbitAngSpeed = (self.Speed / self.OrbitRadius) * self.OrbitDir
	self.OrbitAngle    = self.OrbitAngle + self.OrbitAngSpeed * dt

	local desiredX = self.CenterPos.x + math.cos(self.OrbitAngle) * self.OrbitRadius
	local desiredY = self.CenterPos.y + math.sin(self.OrbitAngle) * self.OrbitRadius

	local tangentYaw    = math.deg(self.OrbitAngle) + 90 * self.OrbitDir
	local yawError      = math.NormalizeAngle(tangentYaw - self.ang.y)
	local yawCorrection = math.Clamp(yawError * 0.08, -0.6, 0.6)
	self.ang            = self.ang + Angle(0, yawCorrection, 0)

	self.JitterPhase  = self.JitterPhase  + self.JitterRate1
	self.JitterPhase2 = self.JitterPhase2 + self.JitterRate2
	local jitter = math.sin(self.JitterPhase)  * self.JitterAmp1
	             + math.sin(self.JitterPhase2) * self.JitterAmp2

	if CurTime() >= self.AltDriftNextPick then
		-- Drift is centred on OrbitAlt; never let it fall below IgnitionAlt.
		self.AltDriftTarget   = self.OrbitAlt + math.Rand(-self.AltDriftRange, self.AltDriftRange)
		self.AltDriftTarget   = math.max(self.AltDriftTarget, self.IgnitionAlt + 50)
		self.AltDriftNextPick = CurTime() + math.Rand(10, 25)
	end
	self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
	local liveAlt = self.AltDriftCurrent + jitter

	local posErr = Vector(desiredX - pos.x, desiredY - pos.y, 0)
	local vel    = self:GetForward() * self.Speed
	if posErr:LengthSqr() > 400 then
		vel = vel + posErr:GetNormalized() * 80
	end

	-- Proportional altitude controller: works for both the initial 600u climb
	-- and steady-state altitude hold once OrbitAlt is reached.
	local altError = liveAlt - pos.z
	vel.z = math.Clamp(altError * 8, -120, 120)

	local rawYawDelta  = math.NormalizeAngle(self.ang.y - (self.PrevYaw or self.ang.y))
	self.PrevYaw       = self.ang.y
	local targetRoll   = math.Clamp(rawYawDelta * -25, -30, 30)
	self.SmoothedRoll  = Lerp(rawYawDelta ~= 0 and 0.15 or 0.05, self.SmoothedRoll, targetRoll)

	local physVel      = IsValid(phys) and phys:GetVelocity() or Vector(0, 0, 0)
	local forwardSpeed = physVel:Dot(self:GetForward())
	local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
	local targetPitch  = math.Clamp(speedRatio * 10, -15, 15)
	self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, targetPitch)

	self.ang.p = self.SmoothedPitch
	self.ang.r = self.SmoothedRoll
	self:SetAngles(self.ang)

	if IsValid(phys) then
		phys:SetVelocity(vel)
	end

	if not self:IsInWorld() then
		self:Debug("Out of world -- removing")
		self:Remove()
	end
end

-- ================================================================
--  TARGET
-- ================================================================

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

-- ================================================================
--  WEAPON WINDOW
-- ================================================================

function ENT:HandleWeaponWindow(ct)
	if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
		self:PickNewWeapon(ct)
	end
	if self.CurrentWeapon == "dive" then
		self:InitDive(ct)
	end
end

function ENT:PickNewWeapon(ct)
	local roll = math.random(1, 3)
	if roll == 1 then
		self.CurrentWeapon = "peaceful_1"
	elseif roll == 2 then
		self.CurrentWeapon = "peaceful_2"
	else
		self.CurrentWeapon = "dive"
	end
	self.WeaponWindowEnd = ct + self.WeaponWindow
	self:Debug("Behavior slot: " .. self.CurrentWeapon)
end

-- ================================================================
--  DIVE
-- ================================================================

function ENT:InitDive(ct)
	if self.Diving then return end

	if not self.DiveCommitTime then
		self.DiveCommitTime = ct + 1.0
		self:Debug("DIVE: locking target in 1s...")
		return
	end

	local frac = math.Clamp((ct - (self.DiveCommitTime - 1.0)) / 1.0, 0, 1)
	self.DivePitchTelegraph = frac * -60
	self:SetAngles(Angle(self.DivePitchTelegraph, self.ang.y, self.SmoothedRoll))

	if ct < self.DiveCommitTime then return end

	local target = self:GetPrimaryTarget()
	if not IsValid(target) then
		self.CurrentWeapon      = nil
		self.DiveCommitTime     = nil
		self.DivePitchTelegraph = 0
		return
	end

	self.Diving             = true
	self.DiveTarget         = target
	self.DiveTargetPos      = target:GetPos()
	self.DiveNextTrack      = ct
	self.DiveExploded       = false
	self.DiveCommitTime     = nil
	self.DivePitchTelegraph = 0
	self.DiveWobblePhase    = 0
	self.DiveWobblePhaseV   = math.Rand(0, math.pi * 2)
	self.DiveSpeedCurrent   = self.DiveSpeedMin
	self.DiveAimOffset      = Vector(math.Rand(-400, 400), math.Rand(-400, 400), 0)

	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetSolid(SOLID_VPHYSICS)
	if IsValid(self.PhysObj) then
		self.PhysObj:EnableGravity(false)
	end

	self:Debug("DIVE: committed -- aim offset " .. tostring(self.DiveAimOffset))
end

function ENT:UpdateDive(ct)
	if self.DiveExploded then return end

	if ct >= self.DiveNextTrack then
		if not self:IsDestroyedState() then
			if IsValid(self.DiveTarget) and self.DiveTarget:Alive() then
				self.DiveTargetPos = self.DiveTarget:GetPos() + Vector(
					math.Rand(-120, 120),
					math.Rand(-120, 120),
					0
				)
			end
		end
		self.DiveNextTrack = ct + self.DIVE_TrackInterval
	end

	if not self.DiveTargetPos then self:Remove() return end

	local myPos = self:GetPos()
	local dir   = (self.DiveTargetPos + self.DiveAimOffset) - myPos
	local dist  = dir:Length()

	if dist < 120 then
		if self:IsDestroyedState() then
			self:CrashExplode(myPos)
		else
			self:DiveExplode(myPos)
		end
		return
	end
	dir:Normalize()

	if self:IsDestroyedState() then return end

	self.DiveSpeedCurrent = Lerp(self.DiveSpeedLerp, self.DiveSpeedCurrent, self.DIVE_Speed)

	local dt = FrameTime()
	if dt <= 0 then dt = 0.01 end
	self.DiveWobblePhase  = self.DiveWobblePhase  + self.DiveWobbleSpeed  * dt
	self.DiveWobblePhaseV = self.DiveWobblePhaseV + self.DiveWobbleSpeedV * dt

	local flatRight = Vector(-dir.y, dir.x, 0)
	if flatRight:LengthSqr() < 0.01 then flatRight = Vector(1, 0, 0) end
	flatRight:Normalize()
	local worldUp = Vector(0, 0, 1)
	local upPerp  = worldUp - dir * dir:Dot(worldUp)
	if upPerp:LengthSqr() < 0.01 then upPerp = Vector(0, 1, 0) end
	upPerp:Normalize()

	local wobbleScale = math.Clamp(dist / 400, 0, 1)
	local wobbleVel   = flatRight * math.sin(self.DiveWobblePhase)  * self.DiveWobbleAmp  * wobbleScale
	                  + upPerp   * math.sin(self.DiveWobblePhaseV) * self.DiveWobbleAmpV * wobbleScale

	local totalVel = dir * self.DiveSpeedCurrent + wobbleVel

	if totalVel:LengthSqr() > 0.01 then
		local faceAng = totalVel:GetNormalized():Angle()
		faceAng.r = 0
		self:SetAngles(faceAng)
		self.ang = faceAng
	end

	local nextPos = myPos + totalVel * dt
	local tr = util.TraceLine({
		start  = myPos,
		endpos = nextPos,
		filter = self,
		mask   = MASK_SOLID,
	})
	if tr.Hit then self:DiveExplode(tr.HitPos) return end

	if IsValid(self.PhysObj) then
		self.PhysObj:SetVelocity(totalVel)
	end
end

-- ================================================================
--  EXPLOSIONS
-- ================================================================

local function FireEffect(origin, effect, scale)
	local ed = EffectData()
	ed:SetOrigin(origin)
	ed:SetScale(scale)
	ed:SetMagnitude(scale)
	ed:SetRadius(scale * 100)
	util.Effect(effect, ed, true, true)
end

function ENT:DiveExplode(pos)
	if self.DiveExploded then return end
	self.DiveExploded    = true
	self.ExplodedAlready = true
	self:Debug("DIVE: exploding at " .. tostring(pos))

	FireEffect(pos,                   "HelicopterMegaBomb", 8)
	FireEffect(pos,                   "500lb_air",          7)
	FireEffect(pos + Vector(0,0, 80), "500lb_air",          6)
	FireEffect(pos + Vector(0,0,160), "500lb_air",          5)
	FireEffect(pos + Vector(0,0, 20), "HelicopterMegaBomb", 6)

	sound.Play("weapon_AWP.Single",               pos,                155, 52, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos,                150, 78, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos+Vector(0,0,40), 145, 85, 0.9)

	util.BlastDamage(self, self, pos, self.DIVE_ExplosionRadius, self.DIVE_ExplosionDamage)
	self:Remove()
end

function ENT:CrashExplode(pos)
	if self.ExplodedAlready then return end
	self.ExplodedAlready = true
	self:Debug("CRASH: exploding at " .. tostring(pos))

	FireEffect(pos,                  "HelicopterMegaBomb", 5)
	FireEffect(pos,                  "500lb_air",          4)
	FireEffect(pos + Vector(0,0,60), "500lb_air",          3)

	sound.Play("ambient/explosions/explode_8.wav", pos, 145, 72, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos, 140, 88, 0.8)

	util.BlastDamage(self, self, pos, self.DIVE_ExplosionRadius * 0.6, self.DIVE_ExplosionDamage * 0.3)
	self:Remove()
end

-- ================================================================
--  MISC
-- ================================================================

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
		else
			break
		end
		maxIter = maxIter + 1
	end
	return -1
end

function ENT:OnRemove()
	if self.EngineLoop then self.EngineLoop:Stop() end
	if IsValid(self.ChuteEnt) then self.ChuteEnt:Remove() end
end
