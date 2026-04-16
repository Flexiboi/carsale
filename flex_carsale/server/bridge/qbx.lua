if GetResourceState(Config.CoreName.qbx) ~= 'started' then return end

function GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

function GetPlayerByCitizenId(identifier)
    return exports.qbx_core:GetPlayerByCitizenId(identifier)
end

function GetVehiclesByName()
    return exports.qbx_core:GetVehiclesByName()
end

function GetPlayerBankMoney(player)
    return player and player.PlayerData and player.PlayerData.money and player.PlayerData.money.bank or 0
end

function RemoveMoney(player, moneyType, amount)
    return player.Functions.RemoveMoney(moneyType, amount)
end

function AddMoneyToPlayer(player, moneyType, amount)
    return player.Functions.AddMoney(moneyType, amount)
end

function RemoveItem(src, item, amount, info, slot)
    return exports.ox_inventory:RemoveItem(src, item, amount, info, slot or nil)
end

function AddItem(src, item, amount, info, slot)
    return exports.ox_inventory:AddItem(src, item, amount, info, slot or nil)
end

function HasInvGotItem(inv, search, item, metadata, amount)
    if type(amount) == "boolean" then return end
    if amount == 0 then return false end
    if exports.ox_inventory:Search(inv, search, item) >= amount then
        return true
    else
        return false
    end
end

function GetInvItems(inv)
    return exports.ox_inventory:GetInventoryItems(inv)
end

function GetItemBySlot(src, slot)
    local Player = exports.qbx_core:GetPlayer(src)
    return Player.Functions.GetItemBySlot(slot)
end

function AddMoney(src, AddType, amount, reason)
    exports.qbx_core:AddMoney(src, AddType, amount, reason or '')
end

local function giveVehicle(src, vehModel)
    if not exports.qbx_core:GetVehiclesByHash()[vehModel] then
        return Config.Notify.server(src, locale('error.invalid_vehicle'), "error", 3000)
    end
    local playerData = GetPlayer(src).PlayerData
    local vehName, props = lib.callback.await('smallresources:client:GetVehicleInfo', src)
    local existingVehicleId = Entity(vehicle).state.vehicleid
    if existingVehicleId then
        local response = lib.callback.await('smallresources:client:SaveCarDialog', src)
        if not response then
            return
        end
        local success, err = exports.qbx_vehicles:SetPlayerVehicleOwner(existingVehicleId, playerData.citizenid)
        if not success then error(err) end
    else
        local vehicleId, err = exports.qbx_vehicles:CreatePlayerVehicle({
            model = vehName,
            citizenid = playerData.citizenid,
            props = props,
        })
        if err then error(err) end
        Entity(vehicle).state:set('vehicleid', vehicleId, true)
    end
end

function RegisterStash(id, slots, maxWeight)
    exports.ox_inventory:RegisterStash(id, id, slots, maxWeight)
end

function ClearStash(id)
    exports.ox_inventory:ClearInventory(id, 'false')
end

function SetJob(src, job, grade)
    local Player = exports.qbx_core:GetPlayer(src)
    exports.qbx_core:SetJob(src, job, grade)
end

function GetJobs()
    return exports.qbx_core:GetJobs()
end

function HasPermission(src)
    return exports.qbx_core:HasPermission(src, 'admin')
end