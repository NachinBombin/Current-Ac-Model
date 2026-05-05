AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local BULLET_MODEL  = "models/weapons/bt_762.mdl"
local BLAST_RADIUS  = 80
local BLAST_DAMAGE  = 40
local HEI_INTERVAL  = 90
local GAU_CAL_ID    = 3
local MUZZLE_VEL    = 85000
local MAX_DIST      = 22000
local MIN_SPEED     = 200
local FORCE_MUL     = 5.0

local IMPACT_SOUNDS = {
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
}

local GAU_BRRT_SOUNDS = {
    "gunsounds/brrt_01.wav",
    "gunsounds/brrt_02.wav",
    "gunsounds/brrt_03.wav",
    "gunsounds/brrt_04.wav",
}

for _, s in ipairs(GAU_BRRT_SOUNDS) do util.PrecacheSound(s) end
util.PrecacheModel(BULLET_MODEL)

bombin_gau_store = bombin_gau_store or {
    last_idx           = 0,
    buffer_size        = 128,
    buffer             = {},
    active_projectiles = {},
}

if #bombin_gau_store.buffer == 0 then
    for i = 1, bombin_gau_store.buffer_size do
        bombin_gau_store.buffer[i] = {
            hit               = true,
            shooter           = NULL,
            pos               = Vector(0,0,0),
            old_pos           = Vector(0,0,0),
            vel               = Vector(0,0,0),
            old_vel           = Vector(0,0,0),
            dir               = Vector(0,0,0),
            speed             = 0,
            damage            = 0,
            distance_traveled = 0,
            firer_ent         = NULL,
            bullet_index      = 1,
            hei_interval      = HEI_INTERVAL,
            blast_radius      = BLAST_RADIUS,
        }
    end
end

local BREAKABLE = {
    ["func_breakable_surf"]      = true,
    ["func_breakable"]           = true,
    ["prop_physics"]             = true,
    ["prop_physics_multiplayer"] = true,
}

local function apply_damage(proj, tr, shooter)
    local hit_ent = tr.Entity
    if not IsValid(hit_ent) then return end
    local damage = proj.damage
    local fvec   = proj.dir * damage * FORCE_MUL
    if BREAKABLE[hit_ent:GetClass()] then
        shooter:FireBullets({
            Src       = tr.HitPos - proj.dir,
            Dir       = proj.dir,
            Damage    = damage,
            Force     = damage * FORCE_MUL,
            Distance  = 2,
            Num       = 1,
            Tracer    = 0,
            Inflictor = shooter,
        })
        return
    end
    local dmg = DamageInfo()
    dmg:SetDamage(damage)
    dmg:SetAttacker(shooter)
    dmg:SetInflictor(shooter)
    dmg:SetDamageType(DMG_BULLET)
    dmg:SetDamagePosition(tr.HitPos)
    dmg:SetDamageForce(fvec)
    hit_ent:TakeDamageInfo(dmg)
end

local function apply_impact_fx(proj, tr)
    local hitPos  = tr.HitPos
    local shooter = IsValid(proj.firer_ent) and proj.firer_ent or proj.shooter

    util.BlastDamage(shooter, shooter, hitPos + Vector(0,0,36), proj.blast_radius, proj.damage)

    local ed1 = EffectData()
    ed1:SetOrigin(hitPos) ed1:SetScale(1.5) ed1:SetMagnitude(1.5) ed1:SetRadius(40)
    util.Effect("gred_ground_impact", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(hitPos) ed2:SetScale(0.5) ed2:SetMagnitude(0.5) ed2:SetRadius(4)
    util.Effect("Sparks", ed2, true, true)

    net.Start("gred_net_createimpact")
        net.WriteVector(hitPos)
        net.WriteAngle(Angle(0,0,0))
        net.WriteUInt(0, 5)
        net.WriteUInt(GAU_CAL_ID, 4)
    net.Broadcast()

    sound.Play(table.Random(IMPACT_SOUNDS), hitPos, 75, math.random(95,105), 0.8)

    if proj.bullet_index % proj.hei_interval == 0 then
        if gred and gred.CreateShell then
            local firer = IsValid(proj.firer_ent) and proj.firer_ent or proj.shooter
            local shell = gred.CreateShell(
                hitPos + Vector(0,0,30), Angle(90,0,0),
                firer, {firer}, 20, "HE", 80, 0.1, nil, 60, nil, 0.005
            )
            if IsValid(shell) then
                shell.Armed = true shell.ShouldExplode = true
                if shell.Arm then shell:Arm() end
                local sp = shell:GetPhysicsObject()
                if IsValid(sp) then sp:EnableGravity(true) sp:SetVelocity(Vector(0,0,-8000)) end
            end
        end
    end
end

local tick_interval = engine.TickInterval()

local function move_projectile(proj)
    if proj.hit then return true end
    if proj.distance_traveled >= MAX_DIST then proj.hit = true return true end
    if proj.speed <= MIN_SPEED then proj.hit = true return true end

    local step    = proj.dir * (proj.speed * tick_interval)
    local new_pos = proj.pos + step
    local shooter = proj.shooter

    local tr = util.TraceLine({
        start  = proj.pos,
        endpos = new_pos,
        filter = IsValid(shooter) and { shooter } or nil,
        mask   = MASK_SHOT,
    })

    proj.old_vel = proj.vel
    proj.old_pos = proj.pos

    if tr.Hit and not tr.HitSky then
        proj.pos = tr.HitPos
        proj.hit = true
        if SERVER and IsValid(tr.Entity) and IsValid(shooter) then
            apply_damage(proj, tr, shooter)
        end
        apply_impact_fx(proj, tr)
        return true
    end

    proj.vel               = step
    proj.pos               = new_pos
    proj.distance_traveled = proj.distance_traveled + step:Length()
    return false
end

hook.Add("Tick", "bombin_gau_move_sv", function()
    local active = bombin_gau_store.active_projectiles
    local count  = #active
    local idx    = 1
    while idx <= count do
        if move_projectile(active[idx]) then
            active[idx] = active[count]
            active[count] = nil
            count = count - 1
        else
            idx = idx + 1
        end
    end
end)

if SERVER then
    util.AddNetworkString("bombin_gau_projectile")

    function bombin_gau_spawn(shooter, firer_ent, pos, dir, bullet_index, hei_interval, blast_radius, blast_damage)
        local store    = bombin_gau_store
        local proj_idx = bit.band(store.last_idx, store.buffer_size - 1) + 1
        local proj     = store.buffer[proj_idx]

        proj.hit               = false
        proj.shooter           = shooter
        proj.firer_ent         = firer_ent
        proj.pos               = Vector(pos.x, pos.y, pos.z)
        proj.old_pos           = Vector(pos.x, pos.y, pos.z)
        proj.dir               = Vector(dir.x, dir.y, dir.z)
        proj.speed             = MUZZLE_VEL
        proj.damage            = blast_damage or BLAST_DAMAGE
        proj.blast_radius      = blast_radius or BLAST_RADIUS
        proj.distance_traveled = 0
        proj.bullet_index      = bullet_index or 1
        proj.hei_interval      = hei_interval or HEI_INTERVAL
        proj.vel               = proj.dir * proj.speed
        proj.old_vel           = proj.dir * proj.speed

        store.last_idx = store.last_idx + 1
        store.active_projectiles[#store.active_projectiles + 1] = proj

        net.Start("bombin_gau_projectile")
            net.WriteVector(pos)
            net.WriteVector(dir)
        net.SendPVS(pos)
    end
end

function ENT:Initialize()
    self:SetModel(BULLET_MODEL)
    self:SetModelScale(3, 0)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)

    local pos = self:GetPos()
    local fwd = self:GetAngles():Forward()

    -- AC-130 GAU uses a burst loop sound played once per burst on the plane, not per bullet.
    -- No per-bullet sound here on purpose.

    bombin_gau_spawn(
        IsValid(self.Firer) and self.Firer or self,
        self.Firer,
        self.MuzzlePos or pos,
        fwd,
        self.BulletIndex or 1,
        self.HEIInterval or 90,
        self.BulletRad   or BLAST_RADIUS,
        self.BulletDmg   or BLAST_DAMAGE
    )

    self:Remove()
end
