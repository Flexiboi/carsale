local logger = require '@qbx_core.modules.logger'
local VEHICLES = GetVehiclesByName()
local locationsFile = 'data/locations.json'
local SavedLocations = {}

local function logEvent(eventType, src, data)
    if not SV_Config.webhook or SV_Config.webhook == '' then return end
    local player = GetPlayer(src)
    local playerName = player and player.PlayerData and player.PlayerData.charinfo and (player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname) or 'Unknown'
    local citizenid = player and player.PlayerData and player.PlayerData.citizenid or 'N/A'

    local logMessage = ''

    if eventType == 'add_location' then
        logMessage = ('Admin %s (CID: %s) added location: %s (Label: %s, Radius: %s)'):format(playerName, citizenid, data.locationId, data.label, data.radius)
    elseif eventType == 'remove_location' then
        logMessage = ('Admin %s (CID: %s) removed location: %s'):format(playerName, citizenid, data.locationId)
    elseif eventType == 'add_spot' then
        logMessage = ('Admin %s (CID: %s) added spot #%s to location: %s'):format(playerName, citizenid, data.spotId, data.locationId)
    elseif eventType == 'remove_spot' then
        logMessage = ('Admin %s (CID: %s) removed spot #%s from location: %s'):format(playerName, citizenid, data.spotId, data.locationId)
    elseif eventType == 'vehicleListed' then
        logMessage = ('Vehicle listed for sale - Plate: %s, Model: %s, Price: %s, Seller: %s (CID: %s), Location: %s, Spot: %s'):format(
            data.plate, data.model, data.price, playerName, citizenid, data.location, data.spotId)
    elseif eventType == 'vehicleBought' then
        logMessage = ('Vehicle purchased - Plate: %s, Model: %s, Price: %s, Buyer: %s (CID: %s), Seller CID: %s, Location: %s'):format(
            data.plate, data.model, data.price, playerName, citizenid, data.sellerCid, data.location)
    end

    logger.log({
        source = src,
        event = 'flex_carsale',
        message = logMessage,
        webhook = SV_Config.webhook,
        color = 'orange',
        tags = {},
    })
    if Config.Debug then
        print(('[flex_carsale] %s'):format(logMessage))
    end
end

local function generateOID()
    local num = math.random(1, 10) .. math.random(111, 999)
    return 'OC' .. num
end

local function serializeLocations(locations)
    local result = {}

    for locationId, locationData in pairs(locations or {}) do
        local saleSpots = {}
        for spotId, spot in pairs(locationData.saleSpots or {}) do
            saleSpots[tostring(spotId)] = {
                x = spot.x,
                y = spot.y,
                z = spot.z,
                w = spot.w,
            }
        end

        result[locationId] = {
            label = locationData.label,
            sellRadius = locationData.sellRadius,
            sellPoint = {
                x = locationData.sellPoint.x,
                y = locationData.sellPoint.y,
                z = locationData.sellPoint.z,
            },
            saleSpots = saleSpots,
        }
    end

    return result
end

local function applySavedLocationsToConfig()
    local locations = {}

    for locationId, locationData in pairs(SavedLocations or {}) do
        if locationData.sellPoint then
            local saleSpots = {}
            for spotId, spot in pairs(locationData.saleSpots or {}) do
                saleSpots[tonumber(spotId)] = vector4(spot.x, spot.y, spot.z, spot.w)
            end

            locations[locationId] = {
                label = locationData.label or locationId,
                sellPoint = vector3(locationData.sellPoint.x, locationData.sellPoint.y, locationData.sellPoint.z),
                sellRadius = tonumber(locationData.sellRadius) or 50.0,
                saleSpots = saleSpots,
            }
        end
    end

    Config.Locations = locations
end

local function saveLocations()
    SaveResourceFile(GetCurrentResourceName(), locationsFile, json.encode(SavedLocations), -1)
end

local function loadLocations()
    local raw = LoadResourceFile(GetCurrentResourceName(), locationsFile)
    if not raw or raw == '' then
        SavedLocations = serializeLocations(Config.Locations)
        saveLocations()
        applySavedLocationsToConfig()
        return
    end

    local decoded = json.decode(raw)
    SavedLocations = type(decoded) == 'table' and decoded or {}
    applySavedLocationsToConfig()
end

local function isAdmin(src)
    return HasPermission(src)
end

local function serializeLocationsForClient()
    return SavedLocations
end

local function getFreeSpotInLocation(locationId)
    local locationData = Config.Locations and Config.Locations[locationId]
    if not locationData or not locationData.saleSpots then return nil end

    local result = MySQL.query.await('SELECT spotid FROM occasion_vehicles WHERE location = ? AND spotid IS NOT NULL ORDER BY spotid ASC', { locationId })
    local usedSpots = {}
    for i = 1, #result do
        usedSpots[result[i].spotid] = true
    end

    for spotId in pairs(locationData.saleSpots) do
        if not usedSpots[spotId] then
            return spotId
        end
    end

    return nil
end

local function findFallbackLocationSpot(preferredLocation)
    if preferredLocation then
        local preferredSpot = getFreeSpotInLocation(preferredLocation)
        if preferredSpot then
            return preferredLocation, preferredSpot
        end
    end

    for locationId in pairs(Config.Locations or {}) do
        if locationId ~= preferredLocation then
            local freeSpot = getFreeSpotInLocation(locationId)
            if freeSpot then
                return locationId, freeSpot
            end
        end
    end

    return nil, nil
end

loadLocations()

lib.callback.register('flex_carsale:server:CheckModelName', function(_, plate)
    if plate then
        local result = MySQL.query.await('SELECT * FROM player_vehicles WHERE plate = ?', {plate})
        if result[1] then
            return result[1].vehicle
        end
    end
end)

lib.callback.register('flex_carsale:server:GetVehicles', function()
    local vehiclesWithoutSpot = MySQL.query.await('SELECT id, location FROM occasion_vehicles WHERE spotid IS NULL')
    if vehiclesWithoutSpot and vehiclesWithoutSpot[1] then
        for i = 1, #vehiclesWithoutSpot do
            local row = vehiclesWithoutSpot[i]
            local resolvedLocation, resolvedSpot = findFallbackLocationSpot(row.location or Config.DefaultLocation)
            if resolvedLocation and resolvedSpot then
                MySQL.update.await('UPDATE occasion_vehicles SET location = ?, spotid = ? WHERE id = ?', {
                    resolvedLocation,
                    resolvedSpot,
                    row.id
                })
            end
        end
    end

    local result = MySQL.query.await('SELECT * FROM occasion_vehicles ORDER BY location, spotid')
    if result[1] then
        return result
    end
end)

lib.callback.register('flex_carsale:server:isAdmin', function(src)
    return isAdmin(src)
end)

lib.callback.register('flex_carsale:server:addSaleSpot', function(src, locationId, coords)
    if not isAdmin(src) then return false, 'no_permission' end
    if not SavedLocations[locationId] or not coords then return false, 'invalid_data' end

    local maxSpot = 0
    for spotId in pairs(SavedLocations[locationId].saleSpots or {}) do
        local numericSpot = tonumber(spotId) or 0
        if numericSpot > maxSpot then maxSpot = numericSpot end
    end

    local nextSpotId = maxSpot + 1
    SavedLocations[locationId].saleSpots = SavedLocations[locationId].saleSpots or {}
    SavedLocations[locationId].saleSpots[tostring(nextSpotId)] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = coords.w,
    }

    saveLocations()
    applySavedLocationsToConfig()
    TriggerClientEvent('flex_carsale:client:syncLocations', -1, serializeLocationsForClient())
    TriggerClientEvent('flex_carsale:client:refreshVehicles', -1)
    TriggerClientEvent('flex_carsale:client:syncLocations', -1, serializeLocationsForClient())

    logEvent('add_spot', src, {locationId = locationId, spotId = nextSpotId})
    return true, nextSpotId
end)

lib.callback.register('flex_carsale:server:addLocation', function(src, locationId, label, radius, sellPoint)
    if not isAdmin(src) then return false, 'no_permission' end
    if not locationId or locationId == '' or not sellPoint then return false, 'invalid_data' end
    if SavedLocations[locationId] then return false, 'already_exists' end

    SavedLocations[locationId] = {
        label = (label and label ~= '' and label) or locationId,
        sellRadius = tonumber(radius) or 50.0,
        sellPoint = {
            x = sellPoint.x,
            y = sellPoint.y,
            z = sellPoint.z,
        },
        saleSpots = {}
    }

    if not Config.DefaultLocation then
        Config.DefaultLocation = locationId
    end

    saveLocations()
    applySavedLocationsToConfig()
    TriggerClientEvent('flex_carsale:client:syncLocations', -1, serializeLocationsForClient())
    TriggerClientEvent('flex_carsale:client:refreshVehicles', -1)

    logEvent('add_location', src, {locationId = locationId, label = label, radius = radius})
    return true
end)

lib.callback.register('flex_carsale:server:getLocations', function()
    return serializeLocationsForClient()
end)

lib.callback.register('flex_carsale:server:removeSaleSpot', function(src, locationId, spotId)
    if not isAdmin(src) then return false, 'no_permission' end
    if not SavedLocations[locationId] or not SavedLocations[locationId].saleSpots then return false, 'invalid_data' end

    local spotKey = tostring(spotId)
    if not SavedLocations[locationId].saleSpots[spotKey] then return false, 'spot_not_found' end

    SavedLocations[locationId].saleSpots[spotKey] = nil

    saveLocations()
    applySavedLocationsToConfig()
    TriggerClientEvent('flex_carsale:client:syncLocations', -1, serializeLocationsForClient())
    TriggerClientEvent('flex_carsale:client:refreshVehicles', -1)

    logEvent('remove_spot', src, {locationId = locationId, spotId = spotId})
    return true
end)

lib.callback.register('flex_carsale:server:removeLocation', function(src, locationId)
    if not isAdmin(src) then return false, 'no_permission' end
    if not SavedLocations[locationId] then return false, 'location_not_found' end

    SavedLocations[locationId] = nil

    if Config.DefaultLocation == locationId then
        local firstLocation = next(SavedLocations)
        Config.DefaultLocation = firstLocation
    end

    saveLocations()
    applySavedLocationsToConfig()
    TriggerClientEvent('flex_carsale:client:syncLocations', -1, serializeLocationsForClient())
    TriggerClientEvent('flex_carsale:client:refreshVehicles', -1)

    logEvent('remove_location', src, {locationId = locationId})
    return true
end)

lib.callback.register('flex_carsale:server:getDynamicSaleSpots', function()
    return serializeLocationsForClient()
end)

-- backwards compatibility event kept for older client listeners
RegisterNetEvent('flex_carsale:server:legacySyncRequest', function()
    TriggerClientEvent('flex_carsale:client:syncLocations', source, serializeLocationsForClient())
end)

-- removed old dynamic spot-only persistence in favor of full locations JSON
-- keep this block intentionally empty for stable patch positioning
do
    -- noop
end

lib.callback.register('flex_carsale:server:CanSellOwnedVehicle', function(src, plate)
    if not plate or plate == '' then return false end

    local player = GetPlayer(src)
    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        return false
    end

    local result = MySQL.single.await('SELECT plate FROM player_vehicles WHERE citizenid = ? AND plate = ? LIMIT 1', {
        player.PlayerData.citizenid,
        plate
    })

    return result ~= nil
end)

lib.callback.register('flex_carsale:server:sellVehicle', function(src, vehiclePrice, vehicleData)
    local player = GetPlayer(src)
    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        return false
    end

    if not vehicleData or not vehicleData.plate or not vehicleData.model then
        return false
    end

    local ownsVehicle = MySQL.single.await('SELECT plate FROM player_vehicles WHERE citizenid = ? AND plate = ? LIMIT 1', {
        player.PlayerData.citizenid,
        vehicleData.plate
    })
    if not ownsVehicle then
        return false
    end

    local preferredLocation = vehicleData.location or Config.DefaultLocation
    local locationId, nextSpotId = findFallbackLocationSpot(preferredLocation)
    if not locationId or not nextSpotId then
        return false
    end

    if locationId ~= preferredLocation then
        Config.Notify.server(src, locale('error.no_free_spot_in_location'), 'error', 3500)
    end

    local deletedRows = MySQL.update.await('DELETE FROM player_vehicles WHERE citizenid = ? AND plate = ? AND vehicle = ?', {
        player.PlayerData.citizenid,
        vehicleData.plate,
        vehicleData.model
    })
    if not deletedRows or deletedRows < 1 then
        return false
    end

    local insertId = MySQL.insert.await('INSERT INTO occasion_vehicles (seller, price, description, plate, model, mods, occasionid, location, spotid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        player.PlayerData.citizenid,
        vehiclePrice,
        vehicleData.desc,
        vehicleData.plate,
        vehicleData.model,
        json.encode(vehicleData.mods),
        generateOID(),
        locationId,
        nextSpotId
    })

    if not insertId then
        MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            player.PlayerData.license,
            player.PlayerData.citizenid,
            vehicleData.model,
            GetHashKey(vehicleData.model),
            json.encode(vehicleData.mods),
            vehicleData.plate,
            0
        })
        return false
    end

    TriggerClientEvent('flex_carsale:client:refreshVehicles', -1)

    logEvent('vehicleListed', src, {
        plate = vehicleData.plate,
        model = vehicleData.model,
        price = vehiclePrice,
        location = locationId,
        spotId = nextSpotId
    })
    return true
end)

lib.callback.register('flex_carsale:server:buyVehicle', function(src, vehicleData)
    local player = GetPlayer(src)
    local result = MySQL.query.await('SELECT * FROM occasion_vehicles WHERE plate = ? AND occasionid = ? AND location = ?',{vehicleData.plate, vehicleData.oid, vehicleData.location or Config.DefaultLocation})
    if not result[1] or not next(result[1]) then return false end
    if GetPlayerBankMoney(player) < result[1].price then
        Notify(src, locale('error.not_enough_money'), 'error', 3500)
        return false
    end

    local sellerCitizenId = result[1].seller
    local sellerData = GetPlayerByCitizenId(sellerCitizenId)
    local newPrice = math.ceil((result[1].price / 100) * 77)
    RemoveMoney(player, 'bank', result[1].price)
    MySQL.insert(
        'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            player.PlayerData.license,
            player.PlayerData.citizenid, result[1].model,
            GetHashKey(result[1].model),
            result[1].mods,
            result[1].plate,
            0
        })
    if sellerData then
        AddMoneyToPlayer(sellerData, 'bank', newPrice)
    else
        local buyerData = MySQL.query.await('SELECT * FROM players WHERE citizenid = ?',{sellerCitizenId})
        if buyerData[1] then
            local buyerMoney = json.decode(buyerData[1].money)
            buyerMoney.bank = buyerMoney.bank + newPrice
            MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(buyerMoney), sellerCitizenId})
        end
    end
    MySQL.query('DELETE FROM occasion_vehicles WHERE plate = ? AND occasionid = ?',{result[1].plate, result[1].occasionid})

    logEvent('vehicleBought', src, {
        plate = result[1].plate,
        model = result[1].model,
        price = result[1].price,
        sellerCitizenId = sellerCitizenId,
        location = vehicleData.location or Config.DefaultLocation
    })

    TriggerClientEvent('flex_carsale:client:refreshVehicles', -1)
    SV_Config.SendMail(src, locale('mail.subject'), (locale('mail.message'):format(newPrice, VEHICLES[result[1].model].name)))

    local locationId = vehicleData.location or Config.DefaultLocation
    local locationData = Config.Locations[locationId]
    local spawnCoords = locationData and locationData.buyVehicle
    
    if not spawnCoords and locationData and locationData.saleSpots and locationData.saleSpots[result[1].spotid] then
        spawnCoords = locationData.saleSpots[result[1].spotid]
    end

    local vehData = {
        model = result[1].model,
        mods = result[1].mods,
        plate = result[1].plate,
        coords = spawnCoords,
        warp = false,
        locationId = locationId,
    }

    TriggerClientEvent('flex_carsale:client:BuyFinished', src, vehData)
    return true
end)

lib.callback.register('flex_carsale:server:spawnVehicle', function(source, vehicle, coords, warp)
    if not vehicle or not vehicle.model then return end

    local vehmods = json.decode(vehicle.mods)
    vehicle.props = vehmods

    local netId = SpawnVehicle(source, {
        model = vehicle.model,
        coords = coords,
        warp = warp,
        props = vehicle.props,
    })

    if not netId then return end

    SetVehicleNumberPlateText(NetworkGetEntityFromNetworkId(netId), vehicle.plate)
    TriggerClientEvent('vehiclekeys:client:SetOwner', source, vehicle.plate)
    return netId
end)
