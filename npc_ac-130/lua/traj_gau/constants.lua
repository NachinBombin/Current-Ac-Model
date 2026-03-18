AddCSLuaFile()

TRAJ_GAU = {
    -- Ballistics
    damage             = 35,
    speed              = 85000,
    penetration_power  = 15.0,
    penetration_count  = 3,
    drag               = 0.0,
    mass               = 0.02,
    drop               = 0.0,
    min_speed          = 200,
    max_distance       = 22000,
    damage_force_mul   = 5.0,

    -- Tracers
    tracer_core  = Color(255, 100,  0, 255),
    tracer_glow  = Color(255, 200, 80, 120),

    -- Rendering
    render_enabled     = true,
    min_trail_length   = 8,
    distance_scale_max = 2.0,

    -- Net
    net_reliable = false,
    buffer_size  = 128,
}

print("[TrajGAU] constants loaded.")
