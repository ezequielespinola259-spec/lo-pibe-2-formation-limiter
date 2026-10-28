ac.log("FORMATION TEST: script cargado")
local t = 0
function script.update(dt)
  t = t + dt
  ac.debug("FORMATION TEST", string.format("ACTIVO %.1f s", t))
end
