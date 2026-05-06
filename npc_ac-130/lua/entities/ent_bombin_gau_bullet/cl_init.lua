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
            -- passby state: one flag per slot so a bullet only whizzes once
            gau_wizz          = false,
        }
    end
end

-- ─── RBO Passby Integration ───────────────────────────────────────────────────
--
-- The GAU-8 fires 30mm at ~3,900 RPM (~65 rds/sec). Triggering a passby sound
-- for every bullet that crosses the listener would be deafening and would spike
-- the audio channel. We address this with two layers of throttling:
--
--   1. Per-projectile `gau_wizz` flag  – each slot whizzes at most once.
--   2. Global sound cooldown           – hard cap of GAU_PASSBY_COOLDOWN seconds
--      between any two GAU passby sounds regardless of bullet volume.
--
-- Sound selection mirrors RBO's Play50Cal (supports.lua) since 30mm is
-- ballistically similar to .50 BMG territory; all aliases are already
-- registered by rbo/sounds.lua on the client.
--
-- Geometry is identical to ENT:Whiz() in rbo_bullet/cl_init.lua:
--   sign check on old_pos → pos crossing the listener's lateral plane,
--   then util.DistanceToLine for closest-approach distance + position.
-- ─────────────────────────────────────────────────────────────────────────────

local GAU_PASSBY_COOLDOWN    = 0.22  -- minimum seconds between any two passby sounds
local GAU_MAX_CONSIDER_DIST  = 4000  -- ignore bullets whose midpoint is farther than this (units)
local GAU_MAX_CONSIDER_DISTSQ = GAU_MAX_CONSIDER_DIST * GAU_MAX_CONSIDER_DIST

local gau_passby_last_time = -99  -- tracks last time a passby sound fired

local function gau_passby_emit(distance, position)
    -- Re-use RBOEmitSound if RBO is loaded, otherwise fall back to sound.Play.
    -- RBOEmitSound plays at the listener's eye with a direction offset so it
    -- always sounds spatial regardless of Source engine distance limits.
    if RBOEmitSound then
        if distance < 256 then
            RBOEmitSound("rbo_passby_50_close", position)
        elseif distance < 768 then
            if math.random(2) == 1 then
                RBOEmitSound("rbo_passby_50_medium_2", position)
            else
                RBOEmitSound("rbo_passby_50_medium", position)
            end
        elseif distance < 2500 then
            RBOEmitSound("rbo_passby_hiss_far", position)
        else
            RBOEmitSound("rbo_passby_50_far_2", position)
        end
    else
        -- Fallback: direct sound.Play at closest-approach position.
        -- Less accurate spatially but always works without RBO present.
        local snd
        if distance < 256 then
            snd = "rbo/passbys/squad/50cal/crack_50cal_close_01.ogg"
        elseif distance < 768 then
            snd = "rbo/passbys/squad/50cal/crack_50cal_mid_01.ogg"
        elseif distance < 2500 then
            snd = "rbo/passbys/squad/hiss/passby_crack_hiss_far_01.ogg"
        else
            snd = "rbo/passbys/squad/50cal/crack_50cal_far_new_01.ogg"
        end
        sound.Play(snd, position, 80, 100, 1)
    end
end

-- Returns the dot product of (p2-p1):Normalized() against dir.
-- Positive → listener is ahead of bullet, negative → bullet has passed.
local function sign_check(p1, p2, dir)
    local dif = p2 - p1
    dif:Normalize()
    return dir:Dot(dif)
end

local function gau_check_passby(proj)
    -- Already whizzed, or RBO sounds aren't registered yet → skip.
    if proj.gau_wizz then return end

    local listener = LocalPlayer()
    if not IsValid(listener) then return end

    -- Never play for the shooter (you are the gun).
    -- proj.shooter is NULL on the client (not networked), so we compare
    -- against the local player's vehicle or the player themselves.
    local view_ent = GetViewEntity()
    -- If we're riding the plane entity that fired this, skip.
    -- We detect this by checking if the view entity is parented to or IS
    -- the plane — a conservative check: if the view entity is not the
    -- local player itself and is not a player, assume we're aboard the plane
    -- and suppress. Adjust this check if spectating is a concern.
    if IsValid(view_ent) and not view_ent:IsPlayer() then return end

    local listen_pos = listener:EyePos()

    -- Cheap broad-phase: skip if listener is too far from the bullet's midpoint.
    local mid_x = (proj.old_pos.x + proj.pos.x) * 0.5
    local mid_y = (proj.old_pos.y + proj.pos.y) * 0.5
    local mid_z = (proj.old_pos.z + proj.pos.z) * 0.5
    local dx = listen_pos.x - mid_x
    local dy = listen_pos.y - mid_y
    local dz = listen_pos.z - mid_z
    if (dx*dx + dy*dy + dz*dz) > GAU_MAX_CONSIDER_DISTSQ then return end

    -- Sign check: did the bullet's travel segment cross the listener's lateral plane?
    -- sign > 0  → listener is still ahead (bullet hasn't reached us yet)
    -- sign ≤ 0  → bullet has passed (or is exactly at our plane)
    local vn = proj.vel:GetNormalized()

    if sign_check(proj.old_pos, listen_pos, vn) > 0 then
        -- Listener still ahead of bullet this tick — update old_pos and wait.
        -- (old_pos is updated by move_cl already; nothing extra needed here.)
        return
    end

    -- The bullet's segment old_pos→pos just crossed our lateral plane.
    -- Check that old_pos was still behind us (sign was positive last tick).
    if sign_check(proj.pos, listen_pos, vn) > 0 then
        -- Bullet passed fully through in one tick — crossing confirmed.
        -- fall through to distance check
    else
        -- Both endpoints are behind the listener → already passed, bail.
        proj.gau_wizz = true
        return
    end

    -- Closest-approach distance and position via DistanceToLine.
    local dist, closest_pos = util.DistanceToLine(proj.old_pos, proj.pos, listen_pos)

    proj.gau_wizz = true  -- mark regardless; only play if within cooldown budget

    -- Global cooldown gate — prevents sound spam from simultaneous bullets.
    local now = UnPredictedCurTime()
    if (now - gau_passby_last_time) < GAU_PASSBY_COOLDOWN then return end
    gau_passby_last_time = now

    gau_passby_emit(dist, closest_pos)
end

-- ─── Net receive ─────────────────────────────────────────────────────────────

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
    proj.gau_wizz          = false  -- reset passby flag for reused slot

    store.last_idx = store.last_idx + 1
    store.active_projectiles[#store.active_projectiles + 1] = proj
end)

-- ─── Movement + passby tick ──────────────────────────────────────────────────

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

            -- Passby check runs after position update so old_pos/pos bracket
            -- the just-completed step. gau_wizz short-circuits after first hit.
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

-- ─── Renderer ────────────────────────────────────────────────────────────────

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
