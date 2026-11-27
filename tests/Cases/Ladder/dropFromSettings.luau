--[[
    The game's ladder drop sets both its uses: with a look 40° below level,
    a drop of 30° keeps a grounded body off the ladder and climbs a climber
    down, and a drop of 50° mounts the body and climbs the climber up
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local DEGREES: number = math.pi / 180
local LOOK: number = -40 * DEGREES -- Radians, a look between the two drops
local START_X: number = 191.5 -- Feet a few ticks' walk short of the course's ladder
local MOUNT_TICKS: number = 6 -- Enough to walk from there into the box and mount
local CLIMB_TICKS: number = 20 -- A second's climb at a level look, which leaves the body partway up
local LOOK_TICKS: number = 5 -- Ticks climbed with the look below level

-- A drop, and whether the look below level mounts a grounded body and keeps a climber climbing up under it
type Drop = { degrees: number, mounts: boolean, climbsUp: boolean }

local DROPS: { Drop } = {
	{ degrees = 30, mounts = false, climbsUp = false }, -- Frontier Zero's, which the look passes
	{ degrees = 50, mounts = true, climbsUp = true },
}

return function (): (boolean, string | nil)
	for _, drop: Drop in DROPS do
		local globals: any = Environment.load(GLOBALS)
		local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
		local fixtures: any = globals.game:GetService("ServerScriptService").Fixtures
		local Course: any = globals.require(fixtures.Step.Course)
		local World: any = globals.require(tread.Step.World)

		-- The settings table the course's worlds read
		Course.settings.ladderDrop = drop.degrees

		local world: any = Course.world()
		World.addLadder(world, Course.ladder.cframe, Course.ladder.size)

		-- A body on the ground walking into the ladder with the look below level
		local walker: any = Course.state(vector.create(START_X, Course.resting, 0), true)
		local walk: any = Course.command()
		walk.yaw = Course.east
		walk.forward = 1
		walk.pitch = LOOK
		Course.advance(walker, world, walk, MOUNT_TICKS)

		if (walker.mode == "Ladder") ~= drop.mounts then
			return false, `With a drop of {drop.degrees}° the body looking 40° down ended {walker.mode}`
		end

		-- A climber partway up at a level look, then looking below level
		local climber: any = Course.state(vector.create(START_X, Course.resting, 0), true)
		local climb: any = Course.command()
		climb.yaw = Course.east
		climb.forward = 1
		Course.advance(climber, world, climb, MOUNT_TICKS + CLIMB_TICKS)

		if climber.mode ~= "Ladder" then
			return false, `With a drop of {drop.degrees}° the climber at a level look ended {climber.mode}`
		end

		local height: number = climber.position.y
		climb.pitch = LOOK
		Course.advance(climber, world, climb, LOOK_TICKS)

		local moved: string = `from {height} to {climber.position.y}`
		if climber.mode ~= "Ladder" then
			return false, `With a drop of {drop.degrees}° the climber looking 40° down ended {climber.mode}`
		elseif (climber.position.y > height) ~= drop.climbsUp then
			return false, `With a drop of {drop.degrees}° looking 40° down moved the climber {moved}`
		end
	end

	return true, nil
end
