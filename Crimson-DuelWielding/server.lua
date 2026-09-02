-- ============================================================================
--                          CRIMSON - DUEL WIELDING
--                            Authored by John Allday
-- ============================================================================
-- SERVER. This is the authority. The client may only ever ask "may I akimbo
-- this weapon" and is told yes or no. It never sends damage, coordinates, a
-- weapon hash, an ammo count or a player id, because none of those would be
-- trustworthy.
-- ============================================================================

local activeWeapon = {}   -- [src] = weapon name currently akimbo
local lastToggle   = {}   -- [src] = GetGameTimer() of last toggle

local COOLDOWN_MS = math.floor((Config.ToggleCooldown or 1.0) * 1000)
local MAX_NAME_LEN = 48

-- ----------------------------------------------------------------------------
-- Input scrubbing
-- ----------------------------------------------------------------------------
-- A client can send tables, multi-megabyte strings, NaN, nil, or the wrong
-- number of arguments. Bound the length BEFORE doing any other string work,
-- and never recurse into a client-supplied table.

local function scrubWeaponName(v)
    if type(v) ~= 'string' then return nil end
    if #v == 0 or #v > MAX_NAME_LEN then return nil end
    if v:find('[^%w_]') then return nil end     -- charset, so it can never be a Lua pattern
    return v:upper()
end

-- ----------------------------------------------------------------------------
-- Player state
-- ----------------------------------------------------------------------------

local function getMetadata(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if not ok or not player then return nil end
    local pd = player.PlayerData
    return pd and pd.metadata or nil
end

-- Dead / downed / cuffed.
--
-- IMPORTANT: do NOT use ped health for this. sc-ambulance resurrects the ped
-- and restores full health while the player is lying "dead", so any health or
-- IsEntityDead style check reports a perfectly healthy player. The authority is
-- player metadata, which the server owns.
local function isBlocked(src, meta)
    if meta and (meta.isdead or meta.inlaststand or meta.ishandcuffed) then
        return true
    end

    if GetResourceState('sc-ambulance') == 'started' then
        local ok, dead = pcall(function() return exports['sc-ambulance']:IsDead(src) end)
        if ok and dead then return true end

        local ok2, down = pcall(function() return exports['sc-ambulance']:IsLaststand(src) end)
        if ok2 and down then return true end
    end

    return false
end

-- Confirm the player is really holding this weapon, and really owns enough of
-- them. Derived from ox_inventory server-side; the client's claim is ignored.
local function ownsWeapon(src, name)
    local ok, current = pcall(function() return exports.ox_inventory:GetCurrentWeapon(src) end)
    if not ok or type(current) ~= 'table' then return false, 'blocked' end
    if current.name ~= name then return false, 'blocked' end

    if Config.RequireTwoWeapons then
        local ok2, count = pcall(function() return exports.ox_inventory:Search(src, 'count', name) end)
        if not ok2 or type(count) ~= 'number' or count < 2 then
            return false, 'need_two'
        end
    end

    return true
end

-- ----------------------------------------------------------------------------
-- Sync. The SERVER is the only writer of this state bag, so other clients can
-- trust it for rendering. A client writing its own bag would not replicate the
-- key we read here.
-- ----------------------------------------------------------------------------

local function setAkimbo(src, name)
    activeWeapon[src] = name
    Player(src).state:set('crimsonDuelWield', name or false, true)
end

-- ----------------------------------------------------------------------------
-- The single client-facing surface.
-- Checks are ordered cheapest-and-most-rejecting first, so that flooding this
-- callback costs the server as little as possible.
-- ----------------------------------------------------------------------------

lib.callback.register('crimson_duelwield:toggle', function(source, weaponName)
    local src = source          -- captured before any yield; never read `source` again

    if not src or not DoesPlayerExist(src) then return false end

    -- Already on? Turn it off. This returns FALSE deliberately: the reply means
    -- "you are not dual wielding now". Returning true here would read to the
    -- client as permission to enable, and it would enable while the server had
    -- just switched akimbo off.
    if activeWeapon[src] then
        setAkimbo(src, nil)
        lastToggle[src] = GetGameTimer()
        return false, 'disabled_msg'
    end

    local now  = GetGameTimer()
    local last = lastToggle[src]
    if last and (now - last) < COOLDOWN_MS then return false end
    lastToggle[src] = now

    local name = scrubWeaponName(weaponName)
    if not name then return false end

    if Config.AllowedWeapons[name] ~= true then return false, 'not_allowed' end

    local meta = getMetadata(src)
    if not meta then return false end               -- player not loaded yet
    if isBlocked(src, meta) then return false, 'blocked' end

    local allowed, reason = ownsWeapon(src, name)
    if not allowed then return false, reason end

    setAkimbo(src, name)
    return true, 'enabled_msg'
end)

-- ----------------------------------------------------------------------------
-- Forced shutdown, used by the client when it detects death, downed, cuffed,
-- a weapon switch, or a vehicle. Carries no arguments at all, so there is
-- nothing here for a client to lie about.
-- ----------------------------------------------------------------------------

RegisterNetEvent('crimson_duelwield:stop', function()
    local src = source
    if not src or not DoesPlayerExist(src) then return end
    if activeWeapon[src] then setAkimbo(src, nil) end
end)

-- ----------------------------------------------------------------------------
-- Cleanup. Unbounded per-player tables are a slow memory-exhaustion DoS, and
-- stale entries can leak onto a recycled server id.
-- ----------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    activeWeapon[src] = nil
    lastToggle[src]   = nil
end)

CreateThread(function()
    while true do
        Wait(600000)
        for src in pairs(lastToggle) do
            if not DoesPlayerExist(src) then
                activeWeapon[src] = nil
                lastToggle[src]   = nil
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Revalidation.
-- ----------------------------------------------------------------------------
-- Every teardown path above is client-initiated, so a modified client that
-- simply never sends the stop event would keep its grant -- and the replicated
-- bag that renders its offhand gun on every other player's screen -- through
-- death, laststand and cuffing. The server therefore re-checks its own grants.

local function revoke(src)
    setAkimbo(src, nil)
    TriggerClientEvent('crimson_duelwield:revoke', src)
end

CreateThread(function()
    while true do
        Wait(5000)

        -- Snapshot the keys: clearing entries while iterating the live table is
        -- undefined behaviour in Lua and would wedge this loop permanently.
        local ids = {}
        for src in pairs(activeWeapon) do ids[#ids + 1] = src end

        for i = 1, #ids do
            local src = ids[i]
            local name = activeWeapon[src]      -- may have been cleared mid-sweep

            if name then
                if not DoesPlayerExist(src) then
                    activeWeapon[src] = nil
                    lastToggle[src]   = nil
                else
                    local meta = getMetadata(src)
                    if not meta or isBlocked(src, meta) or not ownsWeapon(src, name) then
                        revoke(src)
                    end
                end
            end
        end
    end
end)

-- A replicated state bag outlives this resource. If the server stops with
-- players still akimbo, their bag keeps saying so, and change handlers only
-- fire on change -- so the value would never be corrected. Clear it on the way
-- out.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(activeWeapon) do
        if DoesPlayerExist(src) then
            Player(src).state:set('crimsonDuelWield', false, true)
        end
    end
end)

-- Read-only helper for other resources (exports are not reachable from clients).
exports('IsDualWielding', function(playerId)
    return activeWeapon[playerId] ~= nil
end)
