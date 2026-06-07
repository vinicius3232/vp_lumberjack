-- vp_lumberjack v2 — Operação de garfo REUTILIZÁVEL (telehandler / empilhadeira).
-- Helpers de baixo nível (ForkTip/Attach/Place) + ForkCarry (carga única) construído neles.
-- Usado por corte (fase 2), empilhamento (3) e entrega (4).

--- Posição mundial da ponta do garfo + índice do bone (fallback p/ offset do config).
--- @param veh number
--- @return vector3 pos, number boneIdx
function VPL.ForkTip(veh)
    local idx = GetEntityBoneIndexByName(veh, Config.Fork.forkBone)
    if idx and idx ~= -1 then
        return GetWorldPositionOfEntityBone(veh, idx), idx
    end
    local o = Config.Fork.forkOffset
    return GetOffsetFromEntityInWorldCoords(veh, o.x, o.y, o.z), 0
end

--- Veículo de trabalho atual SE o jogador estiver nele. @return number|nil
function VPL.InForkVehicle()
    local veh = VPL.GetJobVehicle()
    if veh and GetVehiclePedIsIn(cache.ped, false) == veh then return veh end
    return nil
end

--- Desenha o marcador da zona (chão).
function VPL.DrawForkZone(coords)
    local m, c = Config.Fork.markerSize, Config.Fork.markerColor
    DrawMarker(1, coords.x, coords.y, coords.z - 0.95, 0,0,0, 0,0,0,
        m.x, m.y, m.z, c.r, c.g, c.b, c.a, false, false, 2, false, nil, nil, false)
end

--- Gruda a carga no garfo.
function VPL.ForkAttach(veh, load)
    local _, b = VPL.ForkTip(veh)
    local a = Config.Fork.loadAttach
    AttachEntityToEntity(load, veh, b, a.x, a.y, a.z, 0.0, 0.0, 0.0, false, false, false, false, 1, true)
end

--- Solta a carga e a posiciona/congela no destino.
function VPL.ForkPlace(load, coords, heading)
    if not DoesEntityExist(load) then return end
    DetachEntity(load, true, true)
    SetEntityCoords(load, coords.x, coords.y, coords.z, false, false, false, false)
    if heading then SetEntityHeading(load, heading) end
    FreezeEntityPosition(load, true)
end

local function uiToggle(state, text)
    if text and not state.shown then lib.showTextUI(text); state.shown = true
    elseif not text and state.shown then lib.hideTextUI(); state.shown = false end
end

--- Carrega `load` do ponto de coleta até o drop. BLOQUEIA até concluir/abortar.
--- @param load number
--- @param pickupCoords vector3
--- @param drop table  { coords=vector3, heading=number, radius=number }
--- @param onDropped fun()|nil
--- @return boolean delivered
function VPL.ForkCarry(load, pickupCoords, drop, onDropped)
    local attached = false
    local st = { shown = false }

    while VPL.CurrentJob() and not attached do
        Wait(0)
        VPL.DrawForkZone(pickupCoords)
        local veh = VPL.InForkVehicle()
        local tip = veh and VPL.ForkTip(veh)
        if veh and #(tip - pickupCoords) <= Config.Fork.alignDistance then
            uiToggle(st, locale('fork_grab'))
            if IsControlJustReleased(0, Config.Fork.grabKey) then
                VPL.ForkAttach(veh, load); attached = true; uiToggle(st, nil)
            end
        else uiToggle(st, nil) end
    end

    while VPL.CurrentJob() and attached do
        Wait(0)
        VPL.DrawForkZone(drop.coords)
        local veh = VPL.InForkVehicle()
        local tip = veh and VPL.ForkTip(veh)
        local aligned = veh and #(tip - drop.coords) <= drop.radius
            and VPL.HeadingDiff(GetEntityHeading(veh), drop.heading) <= Config.Fork.alignHeading
        if aligned then
            uiToggle(st, locale('fork_drop'))
            if IsControlJustReleased(0, Config.Fork.grabKey) then
                VPL.ForkPlace(load, drop.coords, drop.heading)
                uiToggle(st, nil)
                if onDropped then onDropped() end
                return true
            end
        else uiToggle(st, nil) end
    end

    uiToggle(st, nil)
    if DoesEntityExist(load) then
        DetachEntity(load, true, true)
        if DoesEntityExist(load) then DeleteEntity(load) end
    end
    return false
end
