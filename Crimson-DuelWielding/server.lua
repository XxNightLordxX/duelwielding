-- ============================================================================
--                          CRIMSON - DUEL WIELDING
--                            Authored by John Allday
-- ============================================================================
-- SERVER. This is the authority.
--
-- The client never names a weapon. It asks "what may I dual wield", gets a list
-- the SERVER built from the player's own inventory, and sends back one slot
-- number from it. Damage, coordinates, weapon hashes, ammo counts and player
-- ids are never accepted from a client, because none of them could be trusted.
-- ============================================================================

local active     = {}   -- [src] = { name = string, slot = number }
local lastAction = {}   -- [src] = GetGameTimer() of last state change

local COOLDOWN_MS = math.floor((Config.ToggleCooldown or 1.0) * 1000)

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

local function currentWeapon(src)
    local ok, cur = pcall(function() return exports.ox_inventory:GetCurrentWeapon(src) end)
    if not ok or type(cur) ~= 'table' then return nil end
    return cur
end

local function allowedNames()
    local names = {}
    for name, on in pairs(Config.AllowedWeapons) do
        if on == true then names[#names + 1] = name end
    end
    return names
end

-- ----------------------------------------------------------------------------
-- Sync. The SERVER is the only writer of this state bag, so other clients can
-- trust its value for rendering.
-- ----------------------------------------------------------------------------

local function setOffhand(src, name, slot)
    active[src] = name and { name = name, slot = slot } or nil
    Player(src).state:set('crimsonDuelWield', name or false, true)
end

local function clear(src)
    if active[src] then setOffhand(src, nil) end
end

-- ----------------------------------------------------------------------------
-- Shared gate for both callbacks. Cheapest and most-rejecting checks first, so
-- flooding either surface costs the server as little as possible.
-- ----------------------------------------------------------------------------

local function gate(src)
    if not src or not DoesPlayerExist(src) then return nil end

    local meta = getMetadata(src)
    if not meta then return nil end                 -- player not loaded yet
    if isBlocked(src, meta) then return nil end

    local cur = currentWeapon(src)
    if not cur or Config.AllowedWeapons[cur.name] ~= true then return nil end

    return cur
end

-- ----------------------------------------------------------------------------
-- READ-ONLY: what can this player dual wield right now?
-- Returns only the caller's own inventory, and only whitelisted one-handed guns
-- that are not the gun already in their hand.
-- ----------------------------------------------------------------------------

lib.callback.register('crimson_duelwield:list', function(source)
    local src = source
    local cur = gate(src)
    if not cur then return { ok = false, reason = 'need_mainhand' } end

    local ok, slots = pcall(function()
        return exports.ox_inventory:Search(src, 'slots', allowedNames())
    end)
    if not ok or type(slots) ~= 'table' then return { ok = false, reason = 'nothing' } end

    local out = {}
    for i = 1, #slots do
        local s = slots[i]
        if type(s) == 'table' and s.slot ~= cur.slot and Config.AllowedWeapons[s.name] == true then
            out[#out + 1] = {
                slot  = s.slot,
                name  = s.name,
                label = (s.label or s.name),
                ammo  = (s.metadata and s.metadata.ammo) or 0,
            }
        end
    end

    return { ok = true, slots = out, activeSlot = active[src] and active[src].slot or nil }
end)

-- ----------------------------------------------------------------------------
-- Pick a slot as the offhand. The ONLY value taken from the client is a slot
-- number, and it is resolved against the caller's own inventory.
-- ----------------------------------------------------------------------------

lib.callback.register('crimson_duelwield:select', function(source, slot)
    local src = source
    if not src or not DoesPlayerExist(src) then return false end

    local now  = GetGameTimer()
    local last = lastAction[src]
    if last and (now - last) < COOLDOWN_MS then return false end
    lastAction[src] = now

    -- Slot must be a real positive integer. A table, float, string, negative or
    -- absurd value never reaches ox_inventory.
    if type(slot) ~= 'number' or slot ~= math.floor(slot) or slot < 1 or slot > 500 then
        return false
    end

    local cur = gate(src)
    if not cur then return false, 'need_mainhand' end
    if slot == cur.slot then return false, 'in_hand' end

    -- Resolved from the PLAYER's inventory only. A slot id cannot reach a
    -- stash, trunk, shop or another player's inventory through this path.
    local ok, item = pcall(function() return exports.ox_inventory:GetSlot(src, slot) end)
    if not ok or type(item) ~= 'table' or not item.name then return false end
    if Config.AllowedWeapons[item.name] ~= true then return false, 'not_allowed' end
    if (item.count or 0) < 1 then return false end

    local ammo = (item.metadata and item.metadata.ammo) or 0
    if ammo < 1 then return false, 'out_of_ammo' end

    setOffhand(src, item.name, slot)
    return true, 'enabled_msg', ammo
end)

-- ----------------------------------------------------------------------------
-- Stop. Carries no arguments, so there is nothing here for a client to lie
-- about, and it can only ever affect the caller.
-- ----------------------------------------------------------------------------

RegisterNetEvent('crimson_duelwield:stop', function()
    local src = source
    if not src or not DoesPlayerExist(src) then return end
    clear(src)
end)

-- ----------------------------------------------------------------------------
-- The server owns the grant, so the server revokes it. A modified client that
-- simply never reports going down, holstering, or dropping the offhand gun
-- would otherwise keep its state bag forever.
-- ----------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(10000)

        local watched = {}
        for src in pairs(active) do watched[#watched + 1] = src end

        for i = 1, #watched do
            local src = watched[i]
            local a = active[src]

            if a then
                local revoke = false

                if not DoesPlayerExist(src) then
                    revoke = true
                else
                    local meta = getMetadata(src)
                    if not meta or isBlocked(src, meta) then
                        revoke = true
                    else
                        local cur = currentWeapon(src)
                        if not cur or Config.AllowedWeapons[cur.name] ~= true or cur.slot == a.slot then
                            revoke = true
                        else
                            -- The offhand gun must still be in the slot it was
                            -- claimed from: it can be dropped, sold or moved.
                            local ok, item = pcall(function() return exports.ox_inventory:GetSlot(src, a.slot) end)
                            if not ok or type(item) ~= 'table' or item.name ~= a.name then
                                revoke = true
                            end
                        end
                    end
                end

                if revoke then
                    if DoesPlayerExist(src) then
                        clear(src)
                        TriggerClientEvent('crimson_duelwield:revoke', src)
                    else
                        active[src] = nil
                    end
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Cleanup. Unbounded per-player tables are a slow memory-exhaustion DoS, and
-- stale entries can leak onto a recycled server id.
-- ----------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    active[src]     = nil
    lastAction[src] = nil
end)

CreateThread(function()
    while true do
        Wait(600000)
        local seen = {}
        for src in pairs(lastAction) do seen[#seen + 1] = src end
        for i = 1, #seen do
            local src = seen[i]
            if not DoesPlayerExist(src) then
                active[src]     = nil
                lastAction[src] = nil
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
    for src in pairs(active) do
        if DoesPlayerExist(src) then
            Player(src).state:set('crimsonDuelWield', false, true)
        end
    end
end)

-- Read-only helper for other resources (exports are not reachable from clients).
exports('IsDualWielding', function(playerId)
    return active[playerId] ~= nil
end)

exports('GetOffhandWeapon', function(playerId)
    local a = active[playerId]
    return a and a.name or nil
end)
