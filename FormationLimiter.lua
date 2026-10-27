
-- FormationLimiter.lua
-- Assetto Corsa + CSP + KissMyRank
-- Limite durante la vuelta de formacion: 145 km/h
-- El limitador se libera al cruzar la linea de largada.

local MAX_SPEED_LIMIT = 145
local BRAKE_TO = 140
local BRAKE_FORCE = 0.30

local limiterActive = false
local raceDetected = false
local previousSpline = nil
local armedForFinish = false
local messageSent = false

local function resetLimiter()
  limiterActive = false
  raceDetected = false
  previousSpline = nil
  armedForFinish = false
  messageSent = false
end

local function limitSpeed(car)
  local speed = car.speedKmh
  if speed == nil then return end

  if speed > MAX_SPEED_LIMIT then
    physics.forceUserClutchFor(0.1, 0)
    physics.forceUserBrakesFor(0.1, BRAKE_FORCE)
    physics.forceUserThrottleFor(0.1, 0)

    ac.setMessage(
      'Formation speed limit: ' .. MAX_SPEED_LIMIT .. ' km/h',
      'Slow down to ' .. BRAKE_TO .. ' km/h'
    )

    if not messageSent then
      ac.sendChatMessage(
        'Formation limiter active: maximum ' ..
        MAX_SPEED_LIMIT .. ' km/h'
      )
      messageSent = true
    end
  elseif speed < BRAKE_TO then
    messageSent = false
  end
end

function script.update()
  local sim = ac.getSim()
  if not sim then return end

  local session = ac.getSession(sim.currentSessionIndex)
  if not session or session.type ~= ac.SessionType.Race then
    resetLimiter()
    return
  end

  local car = ac.getCar(carIndex)
  if not car then return end

  local spline = car.splinePosition
  if spline == nil then return end

  -- Activate when the race session begins.
  if not raceDetected then
    raceDetected = true
    limiterActive = true
    previousSpline = spline
    armedForFinish = false
  end

  -- Arm detection after moving away from the start line.
  if spline > 0.15 then
    armedForFinish = true
  end

  -- Detect crossing the start/finish line.
  if limiterActive and armedForFinish
      and previousSpline ~= nil
      and previousSpline > 0.85
      and spline < 0.15 then

    limiterActive = false
    ac.sendChatMessage(
      'Formation limiter released: start line crossed'
    )
  end

  previousSpline = spline

  if limiterActive then
    limitSpeed(car)
  end
end
