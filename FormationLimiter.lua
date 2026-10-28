-- Lo Pibe 2 - Limitador de vuelta de formacion v0.6 (diagnostico)
-- Script online de CSP (se carga desde [SCRIPT_...] en las opciones extra del servidor).
-- Frena al auto local cuando pasa MAX_SPEED_LIMIT y lo libera para TODOS cuando
-- el primer auto cruza la linea RELEASE_CROSSING veces.

local cfg = ac.INIConfig.onlineExtras():mapSection('EXTRA_TWEAKS', {
  MAX_SPEED_LIMIT  = 85,   -- km/h: arriba de esto se frena
  BRAKE_TO         = 83,   -- km/h: por debajo de esto se suelta el freno
  BRAKE_FORCE      = 0.3,  -- 0..1
  RELEASE_CROSSING = 1,    -- cruces de linea del lider para liberar (probar 2 si libera apenas arranca)
})

local limiterActive = true
local braking = false
local lastSpline = {}   -- ultima posicion en la pista por auto
local crossings = {}    -- cruces de linea por auto
local logTimer = 0
local physErr = nil

ac.log('[LoPibe2] v0.6 cargado: limite ' .. cfg.MAX_SPEED_LIMIT .. ' km/h, soltar en ' .. cfg.BRAKE_TO
  .. ', fuerza ' .. cfg.BRAKE_FORCE .. ', liberar tras ' .. cfg.RELEASE_CROSSING .. ' cruce(s)')

local function applyBrake()
  local ok, err = pcall(function()
    physics.forceUserClutchFor(0.1, 0)
    physics.forceUserBrakesFor(0.1, cfg.BRAKE_FORCE)
    physics.forceUserThrottleFor(0.1, 0)
  end)
  if not ok and err ~= physErr then
    physErr = err
    ac.log('[LoPibe2] ERROR en physics.forceUser*For: ' .. tostring(err))
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
      if last and last > 0.9 and s < 0.1 then
        crossings[i] = (crossings[i] or 0) + 1
        ac.log('[LoPibe2] auto ' .. i .. ' cruzo la linea, cruces=' .. crossings[i])
        if limiterActive and crossings[i] >= cfg.RELEASE_CROSSING then
          limiterActive = false
          braking = false
          ac.log('[LoPibe2] LIMITADOR LIBERADO por auto ' .. i)
        end
      end
      lastSpline[i] = s
    end
  end

  local me = ac.getCar(sim.focusedCar)
  if not me then return end
  local speed = me.speedKmh

  ac.debug('LoPibe2 limite activo', limiterActive and 'SI' or 'NO')
  ac.debug('LoPibe2 velocidad', speed)
  ac.debug('LoPibe2 frenando', braking and 'SI' or 'NO')

  -- Diagnostico periodico
  logTimer = logTimer + dt
  if logTimer > 2 then
    logTimer = 0
    ac.log(string.format('[LoPibe2] auto=%d v=%.1f activo=%s frenando=%s spline=%.3f',
      sim.focusedCar, speed, tostring(limiterActive), tostring(braking), me.splinePosition))
  end

  if not limiterActive then return end

  if speed > cfg.MAX_SPEED_LIMIT then
    if not braking then ac.log(string.format('[LoPibe2] EMPIEZA A FRENAR a %.1f km/h', speed)) end
    braking = true
  elseif speed < cfg.BRAKE_TO then
    if braking then ac.log(string.format('[LoPibe2] SUELTA FRENO a %.1f km/h', speed)) end
    braking = false
  end

  if braking then
    applyBrake()
    pcall(ac.setMessage,
      'LIMITADOR DE FORMACION: ' .. cfg.MAX_SPEED_LIMIT .. ' km/h',
      'Se desactiva cuando el lider cruza la meta')
  end
end
