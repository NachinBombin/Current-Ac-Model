-- Realm: CLIENT
-- Parachute visual for the owned JASSM.

include("shared.lua")

local CHUTE_MODEL = "models/v92/parachutez/flying.mdl"

function ENT:Initialize()
	self:SetModel(CHUTE_MODEL)
end

function ENT:Draw()
	self:DrawModel()
end
