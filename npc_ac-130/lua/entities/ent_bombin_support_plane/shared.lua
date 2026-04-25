ENT.Type           = "anim"
ENT.Base           = "base_gmodentity"
ENT.PrintName      = "AC-130 Support Plane"
ENT.Author         = "Bombin"
ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- Precache HL2 Episode 2 base .pcf files that ship with every GMod install.
-- These are NOT TF2 particles — they exist in hl2ep2/particles/.
-- Must be done in shared.lua so the server runs them (PrecacheParticleSystem
-- is a no-op on client, game.AddParticles must run serverside).
game.AddParticles("particles/fire_01.pcf")      -- fastFire (HL2 base)
game.AddParticles("particles/largefire.pcf")    -- fastFire, smoke_blackbillow
game.AddParticles("particles/explosion.pcf")    -- Explosion_2_FireSmoke

PrecacheParticleSystem("fastFire")
PrecacheParticleSystem("smoke_blackbillow")
PrecacheParticleSystem("Explosion_2_FireSmoke")
