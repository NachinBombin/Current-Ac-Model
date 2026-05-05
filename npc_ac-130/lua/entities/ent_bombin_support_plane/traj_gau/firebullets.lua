AddCSLuaFile()

-- firebullets.lua is kept for compatibility but the EntityFireBullets hook is
-- not used by the AC-130 (it calls traj_gau_broadcast directly). The hook is
-- disabled by default to avoid interfering with other addons.
traj_gau_disable_hook = true

print("[TrajGAU] firebullets loaded.")
