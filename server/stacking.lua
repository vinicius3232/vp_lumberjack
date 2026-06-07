-- vp_lumberjack v2 — ESTÁGIO Empilhamento (server): validação do drop de pallet no trailer.
-- Fills por SESSÃO (cada empilhador tem seus trailers). Earning por pallet, pago na devolução.

local function isStacking(src)
    return VPL.GetJobOf(src) == 'stacking'
end

lib.callback.register('vp_lumberjack:stacking:drop', function(src, trailerIndex)
    if not Security.IsValidSource(src) or not isStacking(src) then return false, 'no_session' end
    if Security.IsOnCooldown(src, 'stackDrop', Config.Cooldowns.action) then return false, 'cooldown' end

    local trailer = Config.Stacking.trailerSpawns[trailerIndex]
    if not trailer then
        Security.LogSuspicious(src, 'stacking:drop', 'idx=' .. tostring(trailerIndex))
        return false, 'failed'
    end
    -- proximidade server-side (jogador perto do trailer)
    if Security.DistanceTo(src, trailer) > 14.0 then return false, 'too_far' end

    local s = VPL.GetSession(src)
    if not s then return false, 'no_session' end
    s.trailerFill = s.trailerFill or {}

    local cap  = Config.Stacking.palletsPerTrailer
    local fill = s.trailerFill[trailerIndex] or 0
    if fill >= cap then return false, 'full' end

    s.trailerFill[trailerIndex] = fill + 1
    local pay = Config.Jobs.stacking.pay.perPallet
    VPL.AddEarning(src, pay)

    return true, { fill = fill + 1, cap = cap, full = (fill + 1 >= cap), pay = pay }
end)
