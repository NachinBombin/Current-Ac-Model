include("shared.lua")

-- Receive gunfire / pass sound broadcast from server and play locally
net.Receive("bombin_plane_sound", function()
    local path   = net.ReadString()
    local pos    = net.ReadVector()
    local level  = net.ReadUInt(8)
    local pitch  = net.ReadUInt(8)
    local volume = net.ReadFloat()
    sound.Play(path, pos, level, pitch, volume)
end)