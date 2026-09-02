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

-- Chat command used to toggle akimbo on/off. Set to false to disable the command.
Config.Command = 'dualwield'

-- Optional keybind. Players rebind it in Settings > Key Bindings > FiveM.
-- Set to false for no default key. 'GRAVE' is the ` / ~ key.
Config.Keybind = false

-- Require the player to actually be carrying TWO of the same weapon.
-- This is the whole cost of dual wielding: you carry (and can lose) two guns.
-- Set to false to let a single weapon be akimbo'd.
Config.RequireTwoWeapons = true

-- ----------------------------------------------------------------------------
-- ALLOWED WEAPONS
-- ----------------------------------------------------------------------------
-- Only one-handed weapons belong here. Putting a rifle in this list will look
-- broken, because the offhand prop is attached to the left hand.
-- Names must match your ox_inventory item names exactly (UPPERCASE).
-- Enforced server-side.

Config.AllowedWeapons = {
    ['WEAPON_PISTOL']        = true,
    ['WEAPON_PISTOL_MK2']    = true,
    ['WEAPON_COMBATPISTOL']  = true,
    ['WEAPON_APPISTOL']      = true,
    ['WEAPON_PISTOL50']      = true,
    ['WEAPON_SNSPISTOL']     = true,
    ['WEAPON_SNSPISTOL_MK2'] = true,
    ['WEAPON_HEAVYPISTOL']   = true,
    ['WEAPON_VINTAGEPISTOL'] = true,
    ['WEAPON_CERAMICPISTOL'] = true,
    ['WEAPON_PISTOLXM3']     = true,
    ['WEAPON_MACHINEPISTOL'] = true,
    ['WEAPON_MINISMG']       = true,
    ['WEAPON_MICROSMG']      = true,
    ['WEAPON_TECPISTOL']     = true,
    ['WEAPON_GADGETPISTOL']  = true,

    -- Revolvers. Disabled by default: they look odd akimbo and reload slowly.
    -- Set any of these to true to allow them.
    ['WEAPON_REVOLVER']      = false,
    ['WEAPON_REVOLVER_MK2']  = false,
    ['WEAPON_DOUBLEACTION']  = false,
    ['WEAPON_NAVYREVOLVER']  = false,
    ['WEAPON_MARKSMANPISTOL'] = false,
}

-- ----------------------------------------------------------------------------
-- BALANCE
-- ----------------------------------------------------------------------------

-- Extra rounds burned per offhand shot. 1 = the offhand costs a real bullet,
-- so akimbo drains your magazine twice as fast. This is the balance lever.
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
    need_two     = 'You need two of the same weapon',
    not_allowed  = 'That weapon cannot be dual wielded',
    blocked      = 'You cannot do that right now',
}
