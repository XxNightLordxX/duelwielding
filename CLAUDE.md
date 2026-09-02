# Rules for this repository

These are hard rules, not preferences. They came from real failures on this
project.

## 1. Fix the broken thing. Do not build around it.

When something does not work, find out why it does not work and change that.

Do not leave the failing code in place and add a second mechanism next to it
that tries to compensate. Two examples of the exact mistake, both from this
repo:

- `SetWeaponAnimationOverride` was not taking effect, so a timer was added to
  call it repeatedly. Calling a no-op more often is still a no-op. The real
  cause was that the override changes the aiming clipset and the ped only loads
  that clipset on equip, so the weapon had to be re-equipped. The timer was
  deleted and replaced with the re-equip.
- The offhand offsets were wrong, so an in-game tuner was added instead of
  correcting the numbers. Once the numbers were right the tuner was dead weight
  and had to be removed again.

If a fix does not work, remove it before trying the next one. Never stack
attempts.

## 2. Do not ship anything that is not working or will not be used.

No speculative config options. No debug commands "in case they help". No
helper that nothing calls. No commented-out alternative. If a thing cannot be
shown to work, it does not go in.

When something is removed, remove it **completely**: the code, the config
entry, the comments referring to it, and the documentation. Grep for the name
afterwards and confirm zero hits. A half-removed feature is worse than one that
was never added.

## 3. Verify against the real source, not against assumptions.

Every bug that reached the server in this repo came from trusting an assumed
API shape:

- `lib.requestModel` throws on timeout, it does not return false.
- `ox_inventory:Search` returns a flat array for one item name and a map keyed
  by item name for several.
- `SetWeaponAnimationOverride` needs the weapon re-equipped to take effect.

Read the actual source or the actual native documentation before relying on a
signature or a return shape. When a test mock is written, it must mirror the
real function including its edge cases -- a mock that is more convenient than
reality makes tests that pass against a fiction.

## 4. Be honest about what has not been verified.

Anything that cannot be checked outside the running game must be called out as
unverified when it is handed over. Do not present a guess as a tested result.
