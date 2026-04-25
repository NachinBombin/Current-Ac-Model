AddCSLuaFile()

-- SERVER: full physics + damage
-- CLIENT: position update only (for renderer interpolation)

local SERVER           = SERVER
local CLIENT           = CLIENT
local NULL             = NULL
local IsValid          = IsValid
local DamageInfo       = DamageInfo
local DMG_BULLET       = DMG_BULLET
local EffectData       = EffectData
local util_Effect      = util.Effect
local util_TraceLine   = util.TraceLine
local engine_TickInterval = engine.TickInterval
local tick_interval    = engine.TickInterval()
local math_min         = math.min
local Vector           = Vector

local entity_meta           = FindMetaTable("Entity")
local dispatch_trace_attack = entity_meta.DispatchTraceAttack
local take_damage_info      = entity_meta.TakeDamageInfo
local get_class             = entity_meta.GetClass

local dmginfo_meta       = FindMetaTable("CTakeDamageInfo")
local dmg_SetDamage      = dmginfo_meta.SetDamage
local dmg_SetAttacker    = dmginfo_meta.SetAttacker
local dmg_SetInflictor   = dmginfo_meta.SetInflictor
local dmg_SetDamageType  = dmginfo_meta.SetDamageType
local dmg_SetDamagePos   = dmginfo_meta.SetDamagePosition
local dmg_SetDamageForce = dmginfo_meta.SetDamageForce

local effdata_meta   = FindMetaTable("CEffectData")
local eff_SetOrigin  = effdata_meta.SetOrigin
local eff_SetStart   = effdata_meta.SetStart
local eff_SetSurf    = effdata_meta.SetSurfaceProp
local eff_SetEnt     = effdata_meta.SetEntity
local eff_SetDmgType = effdata_meta.SetDamageType
local eff_SetHitBox  = effdata_meta.SetHitBox

-- Entities that need FireBullets for breakable physics (glass, func_breakable)
local BREAKABLE = {
    ["func_breakable_surf"] = true,
    ["func_breakable"]      = true,
    ["prop_physics"]        = true,
    ["prop_physics_multiplayer"] = true,
}

local function apply_impact_fx(tr)
    local ed = EffectData()
    eff_SetOrigin(ed,  tr.HitPos)
    eff_SetStart(ed,   tr.StartPos)
    eff_SetSurf(ed,    tr.SurfaceProps)
    eff_SetEnt(ed,     tr.Entity)
    eff_SetHitBox(ed,  tr.HitBoxBone or 0)
    eff_SetDmgType(ed, DMG_BULLET)
    util_Effect("Impact", ed)
    -- Play the surface-appropriate bullet impact sound.
    -- util.Effect("ImpactSound") reads SurfaceProp and plays the correct sound
    -- exactly as the engine would for a native hitscan bullet.
    util_Effect("ImpactSound", ed)
end

local function apply_damage(proj, tr, shooter)
    local hit_ent   = tr.Entity
    local damage    = proj.damage
    local force_vec = proj.dir * damage * TRAJ_GAU.damage_force_mul

    -- DispatchTraceAttack gives correct hitgroup multipliers and NPC reactions
    -- It works for players, NPCs and most SWEPs
    if hit_ent:IsPlayer() or hit_ent:IsNPC() then
        dispatch_trace_attack(shooter, tr, damage, force_vec)
        return
    end

    -- Breakables need FireBullets for the engine to splinter them
    if BREAKABLE[get_class(hit_ent)] then
        -- Temporarily disable our own hook so we don't recurse
        traj_gau_disable_hook = true
        shooter:FireBullets({
            Src       = tr.HitPos - proj.dir,
            Dir       = proj.dir,
            Damage    = damage,
            Force     = damage * TRAJ_GAU.damage_force_mul,
            Distance  = 2,
            Num       = 1,
            Tracer    = 0,
            Inflictor = shooter,
        })
        traj_gau_disable_hook = false
        return
    end

    -- Everything else: generic DamageInfo
    local dmg = DamageInfo()
    dmg_SetDamage(dmg,      damage)
    dmg_SetAttacker(dmg,    shooter)
    dmg_SetInflictor(dmg,   shooter)
    dmg_SetDamageType(dmg,  DMG_BULLET)
    dmg_SetDamagePos(dmg,   tr.HitPos)
    dmg_SetDamageForce(dmg, force_vec)
    take_damage_info(hit_ent, dmg)
end

local function move_projectile(proj)
    if proj.hit then return true end
    if proj.distance_traveled >= TRAJ_GAU.max_distance then
        proj.hit = true
        return true
    end
    if proj.speed <= TRAJ_GAU.min_speed then
        proj.hit = true
        return true
    end

    local step     = proj.dir * (proj.speed * tick_interval)
    local new_pos  = proj.pos + step
    local shooter  = proj.shooter

    local tr = util_TraceLine({
        start  = proj.pos,
        endpos = new_pos,
        filter = IsValid(shooter) and { shooter } or nil,
    })

    -- Client: only update position for renderer, no damage
    if CLIENT then
        proj.old_vel = proj.vel
        proj.old_pos = proj.pos
        if tr.Hit then
            proj.pos = tr.HitPos
            proj.hit = true
            apply_impact_fx(tr)
        else
            proj.vel = step
            proj.pos = new_pos
            proj.distance_traveled = proj.distance_traveled + step:Length()
        end
        return proj.hit
    end

    -- SERVER
    proj.old_vel = proj.vel
    proj.old_pos = proj.pos

    if tr.Hit then
        local hit_ent = tr.Entity

        proj.pos = tr.HitPos
        proj.hit = true

        if IsValid(hit_ent) and IsValid(shooter) then
            apply_damage(proj, tr, shooter)
        end

        return true
    end

    proj.vel               = step
    proj.pos               = new_pos
    proj.distance_traveled = proj.distance_traveled + step:Length()
    return false
end

local function tick_all()
    local active = traj_gau_store.active_projectiles
    local count  = #active
    local idx    = 1

    while idx <= count do
        local done = move_projectile(active[idx])
        if done then
            active[idx] = active[count]
            active[count] = nil
            count = count - 1
        else
            idx = idx + 1
        end
    end
end

if SERVER then
    hook.Add("Tick", "traj_gau_move", tick_all)
end

if CLIENT then
    -- Clients step projectiles on CreateMove for smooth interp
    local last_tick    = engine.TickCount()
    local engine_Tick  = engine.TickCount

    hook.Add("CreateMove", "traj_gau_move_cl", function(cmd)
        local t = engine_Tick()
        if t > last_tick then
            last_tick = t
            tick_all()
        end
    end)
end

print("[TrajGAU] move loaded.")
