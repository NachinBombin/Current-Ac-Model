-- lua/entities/gb_rocket_depleted_105mm.lua

AddCSLuaFile()

ENT.Type      = "anim"
ENT.Base      = "base_rocket"
DEFINE_BASECLASS("base_rocket")

ENT.Spawnable      = true
ENT.AdminSpawnable = true
ENT.PrintName      = "[ROCKETS] Depleted 105mm Artillery Shell"
ENT.Author         = ""
ENT.Contact        = ""
ENT.Category       = "Gredwitch's Stuff"

-- Original howitzer shell model
ENT.Model = "models/gredwitch/artillery_shell.mdl"

-- ── Gredwitch explosion effects (500lb family only) ───────────────────────
ENT.Effect      = "500lb_air"
ENT.EffectAir   = "500lb_air"
ENT.EffectWater = "ins_water_explosion"

-- ── Sounds ────────────────────────────────────────────────────────────────
ENT.StartSound       = ""
ENT.ArmSound         = ""
ENT.ActivationSound  = ""
ENT.EngineSound      = ""

local CloseExploSnds = {
    "explosions/doi_generic_01_close.wav",
    "explosions/doi_generic_02_close.wav",
    "explosions/doi_generic_03_close.wav",
    "explosions/doi_generic_04_close.wav",
}
local FarExploSnds = {
    "explosions/doi_generic_01.wav",
    "explosions/doi_generic_02.wav",
    "explosions/doi_generic_03.wav",
    "explosions/doi_generic_04.wav",
}
local DistExploSnds = {
    "explosions/doi_generic_01_dist.wav",
    "explosions/doi_generic_02_dist.wav",
    "explosions/doi_generic_03_dist.wav",
    "explosions/doi_generic_04_dist.wav",
}
local WaterCloseSnds = {
    "explosions/doi_generic_02_closewater.wav",
    "explosions/doi_generic_03_closewater.wav",
    "explosions/doi_generic_04_closewater.wav",
}
local WaterFarSnds = {
    "explosions/doi_generic_01_water.wav",
    "explosions/doi_generic_02_water.wav",
    "explosions/doi_generic_03_water.wav",
    "explosions/doi_generic_04_water.wav",
}

ENT.ExplosionSound         = table.Random(CloseExploSnds)
ENT.FarExplosionSound      = table.Random(FarExploSnds)
ENT.DistExplosionSound     = table.Random(DistExploSnds)
ENT.WaterExplosionSound    = table.Random(WaterCloseSnds)
ENT.WaterFarExplosionSound = table.Random(WaterFarSnds)
ENT.RSound                 = 0

-- ── Rocket behaviour ──────────────────────────────────────────────────────
ENT.ShouldUnweld     = true
ENT.ShouldIgnite     = true
ENT.UseRandomSounds  = true
ENT.SmartLaunch      = true
ENT.Timed            = false

ENT.RocketTrail        = ""
ENT.RocketBurnoutTrail = ""

-- ── Blast parameters ──────────────────────────────────────────────────────
ENT.ExplosionDamage  = 600
ENT.ExplosionRadius  = 600
ENT.PhysForce        = 800
ENT.SpecialRadius    = 600

ENT.MaxIgnitionTime  = 0
ENT.Life             = 1
ENT.MaxDelay         = 0
ENT.TraceLength      = 50
ENT.ImpactSpeed      = 100

ENT.Mass             = 45
ENT.EnginePower      = 5000
ENT.FuelBurnoutTime  = 0.5
ENT.IgnitionDelay    = 0.1
ENT.ArmDelay         = 0
ENT.RotationalForce  = 0
ENT.ForceOrientation = "NORMAL"
ENT.Timer            = 0

ENT.DEFAULT_PHYSFORCE           = 200
ENT.DEFAULT_PHYSFORCE_PLYAIR    = 30
ENT.DEFAULT_PHYSFORCE_PLYGROUND = 1200
ENT.Shocktime                   = 3

ENT.GBOWNER = nil

-- ── Spawn function ────────────────────────────────────────────────────────
function ENT:SpawnFunction(ply, tr)
    if not tr.Hit then return end
    self.GBOWNER = ply

    local ent = ents.Create(self.ClassName)
    if not IsValid(ent) then return end

    ent:SetPhysicsAttacker(ply)
    ent:SetPos(tr.HitPos + tr.HitNormal * 16)
    ent:Spawn()
    ent:Activate()

    ent.ExplosionSound         = table.Random(CloseExploSnds)
    ent.FarExplosionSound      = table.Random(FarExploSnds)
    ent.DistExplosionSound     = table.Random(DistExploSnds)
    ent.WaterExplosionSound    = table.Random(WaterCloseSnds)
    ent.WaterFarExplosionSound = table.Random(WaterFarSnds)

    return ent
end

-- ── Stacked Gredwitch 500lb impact effects ────────────────────────────────
function ENT:OnExplode(pos, normal)

    -- 1. Ground-level primary blast column
    local ed1 = EffectData()
    ed1:SetOrigin(pos)
    ed1:SetScale(6)
    ed1:SetMagnitude(6)
    ed1:SetRadius(600)
    util.Effect("500lb_air", ed1, true, true)

    -- 2. Second 500lb burst raised slightly for a tall rising fireball column
    local ed2 = EffectData()
    ed2:SetOrigin(pos + Vector(0, 0, 80))
    ed2:SetScale(5)
    ed2:SetMagnitude(5)
    ed2:SetRadius(500)
    util.Effect("500lb_air", ed2, true, true)

    -- 3. Third 500lb burst even higher for the towering top of the column
    local ed3 = EffectData()
    ed3:SetOrigin(pos + Vector(0, 0, 180))
    ed3:SetScale(4)
    ed3:SetMagnitude(4)
    ed3:SetRadius(400)
    util.Effect("500lb_air", ed3, true, true)

    -- 4. HelicopterMegaBomb at ground level for the wide dirt/debris skirt
    local ed4 = EffectData()
    ed4:SetOrigin(pos)
    ed4:SetScale(6)
    ed4:SetMagnitude(6)
    ed4:SetRadius(600)
    util.Effect("HelicopterMegaBomb", ed4, true, true)

    -- 5. Second HelicopterMegaBomb offset upward to thicken the mid-column smoke
    local ed5 = EffectData()
    ed5:SetOrigin(pos + Vector(0, 0, 100))
    ed5:SetScale(5)
    ed5:SetMagnitude(5)
    ed5:SetRadius(500)
    util.Effect("HelicopterMegaBomb", ed5, true, true)

end
