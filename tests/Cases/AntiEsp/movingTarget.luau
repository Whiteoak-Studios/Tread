--[[
    A moving target's side points are pushed out along their own sides by
    its speed over the look-ahead, whichever way it moves, while its points
    on the line are not, the leading one moved by its velocity instead
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local LOOK_AHEAD: number = 0.2 -- The harness's bot round trip, inside the example's clamp
local TOLERANCE: number = 1e-6 -- Studs a ray's end may sit from where it should
local VELOCITY: vector = vector.create(6, 0, 8) -- 10 studs/s, mostly along the line toward the viewer
local SPEED: number = 10

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	harness.wall = Harness.solid

	-- A line along -Z, so the viewer's right is +X
	local feet: vector = vector.create(0, 0, -40)
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", feet)
	harness.states[target].velocity = VELOCITY

	Harness.AntiEsp.isHidden(viewer, target)
	harness:slice(0)

	local points: { any } = harness.server.antiEsp.aim.Stand
	local reach: number = SPEED * LOOK_AHEAD

	for index: number, point: any in points do
		local ended: vector = harness.rays[index].to
		local finish: vector = feet + vector.create(point.side, point.up, 0)

		if point.side > 0 then
			finish += vector.create(reach, 0, 0)
		elseif point.side < 0 then
			finish -= vector.create(reach, 0, 0)
		elseif point.lead then
			finish += VELOCITY * LOOK_AHEAD
		end

		if vector.magnitude(ended - finish) > TOLERANCE then
			return false, `Point {index}, side {point.side}, ended at {ended}, not {finish}`
		end
	end

	return true, nil
end
