AddCSLuaFile()

if SERVER then
    util.AddNetworkString("traj_gau_projectile")
end

local Vector       = Vector
local bit_band     = bit.band
local NULL         = NULL

traj_gau_store = traj_gau_store or {}

local function create_store()
    local store = {
        last_idx           = 0,
        buffer_size        = TRAJ_GAU.buffer_size,
        buffer             = {},
        active_projectiles = {},
    }
    for i = 1, store.buffer_size do
        store.buffer[i] = {
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
            last_hit_entity   = NULL,
        }
    end
    return store
end

traj_gau_store = create_store()

if SERVER then
    function traj_gau_broadcast(shooter, pos, dir)
        local store    = traj_gau_store
        local proj_idx = bit_band(store.last_idx, store.buffer_size - 1) + 1
        local proj     = store.buffer[proj_idx]

        proj.hit               = false
        proj.shooter           = shooter
        proj.pos               = Vector(pos.x, pos.y, pos.z)
        proj.old_pos           = Vector(pos.x, pos.y, pos.z)
        proj.dir               = Vector(dir.x, dir.y, dir.z)
        proj.speed             = TRAJ_GAU.speed
        proj.damage            = TRAJ_GAU.damage
        proj.distance_traveled = 0
        proj.last_hit_entity   = NULL
        proj.vel               = proj.dir * proj.speed
        proj.old_vel           = proj.dir * proj.speed

        store.last_idx = store.last_idx + 1
        store.active_projectiles[#store.active_projectiles + 1] = proj

        -- Broadcast to clients for tracer rendering
        net.Start("traj_gau_projectile")
        net.WriteVector(pos)
        net.WriteVector(dir)
        net.SendPVS(pos)
    end
end

if CLIENT then
    net.Receive("traj_gau_projectile", function()
        local pos = net.ReadVector()
        local dir = net.ReadVector()

        local store    = traj_gau_store
        local proj_idx = bit_band(store.last_idx, store.buffer_size - 1) + 1
        local proj     = store.buffer[proj_idx]

        proj.hit               = false
        proj.shooter           = NULL
        proj.pos               = Vector(pos.x, pos.y, pos.z)
        proj.old_pos           = Vector(pos.x, pos.y, pos.z)
        proj.dir               = Vector(dir.x, dir.y, dir.z)
        proj.speed             = TRAJ_GAU.speed
        proj.damage            = TRAJ_GAU.damage
        proj.distance_traveled = 0
        proj.last_hit_entity   = NULL
        proj.vel               = proj.dir * proj.speed
        proj.old_vel           = proj.dir * proj.speed

        store.last_idx = store.last_idx + 1
        store.active_projectiles[#store.active_projectiles + 1] = proj
    end)
end

print("[TrajGAU] net loaded.")
