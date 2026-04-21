AddCSLuaFile()

traj_gau_disable_hook = traj_gau_disable_hook or false

if SERVER then
    hook.Add("EntityFireBullets", "traj_gau_intercept", function(shooter, data)
        if traj_gau_disable_hook then return end

        local inflictor = data.Inflictor
        if not IsValid(inflictor) then return end
        if inflictor:GetClass() ~= "ent_bombin_support_plane" then return end

        traj_gau_broadcast(shooter, data.Src, data.Dir:GetNormalized())
        return false
    end)
end

print("[TrajGAU] firebullets loaded.")
