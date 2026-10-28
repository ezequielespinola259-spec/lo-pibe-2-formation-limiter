-- Lo Pibe 2 - Limitador de vuelta de formacion v0.8
-- Script online de CSP (se carga desde [SCRIPT_...] en las opciones extra del servidor).
-- Mantiene la velocidad en MAX_SPEED_LIMIT con el acelerador a fondo, topando el acelerador
-- con un control PI (sin cortar y soltar). Se libera para TODOS cuando el primer auto
-- completa la vuelta de formacion.

local cfg = ac.INIConfig.onlineExtras():mapSection('EXTRA_TWEAKS', {
  MAX_SPEED_LIMIT  = 85,   -- km/h objetivo
  BRAKE_FORCE      = 0.3,  -- freno de emergencia (solo si se pasa por mucho, ej. bajada)
  OVERSPEED_BRAKE  = 6,    -- km/h por encima del limite para activar el freno de emergencia
  KP               = 0.12, -- ganancia proporcional (acelerador por cada km/h de error)
  KI               = 0.08, -- ganancia integral
  RELEASE_CROSSING = 0,    -- cruces para liberar; 0 = automatico (2 si arranca detras de la linea, 1 si no)
})

local limiterActive = true
local lastSpline = {}   -- ultima posicion en la pista por auto
local crossings = {}    -- cruces de linea por auto
local startBehind = {}  -- true si el auto aparecio detras de la linea de meta
local integral = 0.3    -- termino integral del control (estimado inicial del acelerador de sostenimiento)
local cap = 1           -- tope de acelerador calculado
local logTimer = 0
local physErr = nil

ac.log('[LoPibe2] v0.8 cargado: limite ' .. cfg.MAX_SPEED_LIMIT .. ' km/h, KP=' .. cfg.KP
  .. ' KI=' .. cfg.KI .. ', liberar tras ' .. cfg.RELEASE_CROSSING .. ' cruce(s) (0=auto)')

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

local function safe(fn)
  local ok, err = pcall(fn)
  if not ok and err ~= physErr then
    physErr = err
    ac.log('[LoPibe2] ERROR en physics.*: ' .. tostring(err))
  end
  return ok
end

function script.update(dt)
  local sim = ac.getSim()

  -- Cruces de linea de todos los autos (el lider libera a todos a la vez)
  for i = 0, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected then
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
    ac.log(string.format('[LoPibe2] v=%.1f activo=%s cap=%.2f integral=%.2f gas=%.2f spline=%.3f',
      speed, tostring(limiterActive), cap, integral, gas, me.splinePosition))
  end

  if not limiterActive then
    integral = 0.3
    cap = 1
    return
  end

  -- Control PI sobre la velocidad: calcula el tope de acelerador que sostiene el limite
  local err = cfg.MAX_SPEED_LIMIT - speed
  local raw = cfg.KP * err + integral
  cap = clamp(raw, 0, 1)

  -- Integral condicional (anti-windup): no acumula si el tope esta saturado en esa direccion
  local satHigh = raw >= 1 and err > 0
  local satLow = raw <= 0 and err < 0
  if not satHigh and not satLow then
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
