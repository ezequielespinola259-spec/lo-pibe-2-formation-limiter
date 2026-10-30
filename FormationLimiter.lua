-- Lo Pibe 2 - Limitador de vuelta de formacion v1.1
-- Script online de CSP (se carga desde [SCRIPT_...] en las opciones extra del servidor).
-- Mantiene la velocidad en MAX_SPEED_LIMIT con el acelerador a fondo (control PI sobre el
-- tope de acelerador). Solo actua en carrera (ONLY_RACE). Se libera para TODOS cuando el
-- primer auto completa la vuelta de formacion, y se vuelve a armar si la sesion se reinicia.

local cfg = ac.INIConfig.onlineExtras():mapSection('EXTRA_TWEAKS', {
  MAX_SPEED_LIMIT  = 98,   -- km/h objetivo
  BRAKE_FORCE      = 0.3,  -- freno de emergencia (solo si se pasa por mucho, ej. bajada)
  OVERSPEED_BRAKE  = 6,    -- km/h por encima del limite para activar el freno de emergencia
  KP               = 0.12, -- ganancia proporcional (acelerador por cada km/h de error)
  KI               = 0.08, -- ganancia integral
  RELEASE_CROSSING = 0,    -- cruces para liberar; 0 = automatico (2 si arranca detras de la linea, 1 si no)
  ONLY_RACE        = 1,    -- 1 = el limitador solo actua en sesion de carrera (0 = en todas)
})

local limiterActive = true
local lastSpline = {}   -- ultima posicion en la pista por auto
local crossings = {}    -- cruces de linea por auto
local startBehind = {}  -- true si el auto aparecio detras de la linea de meta
local lastPos = {}      -- ultima posicion 3D por auto (para detectar teletransportes)
local teleportAt = {}   -- instante del ultimo teletransporte por auto
local integral = 0.2    -- termino integral del control
local cap = 1           -- tope de acelerador calculado
local logTimer = 0
local clock = 0
local settle = 0        -- tiempo de espera tras un rearme, para que los autos lleguen a la parrilla
local lastSession = nil
local lastTts = nil
local raceNow = true
local physErr = nil

ac.log('[LoPibe2] v1.1 cargado: limite ' .. cfg.MAX_SPEED_LIMIT .. ' km/h, KP=' .. cfg.KP
  .. ' KI=' .. cfg.KI .. ', liberar tras ' .. cfg.RELEASE_CROSSING .. ' cruce(s) (0=auto)')

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- Devuelve true si la sesion actual es carrera. Si no se puede saber, devuelve true
-- (mejor limitar de mas que dejar sin limitador).
local function sessionIsRace(sim)
  local ok, res = pcall(function()
    return ac.getSession(sim.currentSessionIndex).type == ac.SessionType.Race
  end)
  if ok and res ~= nil then return res end
  local ok2, res2 = pcall(function() return sim.raceSessionType == ac.SessionType.Race end)
  if ok2 and res2 ~= nil then return res2 end
  return true
end

local function safe(fn)
  local ok, err = pcall(fn)
  if not ok and err ~= physErr then
    physErr = err
    ac.log('[LoPibe2] ERROR en physics.*: ' .. tostring(err))
  end
  return ok
end

-- Vuelve a armar el limitador (nueva sesion o reinicio de la carrera)
local function resetState(reason)
  limiterActive = true
  integral = 0.2
  cap = 1
  lastSpline, crossings, startBehind = {}, {}, {}
  lastPos, teleportAt = {}, {}
  settle = 1.0
  ac.log('[LoPibe2] REARMADO: ' .. reason)
end

function script.update(dt)
  local sim = ac.getSim()
  clock = clock + dt
  if settle > 0 then settle = settle - dt end

  -- Cambio de sesion
  local sessionIdx = sim.currentSessionIndex
  if sessionIdx ~= lastSession then
    lastSession = sessionIdx
    lastTts = nil
    raceNow = sessionIsRace(sim)
    local okT, tName = pcall(function() return tostring(ac.getSession(sessionIdx).type) end)
    ac.log('[LoPibe2] sesion ' .. tostring(sessionIdx) .. ' tipo=' .. (okT and tName or '?')
      .. ' esCarrera=' .. tostring(raceNow) .. ' ONLY_RACE=' .. tostring(cfg.ONLY_RACE))
    resetState('nueva sesion')
  end

  -- Senal A de reinicio: la cuenta atras de la sesion vuelve a empezar
  local okTts, tts = pcall(function() return sim.timeToSessionStart end)
  if okTts and type(tts) == 'number' then
    if lastTts ~= nil and lastTts <= 0 and tts > 0 then
      resetState('reinicio de sesion (cuenta atras, tts=' .. tostring(tts) .. ')')
    end
    lastTts = tts
  end

  -- Cruces de linea y teletransportes de todos los autos
  if settle <= 0 then
    local connected = 0
    for i = 0, sim.carsCount - 1 do
      local c = ac.getCar(i)
      if c and c.isConnected then
        connected = connected + 1
        local s = c.splinePosition
        local last = lastSpline[i]
        if last == nil then
          startBehind[i] = s > 0.9
          ac.log('[LoPibe2] auto ' .. i .. ' visto por primera vez en spline=' .. string.format('%.3f', s)
            .. ' detras_de_linea=' .. tostring(startBehind[i]))
        end
        if last and last > 0.9 and s < 0.1 then
          crossings[i] = (crossings[i] or 0) + 1
          local need = cfg.RELEASE_CROSSING
          if need <= 0 then need = startBehind[i] and 2 or 1 end
          ac.log('[LoPibe2] auto ' .. i .. ' cruzo la linea, cruces=' .. crossings[i] .. ' de ' .. need)
          if limiterActive and crossings[i] >= need then
            limiterActive = false
            ac.log('[LoPibe2] LIMITADOR LIBERADO por auto ' .. i)
          end
        end
        lastSpline[i] = s

        -- Senal B de reinicio: teletransporte de varios autos a la vez (vuelta a la parrilla)
        local p = c.position
        local pp = lastPos[i]
        if pp and dt < 0.5 then
          local dx, dy, dz = p.x - pp[1], p.y - pp[2], p.z - pp[3]
          if dx * dx + dy * dy + dz * dz > 10000 then teleportAt[i] = clock end
        end
        lastPos[i] = { p.x, p.y, p.z }
      end
    end

    if not limiterActive and raceNow then
      local n = 0
      for i = 0, sim.carsCount - 1 do
        if teleportAt[i] and clock - teleportAt[i] < 3 then n = n + 1 end
      end
      if n > 0 and n >= math.min(2, connected) then
        resetState('teletransporte de ' .. n .. ' auto(s) a la vez')
      end
    end
  end

  local me = ac.getCar(sim.focusedCar)
  if not me then return end
  local speed = me.speedKmh
  local gas = me.gas or 1

  ac.debug('LoPibe2 limite activo', limiterActive and 'SI' or 'NO')
  ac.debug('LoPibe2 velocidad', speed)
  ac.debug('LoPibe2 tope acelerador', cap)
  ac.debug('LoPibe2 gas leido', gas)

  logTimer = logTimer + dt
  if logTimer > 2 then
    logTimer = 0
    ac.log(string.format('[LoPibe2] v=%.1f activo=%s carrera=%s cap=%.2f integral=%.2f gas=%.2f spline=%.3f',
      speed, tostring(limiterActive), tostring(raceNow), cap, integral, gas, me.splinePosition))
  end

  if not limiterActive or (cfg.ONLY_RACE == 1 and not raceNow) then
    integral = 0.2
    cap = 1
    return
  end

  -- Control PI sobre la velocidad: calcula el tope de acelerador que sostiene el limite
  local err = cfg.MAX_SPEED_LIMIT - speed
  local raw = cfg.KP * err + integral
  cap = clamp(raw, 0, 1)

  -- Integral condicional (anti-windup): no acumula si el tope esta saturado en esa direccion,
  -- ni cuando el piloto no esta pidiendo el tope (levanto el pie en una curva).
  local satHigh = raw >= 1 and err > 0
  local satLow = raw <= 0 and err < 0
  local limiting = gas >= cap - 0.03
  if limiting and not satHigh and not satLow then
    integral = clamp(integral + cfg.KI * err * dt, 0, 1)
  end

  -- Solo se topa si el piloto pide mas acelerador que el tope
  if gas > cap then
    safe(function() physics.forceUserThrottleFor(0.1, cap) end)
    pcall(ac.setMessage,
      'LIMITADOR DE FORMACION: ' .. cfg.MAX_SPEED_LIMIT .. ' km/h',
      'Se desactiva cuando el lider cruza la meta')
  end

  -- Freno de emergencia solo si se pasa por mucho (ej. bajada)
  if speed > cfg.MAX_SPEED_LIMIT + cfg.OVERSPEED_BRAKE then
    safe(function() physics.forceUserBrakesFor(0.1, cfg.BRAKE_FORCE) end)
  end
end
