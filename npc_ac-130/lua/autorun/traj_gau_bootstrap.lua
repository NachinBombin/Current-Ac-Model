-- Bootstraps the traj_gau tracer system for the AC-130 GAU.
-- Must run on both server and client so render.lua and net.lua are active.

if SERVER then
    AddCSLuaFile("traj_gau/constants.lua")
    AddCSLuaFile("traj_gau/net.lua")
    AddCSLuaFile("traj_gau/firebullets.lua")
    AddCSLuaFile("traj_gau/move.lua")
    AddCSLuaFile("traj_gau/render.lua")
end

include("traj_gau/constants.lua")
include("traj_gau/net.lua")
include("traj_gau/firebullets.lua")

if SERVER then
    include("traj_gau/move.lua")
end

if CLIENT then
    include("traj_gau/render.lua")
end

print("[TrajGAU] bootstrap complete.")
