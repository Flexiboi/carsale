SV_Config = {}
SV_Config.webhook = ''

SV_Config.SendMail = function(src, subject, message)
    local Player = GetPlayer(src)
    if Player then
        TriggerEvent('qb-phone:server:sendNewMailToOffline', sellerCitizenId, {
            sender = locale('mail.sender'),
            subject = locale('mail.subject'),
            message = (locale('mail.message'):format(newPrice, VEHICLES[result[1].model].name))
        })
    end
end