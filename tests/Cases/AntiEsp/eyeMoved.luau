--[[
    A viewer's cleared eye holds through its tick's slices, a move of its
    own slot between ticks or a new life of it has the next slice cast from
    where its body is then, and so does the next tick
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local HEARTBEAT: number = 1 / 60 -- Seconds between slices
local TOLERANCE: number = 1e-6 -- Studs a ray's origin may sit from the eye
local TARGET: vector = vector.create(0, 0, -50)
local LANDED: vector = vector.create(20, 0, 10) -- Where a landing between ticks puts the viewer
local STEPPED: vector = vector.create(22, 0, 10) -- Where its next tick's step takes it

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	local world: any = harness.world
	harness.wall = Harness.solid

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", TARGET)
	local state: any = harness.states[own]
	local rays: number = #harness.server.antiEsp.aim.Stand
	local now: number = 0

	-- One slice after the relay's ask, the pair made due first, and whether every ray it cast started at the eye
	local function castsFrom(eye: vector, due: boolean): boolean
		if due then
			AntiEsp.moved(target)
		end

		AntiEsp.isHidden(viewer, target)
		harness:slice(now)
		now += HEARTBEAT

		if #harness.rays ~= rays then
			return false
		end

		for _, ray: any in harness.rays do
			if vector.magnitude(ray.origin - eye) > TOLERANCE then
				return false
			end
		end

		return true
	end

	world.clock = 1
	local first: vector = Harness.Eye.clear(state, world)
	if not castsFrom(first, false) then
		return false, "The new pair's first test did not cast from the viewer's eye"
	end

	-- Moved between ticks with nothing told, the body keeps its tick's eye
	harness:move(own, LANDED, viewer)
	if not castsFrom(first, true) then
		return false, "A slice later in the tick did not cast from the eye its first slice found"
	end

	AntiEsp.moved(own)
	if not castsFrom(Harness.Eye.clear(state, world), false) then
		return false, "The slice after a move of the viewer's own slot did not cast from where it landed"
	end

	-- A new life of the viewer's slot between ticks, crouched
	state.posture = "Crouch"
	state.eyeHeight = harness.shared.step.eyeCrouched
	harness:reborn(own)
	if not castsFrom(Harness.Eye.clear(state, world), true) then
		return false, "The slice after a new life of the viewer's slot did not cast from its crouched eye"
	end

	world.clock = 2
	harness:move(own, STEPPED, viewer)
	if not castsFrom(Harness.Eye.clear(state, world), true) then
		return false, "The next tick's slice did not cast from where the viewer stepped"
	end

	return true, nil
end
