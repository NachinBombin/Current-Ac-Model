AddCSLuaFile()

if SERVER then return end

local render_SetMaterial = render.SetMaterial
local render_DrawBeam    = render.DrawBeam
local render_DrawSprite  = render.DrawSprite
local UnpredictedCurTime = UnPredictedCurTime
local engine_TickInterval = engine.TickInterval()
local engine_TickCount   = engine.TickCount
local sqrt               = math.sqrt
local clamp              = math.Clamp
local EyePos             = EyePos

local mat_beam = Material("effects/laser1")
local mat_glow = Material("sprites/light_glow02_add")

local vector_meta    = FindMetaTable("Vector")
local DistToSqr      = vector_meta.DistToSqr
local LengthSqr      = vector_meta.LengthSqr
local Length         = vector_meta.Length

local tick_interval  = engine.TickInterval()

local function render_projectiles()
    if not TRAJ_GAU.render_enabled then return end

    local active        = traj_gau_store.active_projectiles
    local count         = #active
    if count == 0 then return end

    local cam_pos       = EyePos()
    local real_time     = UnpredictedCurTime()
    local cur_tick_time = engine_TickCount() * tick_interval
    local interp_frac   = clamp((real_time - cur_tick_time) / tick_interval, 0, 2)

    local min_trail = TRAJ_GAU.min_trail_length

    for i = 1, count do
        local p = active[i]
        if p.hit then continue end

        -- Hermite interpolation between old_pos and pos
        local render_pos = p.pos
        if interp_frac <= 1.0 then
            local t  = interp_frac
            local t2 = t * t
            local t3 = t2 * t
            local h1 = 2*t3 - 3*t2 + 1
            local h2 = -2*t3 + 3*t2
            local h3 = t3 - 2*t2 + t
            local h4 = t3 - t2
            render_pos = p.old_pos * h1 + p.pos * h2
                       + (p.old_vel or p.vel) * (h3 * tick_interval)
                       + p.vel               * (h4 * tick_interval)
        end

        -- Tail
        local tail_end = p.old_pos or render_pos
        -- enforce minimum trail length
        if min_trail > 0 and p.vel then
            local trail = render_pos - tail_end
            if LengthSqr(trail) < min_trail * min_trail then
                local vls = LengthSqr(p.vel)
                if vls > 1 then
                    tail_end = render_pos - p.vel * (1.0 / sqrt(vls)) * min_trail
                end
            end
        end

        -- Draw beam tail
        local dist = sqrt(DistToSqr(cam_pos, render_pos))
        local scale = clamp(dist / 3000, 1, TRAJ_GAU.distance_scale_max)
        local beam_w = 1.5 * scale

        render_SetMaterial(mat_beam)
        if DistToSqr(render_pos, tail_end) > 4 then
            render_DrawBeam(tail_end, render_pos, beam_w, 0, 1, TRAJ_GAU.tracer_glow)
        end

        -- Draw glow sprite at head
        local sprite_size = 6 * scale
        render_SetMaterial(mat_glow)
        render_DrawSprite(render_pos, sprite_size, sprite_size, TRAJ_GAU.tracer_core)
    end
end

hook.Add("PostDrawTranslucentRenderables", "traj_gau_render", function(depth, skybox)
    if depth or skybox then return end
    render_projectiles()
end)

print("[TrajGAU] render loaded.")
