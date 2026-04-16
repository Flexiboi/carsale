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