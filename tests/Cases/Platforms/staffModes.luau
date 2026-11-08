--[[
    Noclip and Parked clear a rider's platform on their first step, and
    the lift then carries the body no farther, while a walking rider beside
    it keeps riding
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"

local LIFT: number = 1
local START: number = 30
local RISE: number = 0.25

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local world: any = Riders.world()
	Platforms.add(world, Riders.lift(LIFT, roblox.Vector3.new(200, 1200, 0), START, RISE))
	world.clock = START

	local walker: any = Riders.standOn(world, LIFT, START, -3, 0)
	local command: any = Riders.command()

	for _, mode: string in { "Noclip", "Parked" } do
		local staff: any = Riders.standOn(world, LIFT, START, 3, 0)
		staff.moveMode = mode

		Riders.step(staff, command, world, START + 1)
		local held: number = staff.position.y
		Riders.step(staff, command, world, START + 2)

		if staff.platform ~= 0 then
			return false, `A rider in {mode} still rode {staff.platform}`
		elseif mode == "Parked" and staff.position.y ~= held then
			return false, `A rider in Parked moved from {held} to {staff.position.y} with the lift`
		end
	end

	Riders.step(walker, command, world, START + 1)
	Riders.step(walker, command, world, START + 2)
	if walker.platform ~= LIFT then
		return false, `A walking rider beside them rode {walker.platform}, not the lift`
	end

	return true, nil
end
