ENT.Type         = "anim"
ENT.Base         = "base_gmodentity"
ENT.PrintName    = "AC-130 Support Plane"
ENT.Author       = "Bombin"
ENT.Spawnable    = false
ENT.AdminSpawnable = false

-- Precache particle files shared (required before ParticleEffectAttach / CreateParticleEffect)
game.AddParticles("particles/fire_01.pcf")
game.AddParticles("particles/fire_02.pcf")
game.AddParticles("particles/smoke_01.pcf")
game.AddParticles("particles/smoke_02.pcf")

PrecacheParticleSystem("fire_medium_02")
PrecacheParticleSystem("fire_large_02")
PrecacheParticleSystem("smoke_stack")
PrecacheParticleSystem("smoke_exhaust")