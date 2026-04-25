if GetResourceState(Config.CoreName.qb) ~= 'started' then return end
local QBCore = exports[Config.CoreName.qb]:GetCoreObject()

function GetPlayer(src)
    return QBCore.Functions.GetPlayer(src)
end

function RemoveItem(src, item, amount, info, slot)
    if exports[Config.CoreName.qb]:RemoveItem(src, item, amount, slot or false, 'qb-inv:RemoveItem') then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'remove', amount)
        return true
    else
        return false
    end
end

function AddItem(src, item, amount, info, slot)
    if exports[Config.CoreName.qb]:AddItem(src, item, amount, slot or false, 'qb-inv:AddItem') then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'add', amount)
        return true
    else
        return false
    end
end

function HasInvGotItem(inv, search, item, metadata, amount)
    if type(amount) == "boolean" then return end
    if amount == 0 then return false end
    if exports[Config.CoreName.qb]:HasItem(inv, item, amount) then
        return true
    else
        return false
    end
end

function GetItemBySlot(src, slot)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player.Functions.GetItemBySlot(slot)
end

function AddMoney(src, AddType, amount, reason)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player.Functions.AddMoney(AddType, amount, reason or '')
end

function GetPlayerJob(src)
    local Player = GetPlayer(src)
    if not Player or not Player.PlayerData then return nil end
    return Player.PlayerData.job
end

function HasJob(src, jobName)
    local playerJob = GetPlayerJob(src)
    return playerJob and playerJob.name == jobName or false
end

function IsPlayerJobBoss(src, jobName)
    local Player = GetPlayer(src)
    if not Player or not Player.PlayerData then return false end
    local playerJob = Player.PlayerData.job
    return playerJob and playerJob.name == jobName and playerJob.isboss == true or false
end

function AddMoneyToCompanyBank(jobName, amount)
    return exports['qb-management']:AddMoney(jobName, amount)
end