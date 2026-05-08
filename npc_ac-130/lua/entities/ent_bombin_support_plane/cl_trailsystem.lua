-- ============================================================
-- TRAIL SYSTEM  --  ent_bombin_support_plane (AC-130)
-- Always active from spawn. All emission points run at all times.
-- Tier drives color + size: white vapor -> dense black smoke.
-- Unique hook/function names to avoid collision with heli & an-71.
-- ============================================================
-- Source Engine local-space axes for an aircraft entity:
--   X = forward  (nose -> tail is negative X)
--   Y = right    (starboard is positive Y, port is negative Y)
--   Z = up
--
-- Three emitters:
--   [1] Left  wingtip : large -Y offset, slightly behind wing centre
--   [2] Right wingtip : large +Y offset, slightly behind wing centre
--   [3] Fuselage body : centre-line, trailing near the tail
-- ============================================================

local TRAIL_MATERIAL = Material( "trails/smoke" )

local SAMPLE_RATE = 0.025  -- seconds between samples (40fps)

local TRAIL_POSITIONS = {
    Vector( -30, -280, -6 ),   -- left  wingtip  (far -Y)
    Vector( -30,  280, -6 ),   -- right wingtip  (far +Y)
    Vector( -70,    0,  0 ),   -- fuselage body  (centre, trailing edge)
}

-- ============================================================
-- TIER CONFIG  (all emission points share the same tier)
-- Tier 0 = 100% HP  ->  white vapor, always visible.
-- Tier 3 = dead     ->  dense black smoke from every point.
-- ============================================================
local TIER_CONFIG = {
    [0] = { r = 255, g = 255, b = 255, a = 108, startSize = 22, endSize =  4, lifetime = 4 },
    [1] = { r = 160, g = 160, b = 160, a = 148, startSize = 35, endSize =  8, lifetime = 5 },
    [2] = { r =  50, g =  50, b =  50, a = 192, startSize = 52, endSize = 14, lifetime = 6 },
    [3] = { r =  10, g =  10, b =  10, a = 222, startSize = 72, endSize = 22, lifetime = 8 },
}

-- State table keyed by entIndex
local AC130Trails = {}

-- ============================================================
-- INTERNALS
-- ============================================================
local function EnsureRegistered( entIndex )
    if AC130Trails[entIndex] then return end
    local trails = {}
    for i = 1, #TRAIL_POSITIONS do
        trails[i] = { positions = {} }
    end
    AC130Trails[entIndex] = {
        tier       = 0,
        nextSample = 0,
        trails     = trails,
    }
end

-- ============================================================
-- PUBLIC: called from net.Receive in cl_init.lua
-- EnsureRegistered called first so a tier message arriving before
-- the entity is tracked does not silently drop the tier.
-- ============================================================
function PlaneTrailSystem_SetTier( entIndex, tier )
    EnsureRegistered( entIndex )
    local state = AC130Trails[entIndex]
    if not state then return end
    state.tier = tier
end

local function DrawBeam( positions, cfg )
    local n = #positions
    if n < 2 then return end

    local Time = CurTime()
    local lt   = cfg.lifetime

    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove( positions, i )
        end
    end

    n = #positions
    if n < 2 then return end

    render.SetMaterial( TRAIL_MATERIAL )
    render.StartBeam( n )
    for _, pd in ipairs( positions ) do
        local Scale = math.Clamp( (pd.time + lt - Time) / lt, 0, 1 )
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam( pd.pos, size, pd.time * 50,
            Color( cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale ) )
    end
    render.EndBeam()
end

-- ============================================================
-- THINK: sample world positions for every emission point
-- ============================================================
hook.Add( "Think", "bombin_plane_trails_update", function()
    local Time = CurTime()

    for _, ent in ipairs( ents.FindByClass( "ent_bombin_support_plane" ) ) do
        EnsureRegistered( ent:EntIndex() )
    end

    for entIndex, state in pairs( AC130Trails ) do
        local ent = Entity( entIndex )
        if not IsValid( ent ) then
            AC130Trails[entIndex] = nil
            continue
        end

        if Time < state.nextSample then continue end
        state.nextSample = Time + SAMPLE_RATE

        local pos = ent:GetPos()
        local ang = ent:GetAngles()

        for i, trail in ipairs( state.trails ) do
            local wpos = LocalToWorld( TRAIL_POSITIONS[i], Angle(0,0,0), pos, ang )
            table.insert( trail.positions, { time = Time, pos = wpos } )
            table.sort( trail.positions, function( a, b ) return a.time > b.time end )
        end
    end
end )

-- ============================================================
-- DRAW: render beams using the current tier config
-- ============================================================
hook.Add( "PostDrawTranslucentRenderables", "bombin_plane_trails_draw", function( bDepth, bSkybox )
    if bSkybox then return end

    for _, state in pairs( AC130Trails ) do
        local cfg = TIER_CONFIG[ state.tier ] or TIER_CONFIG[0]
        for _, trail in ipairs( state.trails ) do
            DrawBeam( trail.positions, cfg )
        end
    end
end )
