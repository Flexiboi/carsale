if GetResourceState(Config.CoreName.esx) ~= 'started' then return end
local ESX = exports[Config.CoreName.esx]:getSharedObject()

function GetPlayer(src)
    return ESX.GetPlayerFromId(src)
end

function RemoveItem(src, item, amount, info, slot)
    exports.ox_inventory:RemoveItem(src, item, amount, info, slot or nil)
end

function AddItem(src, item, amount, info, slot)
    exports.ox_inventory:AddItem(src, item, amount, info, slot or nil)
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

function RegisterStash(id, slots, maxWeight)
    exports.ox_inventory:RegisterStash(id, id, slots, maxWeight)
end

function ClearStash(id)
    exports.ox_inventory:ClearInventory(id, 'false')
end