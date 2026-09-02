-- ============================================================================
--                          CRIMSON - DUEL WIELDING
--                            Authored by John Allday
-- ============================================================================
-- Everything you are meant to touch lives in this file.
--
-- NOTE ON SECURITY: this file is a shared_script, so the SERVER loads its own
-- private copy of this table. The server re-checks every value here before it
-- allows anything, so a modified client cannot widen the allow-list. Do not
-- move the weapon allow-list to a client-only file.
-- ============================================================================

Config = {}

-- ----------------------------------------------------------------------------
-- ACTIVATION
-- ----------------------------------------------------------------------------

-- Press this key to open the dual wield menu, which lists the one-handed guns
-- you are carrying but not currently holding. Pick one and it goes in your left
-- hand. Players can rebind it in Settings > Key Bindings > FiveM.
--
-- NOTE: the default only applies the FIRST time a client ever sees this
-- binding. Changing it later will not move anyone's existing key.
Config.Keybind = 'K'

-- Chat command that opens the same menu, and turns akimbo off. Kept as a
-- fallback so nobody is ever stuck with a gun they cannot put away.
-- Set to false to remove it.
Config.Command = 'dualwield'

-- ----------------------------------------------------------------------------
-- ALLOWED WEAPONS
-- ----------------------------------------------------------------------------
-- Only one-handed weapons belong here. Putting a rifle in this list will look
-- broken, because the offhand prop is attached to the left hand.
-- Names must match your ox_inventory item names exactly (UPPERCASE).
-- Enforced server-side.
--
-- BOTH hands must be on this list: the gun you are holding, and the gun you
-- pick for your left hand. They do NOT have to be the same weapon -- a Pistol
-- in the right hand and a Combat Pistol in the left is fine. Each gun uses its
-- own ammo, from its own inventory slot.

Config.AllowedWeapons = {
    -- Pistols
    ['WEAPON_PISTOL']         = true,
    ['WEAPON_PISTOL_MK2']     = true,
    ['WEAPON_COMBATPISTOL']   = true,
    ['WEAPON_APPISTOL']       = true,
    ['WEAPON_PISTOL50']       = true,
    ['WEAPON_SNSPISTOL']      = true,
    ['WEAPON_SNSPISTOL_MK2']  = true,
    ['WEAPON_HEAVYPISTOL']    = true,
    ['WEAPON_VINTAGEPISTOL']  = true,
    ['WEAPON_CERAMICPISTOL']  = true,
    ['WEAPON_PISTOLXM3']      = true,   -- WM 29 Pistol
    ['WEAPON_GADGETPISTOL']   = true,   -- Perico Pistol
    ['WEAPON_MARKSMANPISTOL'] = true,

    -- Revolvers. Slower, hit harder, and akimbo revolvers look the part.
    ['WEAPON_REVOLVER']       = true,
    ['WEAPON_REVOLVER_MK2']   = true,
    ['WEAPON_DOUBLEACTION']   = true,
    ['WEAPON_NAVYREVOLVER']   = true,

    -- Machine pistols and micro SMGs. Still a one-handed grip in game.
    -- These are the strongest thing on this list: high rate of fire doubled.
    -- Set any of them to false if akimbo feels too strong on your server.
    ['WEAPON_MACHINEPISTOL']  = true,
    ['WEAPON_MICROSMG']       = true,
    ['WEAPON_MINISMG']        = true,
    ['WEAPON_TECPISTOL']      = true,   -- Tactical SMG

    -- Other one-handed guns you run.
    ['WEAPON_FLAREGUN']       = true,
    ['WEAPON_NAILGUN']        = true,

    -- One-handed but not really guns. Off by default; flip any to true if you
    -- want them. Dual pepper spray is legal, just silly.
    ['WEAPON_PEPPERSPRAY']     = false,
    ['WEAPON_PINKPEPPERSPRAY'] = false,
    ['WEAPON_ACIDSPRAY']       = false,
    ['WEAPON_SPRAYPAINT']      = false,
    ['WEAPON_FIREWORKSINGLE']  = false,

    -- Deliberately absent: every rifle, shotgun, SMG proper (WEAPON_SMG,
    -- WEAPON_ASSAULTSMG, WEAPON_COMBATPDW, WEAPON_GUSENBERG), MG, sniper and
    -- launcher on your server. They are two-handed, so a second gun welded to
    -- the left hand looks wrong no matter how the offsets are tuned.
    --
    -- Also unusable even if you added them: WEAPON_STUNGUN and WEAPON_RAYPISTOL
    -- have no ammoname in your weapons.lua, so ox_inventory never gives them a
    -- metadata.ammo value, and a gun with no ammo can never be picked here.
}

-- ----------------------------------------------------------------------------
-- BALANCE
-- ----------------------------------------------------------------------------

-- Rounds burned from the OFFHAND gun's own magazine per offhand shot.
-- The offhand cannot be reloaded while it is in your left hand, so when it runs
-- dry akimbo switches itself off and you get your hands back. Reload that gun
-- by equipping it normally, then pick it again.
-- 0 makes the offhand free (not recommended).
Config.AmmoPerOffhandShot = 1

-- Accuracy penalty for the offhand, in metres of scatter at the aim point.
-- 0.0 = the offhand is pinpoint. Higher = akimbo sprays. 0.35 is a fair start.
Config.OffhandSpread = 0.35

-- How far the offhand shot is traced, in metres.
Config.OffhandRange = 60.0

-- Seconds a player must wait between toggles. Also enforced server-side.
Config.ToggleCooldown = 1.0

-- ----------------------------------------------------------------------------
-- VISUALS
-- ----------------------------------------------------------------------------

-- Let other players see your second gun. This costs one small local prop per
-- nearby akimbo player. The prop is created LOCALLY on each client (never a
-- networked entity), the same approach crimson-backweapons uses.
Config.ShowToOtherPlayers = true

-- One-handed "gangster" grip. Makes the mainhand read as akimbo rather than a
-- normal two-handed stance. Set to false to keep the default animation.
Config.UseGangAnimation = true

-- Left-hand attachment. Tuned for standard pistol models.
-- If the gun sits through the palm, nudge these. A prop aligner such as
-- noted_propattacher will print exact values for a specific model.
Config.Attach = {
    bone = 'IK_L_Hand',
    pos  = vec3(0.12, 0.03, 0.02),
    rot  = vec3(-75.0, 5.0, 175.0),
}

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS
-- ----------------------------------------------------------------------------

Config.Notify = {
    enabled  = true,
    enabled_msg  = 'Dual wielding enabled',
    disabled_msg = 'Dual wielding disabled',
    not_allowed  = 'That weapon cannot be dual wielded',
    blocked      = 'You cannot do that right now',
    nothing      = 'You are not carrying a second gun you can dual wield',
    need_mainhand = 'Hold a one-handed gun first',
    in_hand      = 'You are already holding that gun',
    out_of_ammo  = 'Your offhand gun is empty',
    menu_title   = 'Dual Wield',
    menu_stop    = 'Stop dual wielding',
}
