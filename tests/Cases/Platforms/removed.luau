--[[
    A rider whose platform is taken out is dropped on the next step and
    falls from where it stood, and a rider of a world left holding no
    platform at all is dropped the same way
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"

local KEPT: number = 2
local TAKEN: number = 3
local START: number = 70

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local world: any = Riders.world()
	Platforms.add(world, Riders.lift(KEPT, roblox.Vector3.new(300, 1200, 0), START, 0))
	local remove: () -> () = Platforms.add(world, Riders.lift(TAKEN, roblox.Vector3.new(200, 1200, 0), START, 0))
	world.clock = START

	local body: any = Riders.standOn(world, TAKEN, START, 0, 0)
	local command: any = Riders.command()
	Riders.step(body, command, world, START + 1)
	if body.platform ~= TAKEN then
		return false, `Before its platform went the rider stood on {body.platform}`
	end

	remove()
	local stood: number = body.position.y
	Riders.step(body, command, world, START + 2)
	if body.platform ~= 0 then
		return false, `After its platform went the rider still rode {body.platform}`
	elseif body.grounded or body.mode ~= "Air" then
		return false, `With its platform gone the rider was grounded {body.grounded} in {body.mode}, not off the ground`
	end

	Riders.step(body, command, world, START + 3)
	if not (body.position.y < stood) then
		return false, `With its platform gone the rider stood at {body.position.y}, not falling from {stood}`
	end

	-- A world whose last platform went drops its rider too
	local lone: any = Riders.world()
	local removeLone: () -> () = Platforms.add(lone, Riders.lift(TAKEN, roblox.Vector3.new(200, 1200, 0), START, 0))
	lone.clock = START

	local rider: any = Riders.standOn(lone, TAKEN, START, 0, 0)
	removeLone()
	Riders.step(rider, command, lone, START + 1)
	if rider.platform ~= 0 then
		return false, `In a world left with no platform the rider still rode {rider.platform}`
	end

	return true, nil
end
