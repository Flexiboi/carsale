if GetResourceState(Config.CoreName.qb) ~= 'started' then return end
local QBCore = exports[Config.CoreName.qb]:GetCoreObject()

function GetPlayerData()
    return QBCore.Functions.GetPlayerData()
end