include("shared.lua")

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local MUZZLE_VEL = 66000
local MAX_DIST   = 50000
local MIN_SPEED  = 200

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
            gau_wizz          = false,
        }
    end
end

-- ─── Passby logic ─────────────────────────────────────────────────────────────
-- GAUEmitSound and gau_passby_* aliases are in cl_gau_passby_sounds.lua.
-- Zero dependency on the RBO addon.
--
-- Crossing detection (corrected):
--   sign(old_pos) = dot( dir, normalize(listener - old_pos) )
--     > 0  →  listener is AHEAD  of bullet's old position  (bullet hasn't passed yet)
--     ≤ 0  →  listener is BEHIND of bullet's old position  (bullet already past)
--
--   We want a crossing event: old_pos had listener ahead (sign > 0),
--   and new pos has listener behind (sign ≤ 0).  That means the bullet
--   swept past the listener's lateral plane THIS tick.

local GAU_PASSBY_COOLDOWN     = 0.22
local GAU_MAX_CONSIDER_DISTSQ = 4000 * 4000

local gau_passby_last_time = -99

local function gau_passby_emit(distance, position)
    if distance < 256 then
        GAUEmitSound("gau_passby_50_close", position)
    elseif distance < 768 then
        if math.random(2) == 1 then
            GAUEmitSound("gau_passby_50_medium_2", position)
        else
            GAUEmitSound("gau_passby_50_medium", position)
        end
    elseif distance < 2500 then
        GAUEmitSound("gau_passby_hiss_far", position)
    else
        GAUEmitSound("gau_passby_50_far_2", position)
    end
end

-- Returns dot( dir, normalize(listener - bullet_pos) ).
-- Positive = listener is ahead of the bullet. Negative = bullet has passed.
local function lateral_sign(bullet_pos, listener_pos, dir)
    local d = listener_pos - bullet_pos
    d:Normalize()
    return dir:Dot(d)
end

local function gau_check_passby(proj)
    -- Skip first tick: old_pos == pos means no real segment yet.
    if proj.distance_traveled == 0 then return end

    local listener = LocalPlayer()
    if not IsValid(listener) then return end

    -- Suppress while riding the plane (view entity is not a player).
    local view_ent = GetViewEntity()
    if IsValid(view_ent) and not view_ent:IsPlayer() then return end

    local listen_pos = listener:EyePos()

    -- Broad-phase: cheap squared-distance cull on the segment midpoint.
    local mid_x = (proj.old_pos.x + proj.pos.x) * 0.5
    local mid_y = (proj.old_pos.y + proj.pos.y) * 0.5
    local mid_z = (proj.old_pos.z + proj.pos.z) * 0.5
    local dx = listen_pos.x - mid_x
    local dy = listen_pos.y - mid_y
    local dz = listen_pos.z - mid_z
    if (dx*dx + dy*dy + dz*dz) > GAU_MAX_CONSIDER_DISTSQ then return end

    local vn = proj.dir  -- already a unit vector; dir never changes per-projectile

    -- Crossing condition:
    --   last tick: listener was AHEAD  (sign_old > 0)
    --   this tick: listener is BEHIND  (sign_new ≤ 0)
    local sign_old = lateral_sign(proj.old_pos, listen_pos, vn)
    local sign_new = lateral_sign(proj.pos,     listen_pos, vn)

    if sign_old <= 0 then
        -- Listener was already behind old_pos — bullet spawned past us or we moved.
        -- Mark as done so we stop checking every tick.
        proj.gau_wizz = true
        return
    end

    if sign_new > 0 then
        -- Listener still ahead this tick — crossing hasn't happened yet.
        return
    end

    -- ── Crossing confirmed this tick ──────────────────────────────────────────
    proj.gau_wizz = true  -- only ever whizz once per bullet slot

    -- Global cooldown: hard cap on concurrent passby spam from burst fire.
    local now = UnPredictedCurTime()
    if (now - gau_passby_last_time) < GAU_PASSBY_COOLDOWN then return end
    gau_passby_last_time = now

    -- Closest-approach distance + world position along the old→new segment.
    local dist, closest_pos = util.DistanceToLine(proj.old_pos, proj.pos, listen_pos)
    gau_passby_emit(dist, closest_pos)
end

-- ─── Net receive ──────────────────────────────────────────────────────────────

net.Receive("bombin_gau_projectile", function()
    local pos = net.ReadVector()
    local dir = net.ReadVector()
    dir:Normalize()

    local store    = bombin_gau_store
    local proj_idx = bit.band(store.last_idx, store.buffer_size - 1) + 1
    local proj     = store.buffer[proj_idx]

    proj.hit               = false
    proj.shooter           = NULL
    proj.pos               = Vector(pos.x, pos.y, pos.z)
    proj.old_pos           = Vector(pos.x, pos.y, pos.z)
    proj.dir               = Vector(dir.x, dir.y, dir.z)
    proj.speed             = MUZZLE_VEL
    proj.damage            = 0
    proj.distance_traveled = 0
    proj.vel               = proj.dir * proj.speed
    proj.old_vel           = proj.dir * proj.speed
    proj.gau_wizz          = false

    store.last_idx = store.last_idx + 1
    store.active_projectiles[#store.active_projectiles + 1] = proj
end)

-- ─── Movement + passby tick ───────────────────────────────────────────────────

local tick_interval = engine.TickInterval()
local last_tick     = engine.TickCount()

local function move_cl()
    local active = bombin_gau_store.active_projectiles
    local count  = #active
    local idx    = 1
    while idx <= count do
        local proj = active[idx]
        if proj.hit or proj.distance_traveled >= MAX_DIST or proj.speed <= MIN_SPEED then
            active[idx] = active[count]
            active[count] = nil
            count = count - 1
        else
            local step    = proj.dir * (proj.speed * tick_interval)
            local new_pos = proj.pos + step
            proj.old_vel  = proj.vel
            proj.old_pos  = proj.pos
            proj.vel      = step
            proj.pos      = new_pos
            proj.distance_traveled = proj.distance_traveled + step:Length()

            -- Passby check runs after pos/old_pos are updated for this tick.
            -- gau_wizz short-circuits after first confirmed crossing.
            if not proj.gau_wizz then
                gau_check_passby(proj)
            end

            idx = idx + 1
        end
    end
end

hook.Add("CreateMove", "bombin_gau_move_cl", function()
    local t = engine.TickCount()
    if t > last_tick then
        last_tick = t
        move_cl()
    end
end)

-- ─── Renderer ─────────────────────────────────────────────────────────────────

local function render_projectiles()
    local active = bombin_gau_store.active_projectiles
    local count  = #active
    if count == 0 then return end

    local cam_pos      = EyePos()
    local real_time    = UnPredictedCurTime()
    local cur_ticktime = engine.TickCount() * tick_interval
    local interp_frac  = math.Clamp((real_time - cur_ticktime) / tick_interval, 0, 2)
    local min_trail    = 120

    for i = 1, count do
        local p = active[i]
        if p.hit then continue end

        local render_pos = p.pos
        if interp_frac <= 1.0 then
            local t  = interp_frac
            local t2 = t * t
            local t3 = t2 * t
            local h1 =  2*t3 - 3*t2 + 1
            local h2 = -2*t3 + 3*t2
            local h3 =  t3 - 2*t2 + t
            local h4 =  t3 - t2
            render_pos = p.old_pos * h1 + p.pos * h2
                       + (p.old_vel or p.vel) * (h3 * tick_interval)
                       + p.vel               * (h4 * tick_interval)
        end

        local tail_end = p.old_pos or render_pos
        if p.vel then
            local vls = p.vel:LengthSqr()
            if vls > 1 then
                local trail_vec = render_pos - tail_end
                if trail_vec:LengthSqr() < min_trail * min_trail then
                    tail_end = render_pos - p.vel * (1.0 / math.sqrt(vls)) * min_trail
                end
            end
        end

        local dist  = math.sqrt(cam_pos:DistToSqr(render_pos))
        local scale = math.Clamp(dist / 1200, 1.5, 6)

        render.SetMaterial(mat_beam)
        if render_pos:DistToSqr(tail_end) > 4 then
            render.DrawBeam(tail_end, render_pos, 8 * scale, 0, 1, Color(255, 240, 180, 255))
        end
        render.DrawBeam(tail_end, render_pos, 22 * scale, 0, 1, Color(255, 120, 0, 120))

        render.SetMaterial(mat_glow)
        render.DrawSprite(render_pos, 80 * scale, 80 * scale, Color(255, 160, 20, 200))
        render.DrawSprite(render_pos, 20 * scale, 20 * scale, Color(255, 255, 200, 255))
    end
end

hook.Add("PostDrawTranslucentRenderables", "bombin_gau_render", function(depth, skybox)
    if depth or skybox then return end
    render_projectiles()
end)

function ENT:Draw() end
