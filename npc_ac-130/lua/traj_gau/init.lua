-- TrajGAU: Dedicated TrajSim for AC-130 GAU only.
-- Load order matters.

AddCSLuaFile("traj_gau/constants.lua")
AddCSLuaFile("traj_gau/net.lua")
AddCSLuaFile("traj_gau/firebullets.lua")
AddCSLuaFile("traj_gau/move.lua")
AddCSLuaFile("traj_gau/render.lua")

include("traj_gau/constants.lua")
include("traj_gau/net.lua")
include("traj_gau/firebullets.lua")
include("traj_gau/move.lua")
include("traj_gau/render.lua")

print("[TrajGAU] fully loaded.")
