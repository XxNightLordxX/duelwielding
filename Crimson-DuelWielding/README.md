# Crimson-DuelWielding

Simple dual wielding (akimbo) for QBox servers.

Authored by John Allday.

Press a key, pick a gun from the list, and it appears in your left hand and
fires along with the one in your right. The two guns do not have to match, and
each one uses its own ammo.

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

Hold a one-handed gun, press **K**, and a menu lists the other one-handed guns
you are carrying, with how many rounds each has left. Pick one and it goes in
your left hand. Press **K** again to put it away.

| Action | How |
| --- | --- |
| Open the menu / put it away | **K** (rebind in *Settings > Key Bindings > FiveM*) |
| Same thing as a command | `/dualwield` |

The two guns do **not** have to be the same. A Pistol in your right hand and a
Combat Pistol in your left is fine — both just have to be on the allow-list.

**Each gun uses its own ammo.** The offhand spends rounds from its own inventory
slot, so you are carrying and can be robbed of a real second magazine.

**The offhand cannot be reloaded while it is in your left hand.** When it runs
dry, akimbo switches itself off and tells you. To reload it, equip that gun
normally, reload, then pick it again.

## Configuration

Everything lives in `config.lua` and is commented. The options you are most
likely to change:

| Option | Default | What it does |
| --- | --- | --- |
| `Config.Keybind` | `'K'` | Key that opens the menu |
| `Config.Command` | `'dualwield'` | Chat command that does the same |
| `Config.AllowedWeapons` | 23 one-handed guns | Which weapons may be akimbo'd |
| `Config.AmmoPerOffhandShot` | `1` | Rounds burned from the offhand's own magazine |
| `Config.OffhandSpread` | `0.35` | Offhand accuracy penalty, in metres |
| `Config.ShowToOtherPlayers` | `true` | Others can see your second gun |
| `Config.Attach` | tuned for pistols | Left-hand position and rotation |

If the gun sits wrong in the hand for a particular model, adjust
`Config.Attach`. `pos` moves it, `rot` turns it; add 180 to `rot.z` if the
barrel points backwards.

`Config.AllowedWeapons` ships with every one-handed firearm on this server
enabled: 13 pistols, 4 revolvers, 4 machine pistols and micro SMGs, plus the
flare gun and nail gun. Sprays and fireworks are listed but off.

Only put **one-handed** weapons in it. The offhand gun is attached to the left
hand, so a rifle will look wrong no matter how the offsets are tuned. **Both**
hands are checked against this list: the gun you are holding and the gun you
pick.

A weapon also needs an `ammoname` in `ox_inventory/data/weapons.lua`. Without
one, ox_inventory never gives it a `metadata.ammo` value, and a gun with no
ammo can never be chosen as an offhand.

`Config.Keybind` only applies the **first** time a client ever sees the binding.
Changing it in a later release will not move anyone's existing key.

## When it turns itself off

Akimbo is dropped automatically, and the offhand gun removed, when you:

- go **down** (bleeding out) or **die**
- get **cuffed**
- **switch weapon** or holster
- **enter a vehicle**
- run the offhand **out of ammo**
- **drop, sell or move** the offhand gun out of its slot

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

The menu itself is built **by the server** from your own inventory — the client
never decides what is eligible, it only renders what it is handed and sends back
one slot number from that list. That slot is then resolved against your own
inventory only, so it can never reach a stash, trunk, shop or another player.

Every request is validated server-side: the slot is a real integer, it holds a
whitelisted weapon, it is not the gun already in your hand, it has ammo, and you
are not dead, down or cuffed. The server also re-checks its own grants on a
timer and revokes them, so a modified client that simply never reports going
down does not keep its offhand. Per-player state is cleared on disconnect.

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
