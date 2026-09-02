# Crimson-DuelWielding

Simple dual wielding (akimbo) for QBox servers.

Authored by John Allday.

Carry two of the same pistol, run `/dualwield`, and a second gun appears in your
left hand and fires along with the first one. Run it again to put it away.

---

## Requirements

- **QBox** (`qbx_core`)
- **ox_lib**
- **ox_inventory**

Nothing else. There is no SQL, no new inventory item to register, and no UI.

## Install

1. Drop the `Crimson-DuelWielding` folder into your `resources` directory.
2. Add `ensure Crimson-DuelWielding` to your `server.cfg`, **after** `ox_lib`
   and `ox_inventory`.
3. Restart the server.

That is the whole install. `config.lua` ships with a sensible pistol list, so it
works untouched.

## Usage

| Action | How |
| --- | --- |
| Toggle akimbo on/off | `/dualwield` |
| Bind it to a key | Set `Config.Keybind`, then rebind in *Settings > Key Bindings > FiveM* |

To dual wield you must be **holding a whitelisted weapon** and **carrying two of
it** (see `Config.RequireTwoWeapons`). Carrying the second gun is the cost — you
can be robbed of it like any other weapon.

## Configuration

Everything lives in `config.lua` and is commented. The options you are most
likely to change:

| Option | Default | What it does |
| --- | --- | --- |
| `Config.Command` | `'dualwield'` | Chat command name |
| `Config.Keybind` | `false` | Optional default key |
| `Config.RequireTwoWeapons` | `true` | Must carry two of the same gun |
| `Config.AllowedWeapons` | pistols | Which weapons may be akimbo'd |
| `Config.AmmoPerOffhandShot` | `1` | Ammo burned per offhand shot |
| `Config.OffhandSpread` | `0.35` | Offhand accuracy penalty, in metres |
| `Config.ShowToOtherPlayers` | `true` | Others can see your second gun |
| `Config.Attach` | tuned for pistols | Left-hand position and rotation |

Only put **one-handed** weapons in `Config.AllowedWeapons`. The offhand gun is
attached to the left hand, so a rifle will look wrong.

If the gun sits through the palm on a particular model, nudge `Config.Attach`.
An in-game prop aligner will print exact values for a given model.

## When it turns itself off

Akimbo is dropped automatically, and the offhand gun removed, when you:

- go **down** (bleeding out) or **die**
- get **cuffed**
- **switch weapon** or holster
- **enter a vehicle**

It does **not** come back on by itself after a revive. Toggle it again when you
want it. Nobody gets a surprise pistol in their hand after being picked up.

## Notes for server owners

**Death detection.** This resource does not use ped health to decide whether you
are dead, because that answer is wrong on a lot of servers. Medical scripts
commonly resurrect the ped and restore full health while the player is lying
"dead", which makes `IsEntityDead` and every health check report a perfectly
healthy player for the entire death state. Instead it asks the medical resource
directly, then falls back to player state, then to player metadata on the
server. It is verified against `sc-ambulance`, and the metadata fallback
(`isdead` / `inlaststand`) is the standard QBox convention, so it works without
it too.

**Anticheat.** Offhand rounds are fired with the damage value read from the
weapon itself via `GetWeaponDamage`, never a number from the config or the
client, so an offhand round carries exactly the damage a normal round from that
gun carries. Shots originate at the player's own left hand and are rate-limited
to the weapon's real fire interval, offset from the mainhand rather than fired on
the same tick. You should not need to whitelist anything, and you should be wary
of any resource that asks you to — a broad anticheat exemption helps cheaters far
more than it helps a script.

**Performance.** The firing loop only exists while akimbo is actually on. When it
is off the resource costs nothing.

**Entities.** The offhand gun is a local, non-networked, collisionless prop.
Every client draws its own copy, so no networked entities are created and there
is nothing for an entity-spam check to trip on.

## For other resources

The server exposes a read-only export:

```lua
-- Note the bracket syntax. The hyphen in the resource name makes
-- exports.Crimson-DuelWielding:... a Lua syntax error.
local akimbo = exports['Crimson-DuelWielding']:IsDualWielding(playerId)
```

Each akimbo player also carries a replicated state bag, written only by the
server, which is what draws the second gun on other players' screens:

```lua
Player(playerId).state.crimsonDuelWield  -- weapon name, or false
```

## Security

The server is the authority. The client can only ever ask *"may I akimbo this
weapon"* and be told yes or no. It never sends damage, coordinates, a weapon
hash, an ammo count or a player id, because none of those could be trusted.

Every request is validated server-side: the weapon allow-list, that you are
actually holding that weapon, that you are carrying enough of them, that you are
not dead, down or cuffed, and a per-player cooldown. Per-player state is cleared
on disconnect.

Validation does not stop at the grant. Every teardown the client performs is a
courtesy, so the server re-checks its own grants every few seconds and revokes
any player who has since died, gone down, been cuffed, or lost the second gun.
A modified client that simply never reports going down still loses the offhand,
because the state bag that draws it on everyone else's screen is written only by
the server.

Cuffing is judged on the server for the same reason. The client does not test
for it at all: on this stack the only real cuff signal is player metadata, and
guessing at client-side names would produce a check that silently never fires.

Note that `config.lua` is a shared script, so the server holds its own copy of
the allow-list. Editing a client's copy changes nothing.

## Credits

Written by John Allday.
