-- vp_lumberjack — Polimento: som da motosserra + comando de volume.
-- O som padrão é um native placeholder. Pra som fiel, troque o corpo de VPL.PlayChainsaw
-- por uma chamada ao seu resource de áudio (xsound/InteractSound).

local KVP = 'vp_lumberjack:sawVolume'

-- carrega volume salvo (0-100); default se nunca setado
do
    local saved = GetResourceKvpString(KVP)
    VPL.chainsawVolume = saved and tonumber(saved) or Config.Chainsaw.defaultVolume
end

RegisterCommand(Config.Chainsaw.volumeCommand, function(_, args)
    local v = tonumber(args[1])
    if not v or v < 0 or v > 100 then
        VPL.Notify('warning', 'saw_vol_bad', Config.Chainsaw.volumeCommand)
        return
    end
    VPL.chainsawVolume = math.floor(v)
    SetResourceKvp(KVP, tostring(VPL.chainsawVolume))
    VPL.Notify('inform', 'saw_vol_set', VPL.chainsawVolume)
end, false)

local sawActive = false

--- Inicia o loop do som da motosserra na entidade (até StopChainsaw). Respeita o volume 0.
function VPL.PlayChainsaw(ped)
    if (VPL.chainsawVolume or 0) <= 0 or sawActive then return end
    sawActive = true
    CreateThread(function()
        while sawActive do
            PlaySoundFromEntity(-1, Config.Chainsaw.sound.name, ped, Config.Chainsaw.sound.set, true, 0)
            Wait(Config.Chainsaw.loopMs)
        end
    end)
end

function VPL.StopChainsaw()
    sawActive = false
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then sawActive = false end
end)
