AddCSLuaFile()

if SERVER then return end

local render_SetMaterial  = render.SetMaterial
local render_DrawBeam     = render.DrawBeam
local render_DrawSprite   = render.DrawSprite
local UnpredictedCurTime  = UnPredictedCurTime
local engine_TickCount    = engine.TickCount
local sqrt                = math.sqrt
local clamp               = math.Clamp
local EyePos              = EyePos
local tick_interval       = engine.TickInterval()

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local vector_meta = FindMetaTable("Vector")
local DistToSqr   = vector_meta.DistToSqr
local LengthSqr   = vector_meta.LengthSqr

local function render_projectiles()
    if not TRAJ_GAU.render_enabled then return end

    local active = traj_gau_store.active_projectiles
    local count  = #active
    if count == 0 then return end

    local cam_pos      = EyePos()
    local real_time    = UnpredictedCurTime()
    local cur_ticktime = engine_TickCount() * tick_interval
    local interp_frac  = clamp((real_time - cur_ticktime) / tick_interval, 0, 2)
    local min_trail    = TRAJ_GAU.min_trail_length

    for i = 1, count do
        local p = active[i]
        if p.hit then continue end

        -- Hermite sub-tick interpolation
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

        -- Enforce minimum trail length
        local tail_end = p.old_pos or render_pos
        if min_trail > 0 and p.vel then
            local vls = LengthSqr(p.vel)
            if vls > 1 then
                if LengthSqr(render_pos - tail_end) < min_trail * min_trail then
                    tail_end = render_pos - p.vel * (1.0 / sqrt(vls)) * min_trail
                end
            end
        end

        local dist  = sqrt(DistToSqr(cam_pos, render_pos))
        local scale = clamp(dist / 1200, 1.5, TRAJ_GAU.distance_scale_max)

        -- Hot white-orange core beam
        render_SetMaterial(mat_beam)
        if DistToSqr(render_pos, tail_end) > 4 then
            render_DrawBeam(tail_end, render_pos, 8 * scale, 0, 1, Color(255, 240, 180, 255))
        end

        -- Wide outer orange glow beam
        render_DrawBeam(tail_end, render_pos, 22 * scale, 0, 1, Color(255, 120, 0, 120))

        -- Large halo + hot core sprite at tip
        render_SetMaterial(mat_glow)
        render_DrawSprite(render_pos, 80 * scale, 80 * scale, Color(255, 160, 20, 200))
        render_DrawSprite(render_pos, 20 * scale, 20 * scale, Color(255, 255, 200, 255))
    end
end

hook.Add("PostDrawTranslucentRenderables", "traj_gau_render", function(depth, skybox)
    if depth or skybox then return end
    render_projectiles()
end)

print("[TrajGAU] render loaded.")
