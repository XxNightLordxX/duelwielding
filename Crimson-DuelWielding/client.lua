-- ============================================================================
--                          CRIMSON - DUEL WIELDING
--                            Authored by John Allday
-- ============================================================================
-- CLIENT. Draws the offhand gun, fires it in time with the mainhand, and tears
-- everything down the moment the player is downed, dead, cuffed, in a vehicle
-- or has switched weapon.
-- ============================================================================

local enabled      = false
local busy         = false   -- a toggle is mid-flight to the server
local activeHash   = nil
local offhandProp  = nil
local remoteProps  = {}      -- [serverId] = prop entity
local remoteWanted = {}      -- [serverId] = weapon name

local BONE = Config.Attach and Config.Attach.bone or 'IK_L_Hand'

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
    if not lib.requestModel(model, 5000) then return nil end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(prop) then return nil end

    SetEntityCollision(prop, false, false)

    local boneIndex = GetEntityBoneIndexByName(ped, BONE)
    if boneIndex == -1 then boneIndex = 0 end   -- invalid index attaches at the centre

    local p, r = Config.Attach.pos, Config.Attach.rot
    AttachEntityToEntity(prop, ped, boneIndex,
        p.x, p.y, p.z,
        r.x, r.y, r.z,
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

    local st = LocalPlayer.state
    if st.isCuffed or st.handcuffed then return true end

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
    local ammo = GetAmmoInPedWeapon(ped, hash)
    local cost = Config.AmmoPerOffhandShot or 1
    if ammo <= cost then return false end

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

    SetPedAmmo(ped, hash, ammo - cost)
    return true
end

-- ----------------------------------------------------------------------------
-- Teardown
-- ----------------------------------------------------------------------------

local function disable(silent)
    if not enabled then return end
    enabled = false

    deleteProp(offhandProp)
    offhandProp = nil
    activeHash = nil

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
    local lastAmmo   = GetAmmoInPedWeapon(cache.ped, activeHash)
    local pendingAt  = 0
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
                    fireOffhand(ped, activeHash)
                end
                pendingAt = 0
                ammo = GetAmmoInPedWeapon(ped, activeHash)
            end

            lastAmmo = ammo
            Wait(0)
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Toggle
-- ----------------------------------------------------------------------------

local function toggle()
    -- The callback below yields for a server round trip. Without this guard,
    -- spamming the command starts a second enable while the first is still in
    -- flight: the first prop handle is overwritten and leaks in the player's
    -- hand, and two firing loops run at once, doubling the offhand rate.
    if busy then return end

    if enabled then
        disable()
        return
    end

    if isBlocked() then
        notify('blocked')
        return
    end

    local weapon = cache.weapon
    if not weapon then return end

    local ok, current = pcall(function() return exports.ox_inventory:getCurrentWeapon() end)
    local name = (ok and type(current) == 'table') and current.name or nil
    if not name then return end

    busy = true
    local allowed, reason = lib.callback.await('crimson_duelwield:toggle', false, name)
    busy = false

    if not allowed then
        notify(reason or 'blocked')
        return
    end

    -- The world can have moved on during the round trip.
    if enabled or isBlocked() or cache.weapon ~= weapon then
        TriggerServerEvent('crimson_duelwield:stop')
        return
    end

    local prop = createOffhandProp(cache.ped, name)
    if not prop then
        -- An invisible offhand that still shoots looks exactly like a cheat.
        -- Fail closed instead.
        TriggerServerEvent('crimson_duelwield:stop')
        notify('blocked')
        return
    end

    enabled     = true
    activeHash  = weapon
    offhandProp = prop

    if Config.UseGangAnimation then
        SetWeaponAnimationOverride(cache.ped, `Gang1H`)
    end

    notify(reason or 'enabled_msg')
    runLoop()
end

if Config.Command then
    RegisterCommand(Config.Command, toggle, false)
    if Config.Keybind then
        RegisterKeyMapping(Config.Command, 'Toggle dual wielding', 'keyboard', Config.Keybind)
    end
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

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    deleteProp(offhandProp)
    for _, prop in pairs(remoteProps) do deleteProp(prop) end
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

        remoteWanted[serverId] = (type(value) == 'string' and value ~= '') and value or nil

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
