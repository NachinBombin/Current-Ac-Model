-- ============================================================
--  NPC Support Plane — Manual Spawn Handler
--  lua/autorun/server/sv_bombinplane_manualspawn.lua
-- ============================================================

if not SERVER then return end

util.AddNetworkString("BombinSupportPlane_ManualSpawn")

net.Receive("BombinSupportPlane_ManualSpawn", function(len, ply)
    if not IsValid(ply) then return end

    -- Trace from player eyepos along look direction to find spawn center
    local tr = util.TraceLine({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 3000,
        filter = ply,
    })

    local centerPos = tr.Hit and tr.HitPos or (ply:GetPos() + Vector(0, 0, 100))
    local callDir   = ply:EyeAngles():Forward()
    callDir.z = 0
    if callDir:LengthSqr() <= 1 then callDir = Vector(1, 0, 0) end
    callDir:Normalize()

    -- Guard: entity must be registered
    if not scripted_ents.GetStored("ent_bombin_support_plane") then
        ply:PrintMessage(HUD_PRINTCENTER, "[Support Plane] Entity not registered!")
        return
    end

    local ent = ents.Create("ent_bombin_support_plane")
    if not IsValid(ent) then
        ply:PrintMessage(HUD_PRINTCENTER, "[Support Plane] Spawn failed!")
        return
    end

    ent:SetPos(centerPos)
    ent:SetAngles(callDir:Angle())

    -- Pass ConVar values into the entity at spawn time
    ent:SetVar("CenterPos",  centerPos)
    ent:SetVar("CallDir",    callDir)
    ent:SetVar("Lifetime",   GetConVar("npc_bombinplane_lifetime"):GetFloat())
    ent:SetVar("Speed",      GetConVar("npc_bombinplane_speed"):GetFloat())
    ent:SetVar("OrbitRadius",GetConVar("npc_bombinplane_radius"):GetFloat())
    ent:SetVar("Height",     GetConVar("npc_bombinplane_height"):GetFloat())

    ent:Spawn()
    ent:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[AC-130U] Inbound!")
end)
