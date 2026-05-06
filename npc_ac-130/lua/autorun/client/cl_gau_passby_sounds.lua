-- Standalone passby sound registration for the AC-130 GAU.
-- Owns all sound.Add aliases and the GAUEmitSound spatial helper.
-- Zero dependency on the RBO addon.

-- ─── Spatial emit helper ─────────────────────────────────────────────────────
-- Mirrors RBOEmitSound exactly: plays the sound at the listener's eye
-- offset slightly toward the bullet's closest-approach position.
-- This keeps the sound audible at any distance while still feeling
-- directional, working around Source's attenuation cutoff at range.

function GAUEmitSound(name, pos, level, pitch, volume)
    local view = GetViewEntity()
    if not IsValid(view) then return end
    local eye = view:EyePos()
    local dir = pos - eye
    dir:Normalize()
    sound.Play(
        name,
        eye + dir * 32,
        level  or 80,
        pitch  or 100,
        volume or 1
    )
end

-- ─── sound.Add alias helper ─────────────────────────────────────────────────

local function FastList(name, ext, num)
    local list = {}
    for i = 1, num do
        list[i] = name .. (i < 10 and "0" .. i or i) .. "." .. ext
    end
    return list
end

-- ─── .50 cal passby aliases ────────────────────────────────────────────────────
-- Used for GAU 30mm passby (closest acoustic match in the RBO library).
-- Alias names are prefixed with gau_ to avoid colliding with RBO's own
-- registrations if both addons happen to be loaded simultaneously.

sound.Add({
    name    = "gau_passby_50_close",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_close_", "ogg", 12)
})

sound.Add({
    name    = "gau_passby_50_medium",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_", "ogg", 12)
})

sound.Add({
    name    = "gau_passby_50_medium_2",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_new_", "ogg", 17)
})

sound.Add({
    name    = "gau_passby_50_far",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_far_", "ogg", 8)
})

sound.Add({
    name    = "gau_passby_50_far_2",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_far_new_", "ogg", 19)
})

-- ─── Hiss aliases (used for mid-range pass) ─────────────────────────────────

sound.Add({
    name    = "gau_passby_hiss_far",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/hiss/passby_crack_hiss_far_", "ogg", 29)
})
