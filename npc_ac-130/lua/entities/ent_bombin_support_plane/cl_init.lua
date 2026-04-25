include("shared.lua")

-- sound.Play requires paths relative to the game root (i.e. prefixed with "sound/").
-- All paths sent over the net are stored without that prefix, so we add it here.
net.Receive("bombin_plane_sound", function()
    local path   = net.ReadString()
    local pos    = net.ReadVector()
    local level  = net.ReadUInt(8)
    local pitch  = net.ReadUInt(8)
    local volume = net.ReadFloat()
    sound.Play("sound/" .. path, pos, level, pitch, volume)
end)
