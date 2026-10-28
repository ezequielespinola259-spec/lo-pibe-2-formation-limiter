
local brake = 0
local messageSent = 0
local limiterActive = true
local lastSpline = nil

local extras = ac.INIConfig.onlineExtras():mapSection('EXTRA_TWEAKS', {
  MAX_SPEED_LIMIT = 80,
  BRAKE_TO = 78,
  BRAKE_FORCE = 0.3
})

function script.update()
  local car = ac.getCar(carIndex)
  if not car then return end

  local spline = car.splinePosition
  local speed = car.speedKmh

  -- Desactivar al cruzar la linea de meta por primera vez
  if lastSpline ~= nil and lastSpline > 0.90 and spline < 0.10 then
    limiterActive = false
    brake = 0
    ac.debug('LO PIBE 2', 'LIMITADOR DESACTIVADO: META')
  end

  lastSpline = spline

  -- Mostrar estado para diagnostico
  ac.debug('Limite activo', limiterActive and 'SI' or 'NO')
  ac.debug('Velocidad', speed)

  if not limiterActive then return end

  -- Limitar velocidad durante la primera vuelta
  if speed < extras.BRAKE_TO and brake == 1 then
    brake = 0
    messageSent = 0
  end

  if speed > extras.MAX_SPEED_LIMIT or brake == 1 then
    brake = 1

    physics.forceUserClutchFor(0.1, 0)
    physics.forceUserBrakesFor(0.1, extras.BRAKE_FORCE)
    physics.forceUserThrottleFor(0.1, 0)

    ac.setMessage(
      'LIMITADOR DE FORMACION: 80 km/h',
      'Se desactiva al cruzar la meta'
    )

    if messageSent == 0 then
      ac.sendChatMessage('Limitador de formacion activo: 80 km/h')
      messageSent = 1
    end
  end
end
