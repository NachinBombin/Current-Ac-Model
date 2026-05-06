-- Realm: CLIENT
-- Standalone JASSM -- client draw, flame trail, ignition sound.

include("shared.lua")

local FLAME_MODEL = "models/roycombat/shared/trail_f22.mdl"
local BACK_OFFSET = 55
local FLAME_SCALE = 0.55

local IGNITION_SOUNDS = {
	"jassm/missile_1.wav",
	"jassm/missile_2.wav",
	"jassm/missile_3.wav",
	"jassm/missile_4.wav",
}

function ENT:Initialize()
	self:SetModelScale(1.6, 0)
	-- Bodygroup is server-controlled: 0 = wings folded (freefall), 1 = wings deployed

	self._engineWasOn = false

	-- Defer clientside model creation by one frame to avoid init-frame model quirks
	timer.Simple(0, function()
		if not IsValid(self) then return end
		self._flameProp = ClientsideModel(FLAME_MODEL)
		if IsValid(self._flameProp) then
			self._flameProp:SetModelScale(FLAME_SCALE, 0)
			self._flameProp:SetNoDraw(true)
		end
	end)
end

function ENT:Draw()
	self:DrawModel()

	local engineOn = self:GetNWBool("EngineOn", false)

	-- Play the ignition sound exactly once when EngineOn transitions false -> true
	if engineOn and not self._engineWasOn then
		self._engineWasOn = true
		local snd = IGNITION_SOUNDS[math.random(1, #IGNITION_SOUNDS)]
		sound.Play(snd, self:GetPos(), 110, math.random(95, 105), 1.0)
	end

	if not engineOn then return end
	if not IsValid(self._flameProp) then return end

	local exhaustPos = self:GetPos() + (-self:GetForward()) * BACK_OFFSET
	local ang = self:GetAngles()
	ang.y = ang.y + 180

	self._flameProp:SetPos(exhaustPos)
	self._flameProp:SetAngles(ang)
	self._flameProp:DrawModel()

	-- Orange dynamic light at the exhaust
	local dlight = DynamicLight(self:EntIndex())
	if dlight then
		dlight.pos        = exhaustPos
		dlight.r          = 255
		dlight.g          = 120
		dlight.b          = 20
		dlight.brightness = 4
		dlight.Decay      = 1200
		dlight.Size       = math.Rand(280, 380)
		dlight.DieTime    = CurTime() + 0.05
	end
end

function ENT:OnRemove()
	if IsValid(self._flameProp) then
		self._flameProp:Remove()
	end
end
