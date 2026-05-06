--[[
	Passby is a function that can be overriden, it has 2 parameters,
	distance and position. These parameters describe the closest approach
	of a bullet

	Passby=function(distance,position)
		if distance<512 then
			RBOEmitSound("crack.wav",position)
		else
			RBOEmitSound("crack_far.wav",position)
		end
	end

	You don't need to add support for every ammo type as they will
	assume a default type, these are here because they might change
]]

local function Play50Cal(distance,position)
	if distance<256 then
		RBOEmitSound("rbo_passby_50_close",position)
	elseif distance<768 then
		local rnd=math.random(10)
		if rnd<=5 then
			RBOEmitSound("rbo_passby_50_medium_2",position)
		else
			RBOEmitSound("rbo_passby_50_medium",position)
		end
	elseif distance<2500 then
		RBOEmitSound("rbo_passby_hiss_far",position)
	else
		RBOEmitSound("rbo_passby_50_far_2",position)
	end
end

--HL2 Support

RBOAddSupport({
	ammo="AR2",
	velocity=48000,
	Passby=RBOPlayRifle762Generic
})

RBOAddSupport({
	ammo="SMG1",
	velocity=48000,
	Passby=RBOPlayRifle556Generic

})

RBOAddSupport({
	ammo="Pistol",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="357",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="Buckshot",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

--CW2 Support

RBOAddSupport({
	ammo="9x19MM",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="12 Gauge",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo=".44 Magnum",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo=".45 ACP",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="9x17MM",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="9x39MM",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo=".50 AE",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="7.62x54MMR",
	velocity=48000,
	Passby=RBOPlayRifle762Generic
})

RBOAddSupport({
	ammo="7.62x51MM",
	velocity=48000,
	Passby=RBOPlayRifle762Generic
})

RBOAddSupport({
	ammo="7.62x39MM",
	velocity=48000,
	Passby=RBOPlayRifle762Generic
})

RBOAddSupport({
	ammo="5.45x39MM",
	velocity=48000,
	Passby=RBOPlayRifle556Generic
})

RBOAddSupport({
	ammo="5.56x45MM",
	velocity=48000,
	Passby=RBOPlayRifle556Generic
})

RBOAddSupport({
	ammo=".338 Lapua",
	velocity=48000,
	Passby=Play50Cal
})

RBOAddSupport({
	ammo="5.7x28MM",
	velocity=48000,
	Passby=RBOPlayRifle556Generic
})

--FAS support

RBOAddSupport({
	ammo=".50 BMG",
	velocity=48000,
	Passby=Play50Cal
})

RBOAddSupport({
	ammo="23x75MMR",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo=".454 Casull",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="9x18MM",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo="10x25MM",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo=".380 ACP",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})

RBOAddSupport({
	ammo=".357 SIG",
	velocity=24000,
	Passby=RBOPlayPistolSoundGeneric
})