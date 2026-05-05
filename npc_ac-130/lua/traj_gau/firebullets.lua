AddCSLuaFile()

-- The EntityFireBullets hook is NOT used by the AC-130 (traj_gau_broadcast is
-- called directly from FireGAUBulletAt in init.lua). Hook disabled to avoid
-- interfering with other addons.
traj_gau_disable_hook = true

print("[TrajGAU] firebullets loaded.")
