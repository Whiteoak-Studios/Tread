--[[
    While on, the client's world casts through every surface too steep to
    walk on and keeps a floor, so a body slides through a wall that stops
    it otherwise, and off puts back the very casts it found
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local REACH: number = 2 -- Studs the body moves toward the wall
local WALL_AT: number = 0.5 -- Studs ahead the wall's hit lies

-- A hit as the step's casts give one, facing a way
local function hit(normal: vector): { [string]: any }
	return {
		distance = WALL_AT,
		position = vector.zero,
		normal = normal,
		material = roblox.Enum.Material.Plastic,
		instance = nil,
	}
end

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local mounted: Kit.Mounted = Kit.mount(rig)
	local world: any = rig.handle._world
	local Collide: any = rig.globals.require(rig.tread.Step.Collide)
	local State: any = rig.globals.require(rig.tread.Step.State)

	local wall: { [string]: any } = hit(vector.create(-1, 0, 0))
	local ceiling: { [string]: any } = hit(vector.create(0, -1, 0))
	local floor: { [string]: any } = hit(vector.create(0, 1, 0))
	local answer: { [string]: any } = wall

	-- Casts whose every sweep meets the answer and whose every box overlaps something
	local casts: { [string]: any } = {
		ray = function (_: vector, _: vector): any
			return nil
		end,

		sweep = function (_: vector, _: vector, _: vector): any
			return answer
		end,

		rest = function (_: vector, _: vector): number?
			return nil
		end,

		sphere = function (_: vector, _: number, _: vector): any
			return nil
		end,

		overlap = function (_: vector, _: vector): boolean
			return true
		end,

		destroy = function () end,
	}

	world.collision = casts

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Noclip).start({ client = rig.handle, shared = rig.shared })

	switch(true)
	local through: any = world.collision
	local size: vector = vector.create(2, 5, 2)
	if through == casts then
		return false, "Switching the noclip on left the client's casts in place"
	elseif through.sweep(vector.zero, size, vector.create(REACH, 0, 0)) ~= nil then
		return false, "The noclip's sweep still met a wall"
	end

	answer = ceiling
	if through.sweep(vector.zero, size, vector.create(0, REACH, 0)) ~= nil then
		return false, "The noclip's sweep still met a ceiling"
	end

	answer = floor
	if through.sweep(vector.zero, size, vector.create(0, -REACH, 0)) ~= floor then
		return false, "The noclip's sweep lost the floor"
	elseif through.overlap(vector.zero, size) then
		return false, "The noclip's overlap still found the body inside something"
	elseif through.ray ~= casts.ray or through.rest ~= casts.rest or through.sphere ~= casts.sphere then
		return false, "The noclip changed the casts the hull's move never makes"
	end

	-- The same move toward the wall, through it with the noclip on and stopped at it with the noclip off
	answer = wall
	local state: any = State.new()
	Collide.move(state, vector.create(REACH, 0, 0), world)
	if math.abs(state.position.x - REACH) > 1e-6 then
		return false, `With the noclip on a move of {REACH} studs through the wall went {state.position.x}`
	end

	switch(false)
	if world.collision ~= casts then
		return false, "Switching the noclip off didn't put back the casts it found"
	end

	local stopped: any = State.new()
	Collide.move(stopped, vector.create(REACH, 0, 0), world)
	if not (stopped.position.x < WALL_AT) then
		return false, `With the noclip off the wall {WALL_AT} studs ahead let the body go {stopped.position.x}`
	end

	return true, nil
end
