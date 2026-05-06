include("shared.lua")

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local MUZZLE_VEL = 85000
local MAX_DIST   = 22000
local MIN_SPEED  = 200

-- Impact sounds also travel-delayed with the same exaggerated constant
-- so the dirt kick and spark are seen before the crack.
local GAU_SOUND_SPEED = 8000

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

bombin_gau_store = bombin_gau_store or {
    last_idx           = 0,
    buffer_size        = 128,
    buffer             = {},
    active_projectiles = {},
    -- pending_impact_sounds: queue of { pos, time } waiting to play
    pending_sounds     = {},
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
        }
    end
end

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

    store.last_idx = store.last_idx + 1
    store.active_projectiles[#store.active_projectiles + 1] = proj
end)

local tick_interval = engine.TickInterval()
local last_tick     = engine.TickCount()

local function move_cl()
    local store  = bombin_gau_store
    local active = store.active_projectiles
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

            -- Client-side impact detection for sound scheduling.
            -- We trace and queue the impact sound with travel delay so the
            -- dirt/spark FX (which play instantly via the server net effect)
            -- are seen before the crack arrives.
            local tr = util.TraceLine({
                start  = proj.pos,
                endpos = new_pos,
                mask   = MASK_SHOT,
            })

            if tr.Hit and not tr.HitSky then
                proj.hit = true
                local hitPos   = tr.HitPos
                local dist     = EyePos():Distance(hitPos)
                local delay    = dist / GAU_SOUND_SPEED
                local snd      = IMPACT_SOUNDS[math.random(#IMPACT_SOUNDS)]
                local playAt   = UnPredictedCurTime() + delay
                local ps       = store.pending_sounds
                ps[#ps + 1]    = { snd = snd, pos = hitPos, playAt = playAt }
            else
                proj.old_vel  = proj.vel
                proj.old_pos  = proj.pos
                proj.vel      = step
                proj.pos      = new_pos
                proj.distance_traveled = proj.distance_traveled + step:Length()
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

-- Drain the pending sound queue each frame
hook.Add("Think", "bombin_gau_impact_sounds", function()
    local ps  = bombin_gau_store.pending_sounds
    local now = UnPredictedCurTime()
    local i   = 1
    while i <= #ps do
        local e = ps[i]
        if now >= e.playAt then
            sound.Play(e.snd, e.pos, 75, math.random(95, 105), 0.8)
            ps[i] = ps[#ps]
            ps[#ps] = nil
        else
            i = i + 1
        end
    end
end)

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
