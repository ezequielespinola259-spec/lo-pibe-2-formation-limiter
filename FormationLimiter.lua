-- Lo Pibe 2 - Limitador de vuelta de formacion v0.5
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

ac.log('[LoPibe2] FormationLimiter cargado: limite ' .. cfg.MAX_SPEED_LIMIT .. ' km/h')

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
          ac.log('[LoPibe2] LIMITADOR LIBERADO')
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

  if not limiterActive then return end

  if speed > cfg.MAX_SPEED_LIMIT then
    braking = true
  elseif speed < cfg.BRAKE_TO then
    braking = false
  end

  if braking then
    physics.forceUserClutchFor(0.1, 0)
    physics.forceUserBrakesFor(0.1, cfg.BRAKE_FORCE)
    physics.forceUserThrottleFor(0.1, 0)
    pcall(ac.setMessage,
      'LIMITADOR DE FORMACION: ' .. cfg.MAX_SPEED_LIMIT .. ' km/h',
      'Se desactiva cuando el lider cruza la meta')
  end
end
