AddCSLuaFile("rbo/sounds.lua")
AddCSLuaFile("rbo/supports.lua")

include("rbo/sounds.lua")

local support={}

if CLIENT then
hook.Add("EntityFireBullets","rbo_efb",function()
	return false
end)
function RBOEmitSound(s,pos,level,pitch,volume)
	local dir=pos-GetViewEntity():EyePos()
	dir:Normalize()
	sound.Play(s,GetViewEntity():EyePos()+dir*32,level,pitch,volume)
end

function RBOPlayRifle762Generic(distance,position)
	if distance<256 then
		local rnd=math.random(10)
		if rnd<=3 then
			RBOEmitSound("rbo_passby_hiss_close",position)
		else
			RBOEmitSound("rbo_passby_762_close",position)
		end
	elseif distance<768 then
		local rnd=math.random(10)
		if rnd<=2 then
			RBOEmitSound("rbo_passby_762_wizz",position)
		else
			RBOEmitSound("rbo_passby_hiss_close",position)
		end
	elseif distance<2000 then
		local rnd=math.random(10)
		if rnd<=2 then
			RBOEmitSound("rbo_passby_762_medium",position)
		else
			RBOEmitSound("rbo_passby_hiss_far",position)
		end
	else
		RBOEmitSound("rbo_passby_762_far",position)
	end
end

function RBOPlayRifle556Generic(distance,position)
	if distance<256 then
		local rnd=math.random(10)
		if rnd<=3 then
			RBOEmitSound("rbo_passby_hiss_close",position)
		else
			RBOEmitSound("rbo_passby_556_close",position)
		end
	elseif distance<768 then
		local rnd=math.random(10)
		if rnd<=2 then
			RBOEmitSound("rbo_passby_556_wizz",position)
		else
			RBOEmitSound("rbo_passby_hiss_close",position)
		end
	elseif distance<2000 then
		local rnd=math.random(10)
		if rnd<=2 then
			RBOEmitSound("rbo_passby_556_medium",position)
		else
			RBOEmitSound("rbo_passby_hiss_far",position)
		end
	else
		RBOEmitSound("rbo_passby_556_far",position)
	end
end

function RBOPlayPistolSoundGeneric(distance,position)
	if distance<1024 then
		local rnd=math.random(10)
		if rnd<=5 then
			RBOEmitSound("rbo_passby_9mm",position)
		else
			RBOEmitSound("rbo_passby_9mm_2",position)
		end
	end
end
end

local rbo_fallback_support={
	ammo="AR2",
	use_tracer=false,
	velocity=48000,
	Passby=RBOPlayRifle762Generic	
}

function RBOAddSupport(info)
	assert(type(info.ammo)=="string")
	if game.GetAmmoID(info.ammo)<0 and SERVER then
		MsgC("RBO Tried to add unknown ammo type "..info.ammo.." doesn't exist\n")
		return
	end
	assert(type(info.velocity)=="number")
	support[info.ammo]={tracers=use_tracer,velocity=info.velocity}
	if CLIENT then
		assert(info.Passby~=nil and type(info.Passby)=="function")
		support[info.ammo].Passby=info.Passby or rbo_fallback_support.Passby
	end
end

function RBOGetSupported(ammotype)
	return support[ammotype] or rbo_fallback_support
end

include("rbo/supports.lua")

if SERVER then
hook.Add("EntityFireBullets","rbo_efb",function(ent,info)
	if ent.rbo_no_refire then
		ent.rbo_no_refire=nil
		return true
	end

	if ent:IsPlayer() or ent:IsNPC() then
		local wep=ent:GetActiveWeapon()
		if IsValid(wep) and wep:IsScripted() then
			info.AmmoType=weapons.Get(wep:GetClass()).Primary.Ammo
		end
	end

	local sup=RBOGetSupported(info.AmmoType)
	for i=1,info.Num do
		local bullet=ents.Create("rbo_bullet")
		local right=info.Dir:Angle():Right()
		local up=info.Dir:Angle():Up()
		local f=0.5
		local x=(math.Rand(-1,1)*f)+(math.Rand(-1,1)*(1-f))
		local y=(math.Rand(-1,1)*f)+(math.Rand(-1,1)*(1-f))
		local dir=info.Dir+(right*x*info.Spread.x)+(up*y*info.Spread.y)

		bullet:SetDTVector(RBO_BULLET_VEC_VELOCITY,dir*sup.velocity)
		bullet:SetDTVector(RBO_BULLET_VEC_ACCELERATION,Vector(0,0,-514))
		bullet:SetDTVector(RBO_BULLET_VEC_POSITION,info.Src)
		bullet:SetDTEntity(RBO_BULLET_ENT_SHOOTER,ent)
		bullet:SetDTString(RBO_BULLET_STR_AMMOTYPE,info.AmmoType)
		
		bullet.source=ent
		bullet.data=table.Copy(info)

		bullet:SetPos(info.Src)
		bullet:Spawn()
	end
	return false
end)
end