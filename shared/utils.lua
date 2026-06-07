-- vp_lumberjack — Funções puras compartilhadas (client + server)
-- Namespace único p/ não poluir o global (CLAUDE.md regra 7).

VPL = VPL or {}

lib.locale()  -- convar `setr ox:locale pt`; fallback en

--- Inteiro aleatório [min, max].
function VPL.RandInt(min, max)
    if max < min then min, max = max, min end
    return math.random(min, max)
end

--- Formata dinheiro ("$1.234").
function VPL.Money(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return '$' .. out
end

--- Menor diferença angular (0..180) entre dois headings. Usado p/ alinhar garfo/trailer.
--- @param a number
--- @param b number
--- @return number graus
function VPL.HeadingDiff(a, b)
    local d = math.abs((a - b) % 360)
    if d > 180 then d = 360 - d end
    return d
end
