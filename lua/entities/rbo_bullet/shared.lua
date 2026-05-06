ENT.Type="anim"
ENT.Base="base_gmodentity"
ENT.Author="joshsw"
ENT.Spawnable=false
ENT.AdminSpawnable=false
ENT.AutomaticFrameAdvance=true

--network vars

--vectors
RBO_BULLET_VEC_VELOCITY=0
RBO_BULLET_VEC_ACCELERATION=1
RBO_BULLET_VEC_POSITION=2
--strings
RBO_BULLET_STR_AMMOTYPE=0
--ents
RBO_BULLET_ENT_SHOOTER=0

local visflag=bit.bor(CONTENTS_WATER,MASK_SHOT)

function ENT:RBOGetPosition()
	return self.position
end

local function ReadVectorPrecise()
	return Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
end

local function WriteVectorPrecise(v)
	net.WriteFloat(v.x)
	net.WriteFloat(v.y)
	net.WriteFloat(v.z)
end

if SERVER then
util.AddNetworkString("RBOBulletSync")

function ENT:Think()
	--bullets travel instantaneously in water, FIX!
	if not util.IsInWorld(self.position) then
		self:Remove()
		return
	end
	self.delta_time=CurTime()-self.curtime
	self.curtime=CurTime()
	local nextpos=self.position+self.velocity*self.delta_time
	local trace=util.TraceLine({
		start=self.position,	
		endpos=nextpos,
		mask=visflag,
		filter=self.source
	})
	if trace.Hit or trace.StartSolid then
		if not IsValid(self.source) then
			self:Remove()
			return true
		end
		self.source.rbo_no_refire=true
		self.data.Src=trace.StartPos
		self.data.Num=1
		self.data.Spread=Vector()
		self.data.TracerName=nil	
		self.data.Tracer=0	
		self.data.Dir=self.velocity:GetNormalized()
		self.source:FireBullets(self.data)
		self:Remove()
		return true
	end	
	self.position=nextpos
	self.velocity=self.velocity+self.acceleration*self.delta_time
	net.Start("RBOBulletSync")	
	net.WriteEntity(self)
	WriteVectorPrecise(self.position)
	WriteVectorPrecise(self.velocity)
	net.Broadcast()
	self:NextThink(CurTime())
	self:SetPos(self.position)
	return true
end
end

if CLIENT then
function ENT:Think()
	--flybys are inconsistent when close to impact, FIX!
	if not self.initialized then
		self:Initialize()
	end
	self.delta_time=CurTime()-self.curtime
	self.curtime=CurTime()
	local nextpos=self.position+self.velocity*self.delta_time
	self:SetNextClientThink(CurTime())
	local trace=util.TraceLine({
		start=self.position,	
		endpos=nextpos,
		mask=visflag,
		filter=self.source
	})
	if trace.Hit or trace.StartSolid then
		--self:Whiz()
		return true
	end
	self.position=nextpos
	self.velocity=self.velocity+self.acceleration*self.delta_time
	self:Whiz()
	return true
end

net.Receive("RBOBulletSync",function()
	local ent=net.ReadEntity()
	if not IsValid(ent) then
		return
	end
	ent.position=ReadVectorPrecise()
	ent.velocity=ReadVectorPrecise()
end)
end