-- vp_lumberjack v2 — ESTÁGIO Corte (server): estado autoritativo das árvores,
-- validação de derrubada e earning na entrega das toras ao stand.
-- Economia: derrubar 1 árvore (server valida) gera 1 "carga pendente" na sessão;
-- entregar no stand credita Config.Jobs.cutting.pay.perTree. Garfo/anim são flavor client.

local Trees = {}   -- [id] = { coords, cuttable, reservedBy, reserveExp, respawnAt }

for id, coords in ipairs(Config.Cutting.trees) do
    Trees[id] = { coords = coords, cuttable = true }
end

local function broadcast(id, cuttable)
    TriggerClientEvent('vp_lumberjack:cutting:update', -1, id, cuttable)
end

local function isCutting(src)
    return VPL.GetJobOf(src) == 'cutting'
end

lib.callback.register('vp_lumberjack:cutting:getState', function(src)
    if not Security.IsValidSource(src) then return {} end
    local out = {}
    for id, t in pairs(Trees) do out[#out + 1] = { id = id, cuttable = t.cuttable } end
    return out
end)

--------------------------------------------------------------------------------
-- Derrubada
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:cutting:beginFell', function(src, id)
    if not Security.IsValidSource(src) or not isCutting(src) then return false, 'no_session' end
    if Security.IsOnCooldown(src, 'fell', Config.Cooldowns.action) then return false, 'cooldown' end

    local t = Trees[id]
    if not t then
        Security.LogSuspicious(src, 'beginFell', 'id=' .. tostring(id))
        return false, 'not_cuttable'
    end
    if not t.cuttable then return false, 'not_cuttable' end
    if t.reservedBy and t.reservedBy ~= src then return false, 'not_cuttable' end
    if not VPL.HasChainsaw(src) then return false, 'need_chainsaw' end
    if Security.DistanceTo(src, t.coords) > Config.Cutting.interactRadius then return false, 'too_far' end

    t.reservedBy = src
    t.reserveExp = GetGameTimer() + Config.Cutting.fellDuration + 6000
    Security.BeginAuth(src, 'fell', id, Config.Cutting.fellMin)
    return true
end)

RegisterNetEvent('vp_lumberjack:cutting:cancelFell', function(id)
    local src = source
    if not Security.IsValidSource(src) or type(id) ~= 'number' then return end
    local t = Trees[id]
    if t and t.reservedBy == src then t.reservedBy = nil; t.reserveExp = nil end
end)

lib.callback.register('vp_lumberjack:cutting:finishFell', function(src, id)
    if not Security.IsValidSource(src) or not isCutting(src) then return false, 'no_session' end
    if not Security.ConsumeAuth(src, 'fell', id) then
        Security.LogSuspicious(src, 'finishFell', 'sem token/instant id=' .. tostring(id))
        return false, 'failed'
    end
    local t = Trees[id]
    if not t or not t.cuttable or t.reservedBy ~= src then return false, 'not_cuttable' end
    if not VPL.HasChainsaw(src) then return false, 'need_chainsaw' end
    if Security.DistanceTo(src, t.coords) > Config.Cutting.interactRadius + 2.0 then return false, 'too_far' end

    t.cuttable   = false
    t.reservedBy = nil
    t.reserveExp = nil
    t.respawnAt  = GetGameTimer() + (Config.Cutting.respawnMinutes * 60000)
    broadcast(id, false)

    -- registra carga pendente na sessão (creditada na entrega ao stand)
    local s = VPL.GetSession(src)
    if s then s.cutPending = (s.cutPending or 0) + 1 end
    return true
end)

--------------------------------------------------------------------------------
-- Entrega das toras ao stand → earning
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:cutting:deliver', function(src)
    if not Security.IsValidSource(src) or not isCutting(src) then return false, 'no_session' end
    if Security.IsOnCooldown(src, 'cutDeliver', Config.Cooldowns.action) then return false, 'cooldown' end

    local s = VPL.GetSession(src)
    if not s or (s.cutPending or 0) <= 0 then return false, 'no_load' end

    local stand = Config.Cutting.stand
    if Security.DistanceTo(src, stand.coords) > stand.radius + 2.0 then return false, 'stand_far' end

    s.cutPending = s.cutPending - 1
    local pay = Config.Jobs.cutting.pay.perTree
    VPL.AddEarning(src, pay)
    return true, { pay = pay }
end)

--------------------------------------------------------------------------------
-- Respawn + reservas órfãs
--------------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for id, t in pairs(Trees) do
            if not t.cuttable and t.respawnAt and now >= t.respawnAt and not t.reservedBy then
                t.cuttable = true; t.respawnAt = nil; broadcast(id, true)
            end
            if t.reservedBy and t.reserveExp and now >= t.reserveExp then
                t.reservedBy = nil; t.reserveExp = nil
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, t in pairs(Trees) do
        if t.reservedBy == src then t.reservedBy = nil; t.reserveExp = nil end
    end
end)
