--[[
    The render time runs at real time on its aim, closes a drift at the
    drift's own size a second inside interpolation.scaleMin to scaleMax, and
    snaps to its aim past delayMax behind the newest tick or past it
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local TOLERANCE: number = 1e-9
local FRAME: number = 0.01

-- A viewer whose render time sits on its aim at 101: five blocks at once, 3 ticks behind the newest
local function settled(): any
	local viewer = Viewer.new()

	for tick: number = 100, 104 do
		viewer.send({ tick = tick })
	end

	viewer.Interpolate.frame(0)

	return viewer
end

-- How far one frame moves the render time, in relay ticks
local function advance(Interpolate: any, dt: number): number
	local before: number = Interpolate.renderTime()
	Interpolate.frame(dt)

	return Interpolate.renderTime() - before
end

return function (): (boolean, string | nil)
	local viewer = settled()
	local Interpolate: any = viewer.Interpolate
	local rate: number = viewer.rates.relay
	local settings: { [string]: number } = viewer.settings

	local moved: number = advance(Interpolate, 0.05)
	if math.abs(moved - 1) > TOLERANCE then
		return false, `On its aim the render time moved {moved} ticks in one relay interval, not 1`
	end

	-- Three blocks early put the aim 2.2 ticks ahead, past what the time scale's top closes at once
	viewer.send({ tick = 105 })
	viewer.send({ tick = 106 })
	viewer.send({ tick = 107 })

	moved = advance(Interpolate, FRAME)
	if math.abs(moved - FRAME * rate * settings.scaleMax) > TOLERANCE then
		return false, `Far behind its aim the render time moved {moved} ticks, not at the time scale's top`
	end

	-- Half a tick behind its aim, the scale is 1 plus that drift in seconds
	viewer = settled()
	Interpolate = viewer.Interpolate
	Interpolate.frame(0.025)
	viewer.send({ tick = 105 })

	moved = advance(Interpolate, FRAME)
	if math.abs(moved - FRAME * rate * (1 + 0.025)) > TOLERANCE then
		return false, `Half a tick behind its aim the render time moved {moved} ticks, not at a scale of 1.025`
	end

	-- A late block grows the delay to its ceiling, which puts the aim far behind the render time
	viewer = settled()
	Interpolate = viewer.Interpolate
	Interpolate.frame(0.15)
	viewer.send({ tick = 105 })

	moved = advance(Interpolate, FRAME)
	if math.abs(moved - FRAME * rate * settings.scaleMin) > TOLERANCE then
		return false, `Far ahead of its aim the render time moved {moved} ticks, not at the time scale's bottom`
	end

	-- Six blocks at once leave it 0.45 s behind the newest, past delayMax, so it snaps 3 ticks behind 110
	viewer = settled()
	Interpolate = viewer.Interpolate
	for tick: number = 105, 110 do
		viewer.send({ tick = tick })
	end

	Interpolate.frame(0)

	local renderTime: number = Interpolate.renderTime()
	if math.abs(renderTime - 107) > TOLERANCE then
		return false, `0.45 s behind the newest tick the render time went to {renderTime}, not its aim at 107`
	end

	-- A second with no block, then one that shows the clock had run ahead, leaves it past the newest tick
	Interpolate.frame(1)
	viewer.send({ tick = 111 })
	Interpolate.frame(0)

	renderTime = Interpolate.renderTime()
	local aim: number = 111 - settings.delayMax * rate
	if math.abs(renderTime - aim) > TOLERANCE then
		return false, `Past the newest tick the render time went to {renderTime}, not its aim at {aim}`
	end

	return true, nil
end
