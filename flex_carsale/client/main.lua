local SpotData, Points = {}, {}
local SellPoints = {}
local thisResource = GetCurrentResourceName()
local width, height = 1024, 512
local txdBaseName, txnBaseName = "flex_dui_txd_", "flex_dui_txn_"
local duiRenderIntervalMs = 33
local SavedLocations = {}
local refreshVehicles

local function makeSpotKey(locationId, spotId)
    return ('%s:%s'):format(locationId, spotId)
end

local UpgradeLabels = {
    modEngine = locale('info.engine_upgrade'),
    modBrakes = locale('info.brakes_upgrade'),
    modTransmission = locale('info.transmission_upgrade'),
    modSuspension = locale('info.suspension_upgrade'),
    modArmor = locale('info.armor_upgrade'),
    modTurbo = locale('info.turbo_upgrade'),
    modNitrous = locale('info.nitrous_upgrade'),
}

local UpgradeOrder = {
    'modEngine',
    'modBrakes',
    'modTransmission',
    'modSuspension',
    'modArmor',
    'modTurbo',
    'modNitrous',
}

local function buildUpgradeOptions(mods, saleDescription)
    local options = {}

    if saleDescription and saleDescription ~= '' then
        options[#options + 1] = {
            title = locale('info.vehicle_description_title'),
            description = saleDescription,
            icon = 'file-lines'
        }
    end

    for i = 1, #UpgradeOrder do
        local key = UpgradeOrder[i]
        local value = mods[key]

        if type(value) == 'number' and value > -1 then
            options[#options + 1] = {
                title = UpgradeLabels[key],
                description = locale('info.upgrade_level', value + 1),
                icon = 'wrench'
            }
        elseif type(value) == 'boolean' and value then
            options[#options + 1] = {
                title = UpgradeLabels[key],
                description = locale('info.installed'),
                icon = 'wrench'
            }
        end
    end

    if #options == 0 then
        options[1] = {
            title = locale('info.no_performance_upgrades_title'),
            description = locale('info.no_performance_upgrades_description'),
            icon = 'circle-info'
        }
    end

    return options
end

local function getClosestLocation()
    local pedCoords = GetEntityCoords(cache.ped)
    local closestId, closestDist

    for locationId, locationData in pairs(Config.Locations or {}) do
        local sellPoint = locationData.sellPoint
        if sellPoint then
            local distance = #(pedCoords - sellPoint)
            if not closestDist or distance < closestDist then
                closestDist = distance
                closestId = locationId
            end
        end
    end

    return closestId, closestDist
end

local function openSellVehicleMenu(locationId)
    if not IsPedInAnyVehicle(cache.ped, false) then
        Config.Notify.client(locale('error.must_be_in_vehicle'), 'error', 3000)
        return
    end

    local vehicle = GetVehiclePedIsIn(cache.ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then
        Config.Notify.client(locale('error.must_be_driver'), 'error', 3000)
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local ownsVehicle = lib.callback.await('flex_carsale:server:CanSellOwnedVehicle', false, plate)
    if not ownsVehicle then
        Config.Notify.client(locale('error.not_vehicle_owner'), 'error', 3500)
        return
    end

    -- Check location details for job requirements
    local locationData = Config.Locations[locationId]
    local helpText = ''
    if locationData and locationData.jobName and locationData.jobName ~= '' then
        local commission = locationData.commission or 0
        helpText = ('This location requires job: %s with %d%% commission'):format(locationData.jobName, commission)
    end

    local input = lib.inputDialog(locale('info.sell_menu_title'), {
        {
            type = 'number',
            label = locale('info.sell_price_label'),
            description = helpText,
            min = 1,
            required = true,
        },
        {
            type = 'textarea',
            label = locale('info.sell_description_label'),
            required = false,
            max = 300,
        }
    })

    if not input then return end

    local amount = tonumber(input[1])
    if not amount or amount <= 0 then
        Config.Notify.client(locale('error.invalid_sell_price'), 'error', 3000)
        return
    end

    -- Calculate and show final price with commission
    local finalPrice = amount
    if locationData and locationData.commission and locationData.commission > 0 then
        local commission = locationData.commission
        finalPrice = amount + math.ceil((amount / 100) * commission)
        Config.Notify.client(('Base: $%d | Commission: %d%% ($%d) | Listing: $%d'):format(
            amount, 
            commission,
            math.ceil((amount / 100) * commission),
            finalPrice
        ), 'info', 4000)
    end

    TriggerEvent('flex_carsale:client:sellVehicle', amount, input[2], locationId)
end

local function clearSellPoints()
    for _, point in pairs(SellPoints) do
        if point.ped and DoesEntityExist(point.ped) then
            DeleteEntity(point.ped)
        end

        if point.hasTextUi then
            lib.hideTextUI()
            point.hasTextUi = false
        end

        point:remove()
    end

    SellPoints = {}
end

local function createSellPoints()
    if not Config.SellInteraction or not Config.SellInteraction.enabled then return end

    clearSellPoints()

    for locationId, locationData in pairs(Config.Locations or {}) do
        if locationData.sellPoint then
            local point = lib.points.new({
                coords = locationData.sellPoint,
                distance = math.max((locationData.sellRadius or 50.0), 10.0)
            })

            point.locationId = locationId
            point.locationData = locationData
            point.ped = nil
            point.hasTextUi = false

            function point:onEnter()
                local pedModel = Config.SellInteraction.ped and Config.SellInteraction.ped.model or 'a_m_m_business_01'
                lib.requestModel(pedModel)
                self.ped = CreatePed(4, joaat(pedModel), self.locationData.sellPoint.x, self.locationData.sellPoint.y, self.locationData.sellPoint.z - 1.0, 0.0, false, true)
                SetEntityAsMissionEntity(self.ped, true, true)
                SetEntityInvincible(self.ped, true)
                FreezeEntityPosition(self.ped, true)
                SetBlockingOfNonTemporaryEvents(self.ped, true)

                if Config.SellInteraction.ped and Config.SellInteraction.ped.scenario then
                    TaskStartScenarioInPlace(self.ped, Config.SellInteraction.ped.scenario, 0, true)
                end
            end

            function point:nearby()
                if self.currentDistance <= 2.0 then
                    if not self.hasTextUi then
                        lib.showTextUI(locale('info.press_e_to_sell'))
                        self.hasTextUi = true
                    end

                    if IsControlJustReleased(0, Config.SellInteraction.key or 38) then
                        openSellVehicleMenu(self.locationId)
                    end
                elseif self.hasTextUi then
                    lib.hideTextUI()
                    self.hasTextUi = false
                end
            end

            function point:onExit()
                if self.hasTextUi then
                    lib.hideTextUI()
                    self.hasTextUi = false
                end

                if self.ped and DoesEntityExist(self.ped) then
                    DeleteEntity(self.ped)
                    self.ped = nil
                end
            end

            SellPoints[locationId] = point
        end
    end
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

local function openAddSaleSpotMenu()
    local isAdmin = lib.callback.await('flex_carsale:server:isAdmin', false)
    if not isAdmin then
        Config.Notify.client(locale('error.no_permission'), 'error', 3500)
        return
    end

    local locationOptions = {}
    for locationId, locationData in pairs(Config.Locations or {}) do
        locationOptions[#locationOptions + 1] = {
            value = locationId,
            label = locationData.label or locationId
        }
    end

    if #locationOptions == 0 then
        Config.Notify.client(locale('error.no_sales_location_nearby'), 'error', 3500)
        return
    end

    local input = lib.inputDialog(locale('info.add_sale_spot_title'), {
        {
            type = 'select',
            label = locale('info.add_sale_spot_location'),
            options = locationOptions,
            required = true
        }
    })

    if not input or not input[1] then return end

    local locationId = input[1]
    local pedCoords = GetEntityCoords(cache.ped)
    local heading = GetEntityHeading(cache.ped)
    local success, spotId = lib.callback.await('flex_carsale:server:addSaleSpot', false, locationId, {
        x = pedCoords.x,
        y = pedCoords.y,
        z = pedCoords.z,
        w = heading,
    })

    if not success then
        if spotId == 'no_job' then
            local locationData = Config.Locations[locationId]
            local jobRequired = locationData and locationData.jobName or 'unknown'
            Config.Notify.client(('You must have the %s job to add spots here'):format(jobRequired), 'error', 3500)
        else
            Config.Notify.client(locale('error.failed_to_add_sale_spot'), 'error', 3500)
        end
        return
    end

    Config.Notify.client(locale('success.added_sale_spot', spotId, input[1]), 'success', 3500)
    if refreshVehicles then
        refreshVehicles()
    end
end

local function openAddLocationMenu()
    local isAdmin = lib.callback.await('flex_carsale:server:isAdmin', false)
    if not isAdmin then
        Config.Notify.client(locale('error.no_permission'), 'error', 3500)
        return
    end

    local input = lib.inputDialog(locale('info.add_location_title'), {
        {
            type = 'input',
            label = locale('info.add_location_id'),
            required = true,
            placeholder = 'e.g. city'
        },
        {
            type = 'input',
            label = locale('info.add_location_label'),
            required = false,
            placeholder = 'e.g. City PDM'
        },
        {
            type = 'input',
            label = locale('info.add_location_radius'),
            default = '50',
            required = true,
        },
        {
            type = 'input',
            label = 'Job Name (optional)',
            required = false,
            placeholder = 'e.g. cardealer'
        },
        {
            type = 'input',
            label = 'Commission % (optional)',
            required = false,
            placeholder = 'e.g. 15',
            default = '0'
        }
    })

    if not input or not input[1] then return end

    local locationId = tostring(input[1]):lower():gsub('%s+', '_')
    local label = input[2] and input[2] ~= '' and input[2] or input[1]
    local radius = tonumber(input[3]) or 50
    local jobName = input[4] and input[4] ~= '' and input[4] or nil
    local commission = input[5] and tonumber(input[5]) or 0

    local pedCoords = GetEntityCoords(cache.ped)

    local success = lib.callback.await('flex_carsale:server:addLocation', false, locationId, label, radius, {
        x = pedCoords.x,
        y = pedCoords.y,
        z = pedCoords.z,
    }, jobName, commission)

    if not success then
        Config.Notify.client(locale('error.failed_to_add_location'), 'error', 3500)
        return
    end

    Config.Notify.client(locale('success.added_location', label), 'success', 3500)
    createSellPoints()
    if refreshVehicles then
        refreshVehicles()
    end
end

local function destroyDui(id)
    if SpotData[id] then
        if SpotData[id].duiObject then DestroyDui(SpotData[id].duiObject) end
        SpotData[id].duiObject = nil
        SpotData[id].duiHandle = nil
        SpotData[id].visible = false
    end
end

local function createDui(id)
    if SpotData[id] and SpotData[id].duiObject then return end

    local duiUrl = ("nui://%s/ui/index.html"):format(thisResource)
    local duiObject = CreateDui(duiUrl, width, height)
    local duiHandle = nil

    local timeout = GetGameTimer() + 3000
    while (not duiHandle or duiHandle == 0) and GetGameTimer() < timeout do
        duiHandle = GetDuiHandle(duiObject)
        Wait(0)
    end

    if not duiHandle or duiHandle == 0 then 
        DestroyDui(duiObject)
        return 
    end

    local txdName = txdBaseName .. id
    local txnName = txnBaseName .. id

    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, txnName, duiHandle)

    SpotData[id] = {
        duiObject = duiObject,
        duiHandle = duiHandle,
        txdName = txdName,
        txnName = txnName,
        visible = false
    }
    return SpotData[id], id
end

local function renderDuiOnWindshield(vehicle, data, offsets)
    if not data or not data.duiHandle or not offsets then return end
    local p1 = GetOffsetFromEntityInWorldCoords(vehicle, offsets.p1.x, offsets.p1.y, offsets.p1.z)
    local p2 = GetOffsetFromEntityInWorldCoords(vehicle, offsets.p2.x, offsets.p2.y, offsets.p2.z)
    local p3 = GetOffsetFromEntityInWorldCoords(vehicle, offsets.p3.x, offsets.p3.y, offsets.p3.z)
    local p4 = GetOffsetFromEntityInWorldCoords(vehicle, offsets.p4.x, offsets.p4.y, offsets.p4.z)
    DrawSpritePoly(p1.x, p1.y, p1.z, p3.x, p3.y, p3.z, p2.x, p2.y, p2.z, 255, 255, 255, 255, data.txdName, data.txnName, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
    DrawSpritePoly(p3.x, p3.y, p3.z, p1.x, p1.y, p1.z, p4.x, p4.y, p4.z, 255, 255, 255, 255, data.txdName, data.txnName, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0)
end

local function getBestWindshieldOffsets(vehicle)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local vehicleClass = GetVehicleClass(vehicle)
    local isBike = (vehicleClass == 8 or vehicleClass == 13)

    if isBike then
        local vehicleOffset = vector3(0.0, maxDim.y * 0.35, maxDim.z * 0.45)
        local w = 0.5
        local bY = vehicleOffset.y + 0.22
        local bZ = vehicleOffset.z - 0.05
        local tY = bY - 0.15
        local tZ = bZ + 0.35

        return {
            p1 = vector3(-w / 2, bY, bZ),
            p2 = vector3(w / 2, bY, bZ),
            p3 = vector3(w / 2, tY, tZ),
            p4 = vector3(-w / 2, tY, tZ)
        }
    end

    local boneNames = {
        'window_lf1',
        'window_rf1',
        'windscreen',
        'windscreen_f',
        'seat_dside_f',
    }

    local boneOffsets = {}
    for i = 1, #boneNames do
        local boneIndex = GetEntityBoneIndexByName(vehicle, boneNames[i])
        if boneIndex ~= -1 then
            local boneWorld = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            boneOffsets[#boneOffsets + 1] = GetOffsetFromEntityGivenWorldCoords(vehicle, boneWorld.x, boneWorld.y, boneWorld.z)
        end
    end

    local avgOffset
    if #boneOffsets > 0 then
        local sx, sy, sz = 0.0, 0.0, 0.0
        for i = 1, #boneOffsets do
            sx = sx + boneOffsets[i].x
            sy = sy + boneOffsets[i].y
            sz = sz + boneOffsets[i].z
        end
        avgOffset = vector3(sx / #boneOffsets, sy / #boneOffsets, sz / #boneOffsets)
    else
        avgOffset = vector3(0.0, maxDim.y * 0.45, maxDim.z * 0.55)
    end

    local clampedZ = math.max(minDim.z + 0.35, math.min(maxDim.z - 0.05, avgOffset.z))
    local forwardBias = math.max(0.7, math.min(0.16, (maxDim.y - minDim.y) * 0.03))
    local upBias = math.max(0.1, math.min(0.08, (maxDim.z - minDim.z) * 0.025))
    local bY = avgOffset.y + forwardBias
    local bZ = clampedZ + upBias
    local tY = bY - 0.35
    local tZ = math.min(maxDim.z + 0.12, bZ + 0.18)
    local w = math.max(0.55, math.min(1.35, (maxDim.x - minDim.x) * 0.52))

    return {
        p1 = vector3(-w / 2, bY, bZ),
        p2 = vector3(w / 2, bY, bZ),
        p3 = vector3(w / 2, tY, tZ),
        p4 = vector3(-w / 2, tY, tZ)
    }
end

refreshVehicles = function()
    SpotData = {}
    for _, point in pairs(Points) do
        if point.vehicle and DoesEntityExist(point.vehicle) then
            exports.ox_target:removeLocalEntity(point.vehicle)
            DeleteVehicle(point.vehicle)
        end
        point:remove()
    end
    Wait(100)
    lib.callback("flex_carsale:server:GetVehicles", 1000, function(vehicles)
        if not vehicles or next(vehicles) == nil then return end
        for _, v in pairs(vehicles) do
            local locationId = v.location or Config.DefaultLocation
            local locationData = Config.Locations and Config.Locations[locationId]
            if not locationData then
                if Config.Debug then
                    print(('[flex_carsale] invalid location "%s" for vehicle %s'):format(locationId, v.plate or 'unknown'))
                end
                goto continue
            end

            local coords = locationData.saleSpots[v.spotid]
            if not coords then
                if Config.Debug then
                    print(('[flex_carsale] invalid spot "%s" for location "%s"'):format(v.spotid or 'nil', locationId))
                end
                goto continue
            end
            local point = lib.points.new({
                coords = coords.xyz,
                distance = 15
            })

            point.locationId = locationId
            point.spotId = v.spotid
            point.spotKey = makeSpotKey(locationId, v.spotid)
            point.vehicle = nil
            point.polyOffsets = nil

            function point:onEnter()
                lib.requestModel(v.model)
                self.vehicle = CreateVehicle(GetHashKey(v.model), coords.xyz, coords.w, false, false)
                local vehicleMods = json.decode(v.mods) or {}
                lib.setVehicleProperties(self.vehicle, vehicleMods)
                SetEntityAsMissionEntity(self.vehicle, true, true)
                FreezeEntityPosition(self.vehicle, true)
                SetVehicleOnGroundProperly(self.vehicle)
                SetModelAsNoLongerNeeded(v.model)

                local PedTarget = exports.ox_target:addLocalEntity(self.vehicle, {
                    {
                        icon = "fa-solid fa-magnifying-glass",
                        label = locale('info.buy'),
                        onSelect = function()
                            local confirmation = lib.alertDialog({
                                header = locale('info.buy_confirm_header'),
                                content = locale('info.buy_confirm_content', v.price, v.plate),
                                centered = true,
                                cancel = true,
                                labels = {
                                    confirm = locale('info.yes'),
                                    cancel = locale('info.no')
                                }
                            })

                            if confirmation ~= 'confirm' then
                                return
                            end

                            lib.callback("flex_carsale:server:buyVehicle", false, function(state)
                                if state then
                                    exports.ox_target:removeLocalEntity(self.vehicle)
                                end
                            end, {plate = v.plate, oid = v.occasionid, location = self.locationId})
                        end,
                        canInteract = function(data, distance)
                            return true
                        end,
                        distance = 2.0,
                    },
                    {
                        icon = 'fa-solid fa-screwdriver-wrench',
                        label = locale('info.view_upgrades'),
                        onSelect = function()
                            local contextId = ('flex_carsale:upgrades:%s'):format(self.spotKey)
                            lib.registerContext({
                                id = contextId,
                                title = locale('info.upgrades_title', v.plate),
                                options = buildUpgradeOptions(vehicleMods, v.description)
                            })
                            lib.showContext(contextId)
                        end,
                        canInteract = function(data, distance)
                            return true
                        end,
                        distance = 2.0,
                    }
                })

                self.polyOffsets = getBestWindshieldOffsets(self.vehicle)
                Wait(100)
                local data, id = createDui(self.spotKey)
                if SpotData[id] then
                    SpotData[id].visible = true
                    SendDuiMessage(SpotData[id].duiObject, json.encode({
                        type = "toggleDUI",
                        display = true,
                        price = v.price
                    }))
                end
            end

            function point:nearby()
                if self.currentDistance < 5.0 then
                    local data = SpotData[self.spotKey]
                    if data and data.visible and self.vehicle and DoesEntityExist(self.vehicle) then
                        renderDuiOnWindshield(self.vehicle, data, self.polyOffsets)
                    end
                end
            end

            function point:onExit()
                if SpotData[self.spotKey] then
                    SpotData[self.spotKey].visible = false
                end

                if DoesEntityExist(self.vehicle) then
                    DeleteVehicle(self.vehicle)
                    self.vehicle = nil
                end
                
                self.polyOffsets = nil
                destroyDui(self.spotKey)
            end

            Points[point.spotKey] = point
            ::continue::
        end
    end)
end
CreateThread(function()
    SavedLocations = lib.callback.await('flex_carsale:server:getLocations', false) or {}
    applySavedLocationsToConfig()
    createSellPoints()
    refreshVehicles()
end)

RegisterNetEvent('flex_carsale:client:syncLocations', function(locations)
    SavedLocations = locations or {}
    applySavedLocationsToConfig()
    refreshVehicles()
end)

RegisterNetEvent('flex_carsale:client:refreshVehicles', function()
    refreshVehicles()
end)

RegisterNetEvent('flex_carsale:client:BuyFinished', function(vehData)
    local locationId = vehData.locationId or Config.DefaultLocation
    DoScreenFadeOut(250)
    Wait(500)
    local netId = lib.callback.await('flex_carsale:server:spawnVehicle', false, vehData, Config.Locations[locationId].buyVehicle, false)
    local timeout = 100
    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout > 0 do
        Wait(10)
        timeout = timeout - 1
    end
    local veh = NetToVeh(netId)
    SetEntityHeading(veh, Config.Locations[locationId].buyVehicle.w)
    SetVehicleFuelLevel(veh, 100)
    lib.setVehicleProperties(veh, vehData.mods)
    Config.Notify.client(locale('success.vehicle_bought'), 'success', 2500)
    Wait(500)
    DoScreenFadeIn(250)
    currentVehicle = {}
end)

RegisterNetEvent('flex_carsale:client:sellVehicle', function(amount, description, selectedLocationId)
    if amount and amount > 0 and IsPedInAnyVehicle(cache.ped, false) then
        local locationId, locationDistance = selectedLocationId, nil
        if not locationId then
            locationId, locationDistance = getClosestLocation()
        else
            local pedCoords = GetEntityCoords(cache.ped)
            local sellPoint = Config.Locations[locationId] and Config.Locations[locationId].sellPoint
            if sellPoint then
                locationDistance = #(pedCoords - sellPoint)
            end
        end

        local locationData = locationId and Config.Locations[locationId]
        if not locationData then
            Config.Notify.client(locale('error.no_sales_location_nearby'), 'error', 3500)
            return
        end

        if locationDistance > (locationData.sellRadius or 50.0) then
            Config.Notify.client(locale('error.too_far_from_sales_location', locationData.label or locationId), 'error', 3500)
            return
        end

        local vehicle = GetVehiclePedIsIn(cache.ped, false)
        if vehicle == 0 then
            Config.Notify.client(locale('error.must_be_in_vehicle'), 'error', 3500)
            return
        end

        local plate = GetVehicleNumberPlateText(vehicle)
        local ownsVehicle = lib.callback.await('flex_carsale:server:CanSellOwnedVehicle', false, plate)
        if not ownsVehicle then
            Config.Notify.client(locale('error.not_vehicle_owner'), 'error', 3500)
            return
        end

        local model = lib.callback.await('flex_carsale:server:CheckModelName', false, plate)
        local vehicleData = {}
        vehicleData.ent = vehicle
        vehicleData.model = model
        vehicleData.plate = plate
        vehicleData.mods = lib.getVehicleProperties(vehicleData.ent)
        vehicleData.desc = (description and description ~= '' and description) or locale('info.no_description')
        vehicleData.location = locationId

        local success, errorCode = lib.callback.await('flex_carsale:server:sellVehicle', false, tonumber(amount), vehicleData)
        if success and DoesEntityExist(vehicle) then
            DeleteVehicle(vehicle)
            Config.Notify.client(locale('success.vehicle_listed'), 'success', 3500)
        elseif not success then
            if errorCode == 'no_job' then
                local jobRequired = locationData.jobName or 'unknown'
                Config.Notify.client(('You need the %s job to sell at this location'):format(jobRequired), 'error', 3500)
            else
                Config.Notify.client(locale('error.sell_failed'), 'error', 3500)
            end
        end
    end
end)

RegisterCommand('addsalespot', function()
    openAddSaleSpotMenu()
end)

RegisterCommand('addcarlocation', function()
    openAddLocationMenu()
end)

local function openRemoveSaleSpotMenu()
    local isAdmin = lib.callback.await('flex_carsale:server:isAdmin', false)
    if not isAdmin then
        Config.Notify.client(locale('error.no_permission'), 'error', 3500)
        return
    end

    local locationOptions = {}
    for locationId, locationData in pairs(Config.Locations or {}) do
        local spotCount = 0
        for _ in pairs(locationData.saleSpots or {}) do
            spotCount = spotCount + 1
        end
        if spotCount > 0 then
            locationOptions[#locationOptions + 1] = {
                value = locationId,
                label = (locationData.label or locationId) .. ' (' .. spotCount .. ' spots)'
            }
        end
    end

    if #locationOptions == 0 then
        Config.Notify.client(locale('error.no_spots_to_remove'), 'error', 3500)
        return
    end

    local input = lib.inputDialog(locale('info.remove_sale_spot_title'), {
        {
            type = 'select',
            label = locale('info.remove_sale_spot_location'),
            options = locationOptions,
            required = true
        },
        {
            type = 'number',
            label = locale('info.remove_sale_spot_id'),
            min = 1,
            required = true
        }
    })

    if not input or not input[1] or not input[2] then return end

    local locationId = input[1]
    local spotId = tonumber(input[2])

    local success = lib.callback.await('flex_carsale:server:removeSaleSpot', false, locationId, spotId)
    if not success then
        Config.Notify.client(locale('error.failed_to_remove_sale_spot'), 'error', 3500)
        return
    end

    Config.Notify.client(locale('success.removed_sale_spot', spotId, locationId), 'success', 3500)
    if refreshVehicles then
        refreshVehicles()
    end
end

local function openRemoveLocationMenu()
    local isAdmin = lib.callback.await('flex_carsale:server:isAdmin', false)
    if not isAdmin then
        Config.Notify.client(locale('error.no_permission'), 'error', 3500)
        return
    end

    local locationOptions = {}
    for locationId, locationData in pairs(Config.Locations or {}) do
        locationOptions[#locationOptions + 1] = {
            value = locationId,
            label = locationData.label or locationId
        }
    end

    if #locationOptions == 0 then
        Config.Notify.client(locale('error.no_locations_to_remove'), 'error', 3500)
        return
    end

    local input = lib.inputDialog(locale('info.remove_location_title'), {
        {
            type = 'select',
            label = locale('info.remove_location_select'),
            options = locationOptions,
            required = true
        }
    })

    if not input or not input[1] then return end

    local locationId = input[1]

    local success = lib.callback.await('flex_carsale:server:removeLocation', false, locationId)
    if not success then
        Config.Notify.client(locale('error.failed_to_remove_location'), 'error', 3500)
        return
    end

    Config.Notify.client(locale('success.removed_location', locationId), 'success', 3500)
    createSellPoints()
    if refreshVehicles then
        refreshVehicles()
    end
end

RegisterCommand('removesalespot', function()
    openRemoveSaleSpotMenu()
end)

RegisterCommand('removelocation', function()
    openRemoveLocationMenu()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == thisResource then
        clearSellPoints()
        for k, v in pairs(SpotData) do
            if v.duiObject then DestroyDui(v.duiObject) end
        end
        for _, point in pairs(Points) do
            if point.vehicle and DoesEntityExist(point.vehicle) then
                exports.ox_target:removeLocalEntity(point.vehicle)
                DeleteVehicle(point.vehicle)
            end
            point:remove()
        end
    end
end)
