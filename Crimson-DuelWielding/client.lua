-- ============================================================================
--                          CRIMSON - DUEL WIELDING
--                            Authored by John Allday
-- ============================================================================
-- CLIENT. Draws the offhand gun, fires it in time with the mainhand, and tears
-- everything down the moment the player is downed, dead, cuffed, in a vehicle
-- or has switched weapon.
-- ============================================================================

local enabled      = false
local busy         = false   -- an enable is in progress (spans the model load)
local loopRunning  = false   -- guards against a second firing thread
local activeHash   = nil     -- MAINHAND hash the offhand is paired with
local offhandSlot  = nil     -- its inventory slot
local offhandAmmo  = 0       -- rounds left in the offhand's own magazine
local ammoDirty    = false   -- unflushed ammo spend
local offhandProp  = nil
local remoteProps  = {}      -- [serverId] = prop entity
local remoteWanted = {}      -- [serverId] = weapon name
local pendingList  = {}      -- last menu payload from the server

local BONE = Config.Attach and Config.Attach.bone or 'IK_L_Hand'

-- Live copies, so /dwtune can nudge the offhand gun without a restart.
local attachPos = vector3(Config.Attach.pos.x, Config.Attach.pos.y, Config.Attach.pos.z)
local attachRot = vector3(Config.Attach.rot.x, Config.Attach.rot.y, Config.Attach.rot.z)

local function animStyle()
    return joaat(Config.AnimationStyle or 'Gang1H')
end

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------

local function notify(key)
    local n = Config.Notify
    if not n or not n.enabled then return end
    local msg = n[key]
    if not msg then return end
    lib.notify({ description = msg })
end

local function deleteProp(prop)
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        SetEntityAsMissionEntity(prop, true, true)
        DeleteEntity(prop)
        if DoesEntityExist(prop) then DeleteObject(prop) end
    end
end

-- Attach a weapon prop to a ped's left hand. The object is created with
-- isNetwork = false, so it exists ONLY on this client: no networked entity, no
-- ownership migration, nothing an anticheat can read as entity spam. Every
-- client draws its own copy, which is how crimson-backweapons does it too.
local function createOffhandProp(ped, weaponName)
    if not DoesEntityExist(ped) then return nil end

    local model = GetWeapontypeModel(joaat(weaponName))
    if not model or model == 0 then return nil end

    -- lib.requestModel does NOT return false on timeout: it goes through
    -- lib.streamingRequest -> lib.waitFor, which ends in error(). Unguarded, a
    -- model that fails to stream would raise straight out of the command
    -- handler while the server had already granted, leaving the player's state
    -- bag saying "dual wielding" with no way to turn it off.
    local ok, res = pcall(lib.requestModel, model, 5000)
    if not ok or res == false then return nil end
    if not HasModelLoaded(model) then return nil end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(prop) then return nil end

    SetEntityCollision(prop, false, false)

    local boneIndex = GetEntityBoneIndexByName(ped, BONE)
    if boneIndex == -1 then boneIndex = 0 end   -- invalid index attaches at the centre

    AttachEntityToEntity(prop, ped, boneIndex,
        attachPos.x, attachPos.y, attachPos.z,
        attachRot.x, attachRot.y, attachRot.z,
        true, true, false, true, 1, true)

    return prop
end

-- ----------------------------------------------------------------------------
-- Blocked states
-- ----------------------------------------------------------------------------
-- Do NOT use ped health here. sc-ambulance calls NetworkResurrectLocalPlayer
-- and restores full health while the player lies "dead", so IsEntityDead and
-- any health check both report a healthy player for the entire death state.
-- Ask the medical script, then fall back to state bags, then to the native.

local function isDownOrDead()
    if GetResourceState('sc-ambulance') == 'started' then
        local ok, dead = pcall(function() return exports['sc-ambulance']:IsDead() end)
        if ok and dead then return true end

        local ok2, down = pcall(function() return exports['sc-ambulance']:IsLaststand() end)
        if ok2 and down then return true end
    end

    local st = LocalPlayer.state
    if st.dead or st.laststand or st.isDead then return true end

    return IsPedDeadOrDying(cache.ped, true)
end

local function isBlocked()
    if isDownOrDead() then return true end

    -- Cuffing is deliberately NOT tested here. On this stack the only real cuff
    -- signal is player metadata (ishandcuffed), which lives on the server; the
    -- client state-bag names that look right are not written by anything. The
    -- server checks it at toggle time and revokes via crimson_duelwield:revoke.
    if cache.vehicle or IsPedInAnyVehicle(cache.ped, true) then return true end

    return false
end

-- ----------------------------------------------------------------------------
-- Offhand firing
-- ----------------------------------------------------------------------------

local function cameraDirection()
    local rot = GetGameplayCamRot(2)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local flat = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * flat, math.cos(rz) * flat, math.sin(rx))
end

local function fireOffhand(ped, hash)
    -- The offhand gun is not on the ped, so its ammo lives on its inventory
    -- slot, not in GetAmmoInPedWeapon. Track it here and flush to ox_inventory.
    local cost = Config.AmmoPerOffhandShot or 1
    if offhandAmmo < cost then return false end

    local boneIndex = GetEntityBoneIndexByName(ped, BONE)
    local origin = boneIndex ~= -1
        and GetWorldPositionOfEntityBone(ped, boneIndex)
        or GetEntityCoords(ped)

    local dir    = cameraDirection()
    local start  = origin + (dir * 0.35)
    local target = start + (dir * (Config.OffhandRange or 60.0))

    local spread = Config.OffhandSpread or 0.0
    if spread > 0.0 then
        target = target + vector3(
            (math.random() - 0.5) * 2.0 * spread,
            (math.random() - 0.5) * 2.0 * spread,
            (math.random() - 0.5) * 2.0 * spread
        )
    end

    -- Damage is read from the weapon itself. It is never configurable and never
    -- comes from the client, so an offhand round always carries exactly the same
    -- damage as a normal round from the same gun.
    local damage = math.floor(GetWeaponDamage(hash, 0) or 0)
    if damage <= 0 then return false end

    -- IgnoreEntity variant: the muzzle sits centimetres from the player's own
    -- collision capsule, so the plain native can register a self-hit.
    ShootSingleBulletBetweenCoordsIgnoreEntity(
        start.x, start.y, start.z,
        target.x, target.y, target.z,
        damage,
        true,           -- pureAccuracy (spread is applied above instead)
        hash,
        ped,            -- ownerPed, so kills attribute correctly
        true,           -- audible
        false,          -- not invisible
        1500.0,
        ped             -- entity to ignore
    )

    if cost > 0 then
        offhandAmmo = offhandAmmo - cost
        ammoDirty = true
    end

    return true
end

-- ox_inventory's own updateWeapon handler takes an explicit slot and only ever
-- DECREMENTS (a value >= the stored ammo is ignored outright), so this can
-- never be turned into an ammo duplication ratchet. Flush on a debounce rather
-- than every shot, the same way ox_inventory does for the equipped weapon.
local function flushAmmo()
    if not ammoDirty or not offhandSlot then return end
    ammoDirty = false
    TriggerServerEvent('ox_inventory:updateWeapon', 'ammo', math.max(0, offhandAmmo), offhandSlot)
end

-- ----------------------------------------------------------------------------
-- Teardown
-- ----------------------------------------------------------------------------

local function disable(silent)
    if not enabled then return end
    enabled = false

    flushAmmo()

    deleteProp(offhandProp)
    offhandProp = nil
    activeHash, offhandSlot, offhandAmmo = nil, nil, 0

    if Config.UseGangAnimation then
        SetWeaponAnimationOverride(cache.ped, `Default`)
    end

    TriggerServerEvent('crimson_duelwield:stop')
    if not silent then notify('disabled_msg') end
end

-- ----------------------------------------------------------------------------
-- Main loop. Runs only while akimbo is active, so the resource costs nothing
-- when it is off.
-- ----------------------------------------------------------------------------

local function runLoop()
    if loopRunning then return end
    loopRunning = true

    local lastAmmo   = GetAmmoInPedWeapon(cache.ped, activeHash)
    local pendingAt  = 0
    local nextFlush  = 0
    local nextAnim   = 0
    local refresh    = Config.AnimationRefresh or 1000
    local interval   = (GetWeaponTimeBetweenShots(activeHash) or 0.1) * 1000.0

    CreateThread(function()
        while enabled do
            local ped = cache.ped

            if isBlocked() or cache.weapon ~= activeHash then
                disable()
                break
            end

            local now  = GetGameTimer()
            local ammo = GetAmmoInPedWeapon(ped, activeHash)

            -- A real shot is the only thing that decrements ammo, so this can
            -- never double-count the way a bare IsPedShooting check does.
            if IsPedShooting(ped) and ammo < lastAmmo and pendingAt == 0 then
                -- Offset the offhand by half the weapon's cycle instead of
                -- firing on the same tick, so the pair reads as a plausible
                -- left-right cadence rather than two simultaneous rounds.
                pendingAt = now + math.max(40.0, interval * 0.5)
            end

            if pendingAt > 0 and now >= pendingAt then
                if not IsPedReloading(ped) then
                    if not fireOffhand(ped, activeHash) and offhandAmmo < (Config.AmmoPerOffhandShot or 1) then
                        -- The offhand cannot be reloaded while it is in the left
                        -- hand, so an empty gun means hands back rather than a
                        -- dead prop that silently does nothing.
                        notify('out_of_ammo')
                        disable(true)
                        break
                    end
                end
                pendingAt = 0
                ammo = GetAmmoInPedWeapon(ped, activeHash)
            end

            if ammoDirty and now >= nextFlush then
                flushAmmo()
                nextFlush = now + 1000
            end

            -- The animation override is ped state that other resources and
            -- weapon switches quietly reset. Without this the support hand
            -- creeps back onto the mainhand and drags the offhand gun with it.
            if Config.UseGangAnimation and refresh > 0 and now >= nextAnim then
                SetWeaponAnimationOverride(ped, animStyle())
                nextAnim = now + refresh
            end

            lastAmmo = ammo
            Wait(0)
        end

        loopRunning = false
    end)
end

-- ----------------------------------------------------------------------------
-- Toggle
-- ----------------------------------------------------------------------------

-- Everything between the server round trip and `enabled = true` must run under
-- the busy guard. createOffhandProp yields inside lib.requestModel while a
-- weapon model streams in -- on first use of a model that can be seconds -- and
-- during that yield neither `busy` nor `enabled` would stop a second toggle.
-- That produced an orphaned prop welded to the hand and two firing threads.
-- ----------------------------------------------------------------------------
-- Menu
-- ----------------------------------------------------------------------------
-- The SERVER builds the list from the player's own inventory. The client never
-- decides what is eligible; it only renders what it is handed and sends back
-- one slot number from that list.

local function equip(slot)
    if busy or enabled then return end
    busy = true
    local ok, reason, ammo = lib.callback.await('crimson_duelwield:select', false, slot)
    busy = false

    if not ok then
        notify(reason or 'blocked')
        return
    end

    -- The world can have moved on during the round trip.
    local weapon = cache.weapon
    if enabled or isBlocked() or not weapon then
        TriggerServerEvent('crimson_duelwield:stop')
        return
    end

    local list = pendingList
    local picked
    for i = 1, #list do
        if list[i].slot == slot then picked = list[i] break end
    end
    if not picked then
        TriggerServerEvent('crimson_duelwield:stop')
        return
    end

    local prop = createOffhandProp(cache.ped, picked.name)
    if not prop then
        -- An invisible offhand that still shoots looks exactly like a cheat.
        -- Fail closed instead.
        TriggerServerEvent('crimson_duelwield:stop')
        notify('blocked')
        return
    end

    enabled     = true
    activeHash  = weapon
    offhandSlot = slot
    offhandAmmo = tonumber(ammo) or 0
    ammoDirty   = false
    offhandProp = prop

    if Config.UseGangAnimation then
        SetWeaponAnimationOverride(cache.ped, animStyle())
    end

    notify(reason or 'enabled_msg')
    runLoop()
end

local function openMenu()
    if busy then return end

    if enabled then
        disable()
        return
    end

    if isBlocked() then
        notify('blocked')
        return
    end

    busy = true
    local res = lib.callback.await('crimson_duelwield:list', false)
    busy = false

    if type(res) ~= 'table' or not res.ok then
        notify((type(res) == 'table' and res.reason) or 'blocked')
        return
    end

    local slots = res.slots or {}
    if #slots == 0 then
        notify('nothing')
        return
    end

    pendingList = slots

    local options = {}
    for i = 1, #slots do
        local s = slots[i]
        options[#options + 1] = {
            title       = s.label,
            description = ('%d rounds'):format(s.ammo or 0),
            disabled    = (s.ammo or 0) < 1,
            onSelect    = function() equip(s.slot) end,
        }
    end

    lib.registerContext({
        id      = 'crimson_duelwield_menu',
        title   = (Config.Notify and Config.Notify.menu_title) or 'Dual Wield',
        options = options,
    })
    lib.showContext('crimson_duelwield_menu')
end

RegisterCommand('crimson_duelwield_menu', openMenu, false)

if Config.Keybind then
    RegisterKeyMapping('crimson_duelwield_menu', 'Dual wield menu', 'keyboard', Config.Keybind)
end

if Config.Command then
    RegisterCommand(Config.Command, openMenu, false)
end

-- ----------------------------------------------------------------------------
-- Reactive teardown
-- ----------------------------------------------------------------------------

-- Weapon switched or holstered. This is the fast path: ox_lib fires it the
-- moment the ped's weapon changes, so the prop never lingers in an empty hand.
lib.onCache('weapon', function(weapon)
    if enabled and weapon ~= activeHash then disable() end
end)

lib.onCache('vehicle', function(vehicle)
    if enabled and vehicle then disable() end
end)

-- Downed, dead or cuffed. Watched on a slow timer because the medical script
-- can enter the dead state without any event this resource can hook.
CreateThread(function()
    while true do
        if enabled and isBlocked() then disable(true) end
        Wait(250)
    end
end)

-- The server revokes when it sees the player dead, downed, cuffed, or no longer
-- carrying the weapon. It is the only authority on those, so obey unconditionally.
RegisterNetEvent('crimson_duelwield:revoke', function()
    if source == '' then return end     -- locally injected TriggerEvent
    disable(true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    deleteProp(offhandProp)
    for _, prop in pairs(remoteProps) do deleteProp(prop) end
    -- SetWeaponAnimationOverride is ped state, not a resource-owned entity, so
    -- FiveM's own cleanup will not revert it. Restore it explicitly or the
    -- player keeps the one-handed grip until they rejoin.
    if Config.UseGangAnimation then
        SetWeaponAnimationOverride(PlayerPedId(), `Default`)
    end
end)

-- ----------------------------------------------------------------------------
-- Other players' offhand guns
-- ----------------------------------------------------------------------------
-- The server is the only writer of this state bag, so its value can be trusted
-- for rendering. Props are still created locally on each client.

if Config.ShowToOtherPlayers then
    AddStateBagChangeHandler('crimsonDuelWield', nil, function(bagName, _, value)
        local serverId = tonumber(bagName:match('player:(%d+)'))
        if not serverId then return end
        if serverId == GetPlayerServerId(PlayerId()) then return end

        -- A client can write its own replicated player state bag, so this value
        -- is not inherently trustworthy. Render only allow-listed weapons, so
        -- the worst a spoofed bag can do is show a pistol that is not there.
        local ok = type(value) == 'string' and Config.AllowedWeapons[value] == true
        remoteWanted[serverId] = ok and value or nil

        if not remoteWanted[serverId] and remoteProps[serverId] then
            deleteProp(remoteProps[serverId])
            remoteProps[serverId] = nil
        end
    end)

    CreateThread(function()
        while true do
            for serverId, name in pairs(remoteWanted) do
                local plyIdx = GetPlayerFromServerId(serverId)
                local ped    = plyIdx ~= -1 and GetPlayerPed(plyIdx) or 0

                if ped ~= 0 and DoesEntityExist(ped) then
                    if not remoteProps[serverId] or not DoesEntityExist(remoteProps[serverId]) then
                        remoteProps[serverId] = createOffhandProp(ped, name)
                    end
                elseif remoteProps[serverId] then
                    deleteProp(remoteProps[serverId])
                    remoteProps[serverId] = nil
                end

                -- Player is no longer in the session at all: drop the entry so
                -- this table cannot grow without bound over a long uptime.
                if plyIdx == -1 then remoteWanted[serverId] = nil end
            end

            for serverId, prop in pairs(remoteProps) do
                if not remoteWanted[serverId] then
                    deleteProp(prop)
                    remoteProps[serverId] = nil
                end
            end

            Wait(500)
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Offset tuner (Config.Debug)
-- ----------------------------------------------------------------------------
-- Hand offsets cannot be worked out on paper: they depend on the weapon model
-- and the bone. Turn on Config.Debug, dual wield, and run /dwtune to drag the
-- gun into place. It prints a Config.Attach block ready to paste.

if Config.Debug then
    local tuning = false

    local function reattach()
        if not offhandProp or not DoesEntityExist(offhandProp) then return end
        local ped = cache.ped
        local boneIndex = GetEntityBoneIndexByName(ped, BONE)
        if boneIndex == -1 then boneIndex = 0 end
        DetachEntity(offhandProp, true, true)
        AttachEntityToEntity(offhandProp, ped, boneIndex,
            attachPos.x, attachPos.y, attachPos.z,
            attachRot.x, attachRot.y, attachRot.z,
            true, true, false, true, 1, true)
    end

    local function line(text, y)
        SetTextFont(4) SetTextScale(0.32, 0.32) SetTextColour(255, 255, 255, 220)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandDisplayText(0.015, y)
    end

    local function dump()
        local out = ('Config.Attach = {\n    bone = \'%s\',\n    pos  = vec3(%.3f, %.3f, %.3f),\n    rot  = vec3(%.1f, %.1f, %.1f),\n}')
            :format(BONE, attachPos.x, attachPos.y, attachPos.z, attachRot.x, attachRot.y, attachRot.z)
        print('\n[Crimson-DuelWielding] paste this into config.lua:\n' .. out .. '\n')
        lib.notify({ description = 'Offsets printed to F8 console' })
    end

    RegisterCommand('dwtune', function()
        if not enabled then
            lib.notify({ type = 'error', description = 'Dual wield something first' })
            return
        end
        tuning = not tuning
        if not tuning then dump() end
    end, false)

    CreateThread(function()
        while true do
            if tuning and enabled then
                local step, astep = 0.005, 2.5

                -- position
                if IsControlPressed(0, 174) then attachPos = attachPos - vector3(step, 0, 0) end  -- arrow left
                if IsControlPressed(0, 175) then attachPos = attachPos + vector3(step, 0, 0) end  -- arrow right
                if IsControlPressed(0, 172) then attachPos = attachPos + vector3(0, step, 0) end  -- arrow up
                if IsControlPressed(0, 173) then attachPos = attachPos - vector3(0, step, 0) end  -- arrow down
                if IsControlPressed(0, 44)  then attachPos = attachPos + vector3(0, 0, step) end  -- Q
                if IsControlPressed(0, 38)  then attachPos = attachPos - vector3(0, 0, step) end  -- E

                -- rotation
                if IsControlPressed(0, 45)  then attachRot = attachRot + vector3(astep, 0, 0) end -- R
                if IsControlPressed(0, 23)  then attachRot = attachRot - vector3(astep, 0, 0) end -- F
                if IsControlPressed(0, 20)  then attachRot = attachRot + vector3(0, astep, 0) end -- Z
                if IsControlPressed(0, 26)  then attachRot = attachRot - vector3(0, astep, 0) end -- C
                if IsControlPressed(0, 47)  then attachRot = attachRot + vector3(0, 0, astep) end -- G
                if IsControlPressed(0, 29)  then attachRot = attachRot - vector3(0, 0, astep) end -- B

                -- flip the barrel 180 in one press, the usual "holding it
                -- backwards" fix
                if IsControlJustPressed(0, 182) then                                             -- L
                    attachRot = attachRot + vector3(0, 0, 180.0)
                end

                if IsControlJustPressed(0, 201) then dump() end                                  -- Enter

                reattach()

                line('~y~DUAL WIELD TUNER~s~   /dwtune to finish', 0.30)
                line(('pos  %.3f  %.3f  %.3f'):format(attachPos.x, attachPos.y, attachPos.z), 0.335)
                line(('rot  %.1f  %.1f  %.1f'):format(attachRot.x, attachRot.y, attachRot.z), 0.365)
                line('arrows = left/right, fwd/back   Q/E = up/down', 0.40)
                line('R/F = pitch   Z/C = roll   G/B = yaw', 0.425)
                line('~g~L~s~ = flip barrel 180   ~g~ENTER~s~ = print values', 0.45)
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end
