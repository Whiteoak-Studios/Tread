--[[
    The ladder's trials on the course, each from a fixed state with fixed
    commands and the ending it must reach: mounting, climbing to the top and
    back down, the jump off, a ladder taken out, and the lowest id winning
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Course = require(script.Parent.Course)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local SKIN: number = Constants.SKIN
local SETTINGS = Course.settings
local GROUND: number = Course.resting
local EAST: number = Course.east
local WEST: number = Course.west
local START_X: number = 191.5 -- Feet a few ticks' walk short of the ladder's box
local MOUNT_TICKS: number = 6 -- Enough to walk from there into the box and mount
local CLIMB_TICKS: number = 20 -- A second's climb, which leaves the body halfway up
local TOP_TICKS: number = 150 -- Past the most a climb up the whole ladder takes
local DOWN_TICKS: number = 80 -- Past the most a climb down from halfway takes
local LOOK_DOWN: number = -math.pi / 4 -- Further below level than the look that keeps the climb's up part

type Collision = State.Collision
type Command = State.Command
type LadderPlace = Course.LadderPlace
type State = State.State
type World = State.World

type Trial = {
	name: string,
	run: (collision: Collision) -> string?,
}

local near = Course.near
local is = Course.is

local Ladders = {}

-- A world over the course with the ladders given registered, and the closure that takes out the first
local function withLadders(collision: Collision, places: { LadderPlace }): (World, () -> ())
	local world: World = Course.world(collision)
	local removeFirst: () -> () = function () end

	for index: number, place: LadderPlace in places do
		local remove: () -> () = World.addLadder(world, place.cframe, place.size)
		if index == 1 then
			removeFirst = remove
		end
	end

	return world, removeFirst
end

-- A body walking along +X into the ladder at z from short of it, and the command walking it
local function walker(z: number): (State, Command)
	local state: State = Course.state(vector.create(START_X, GROUND, z), true)
	local order: Command = Course.command()
	order.yaw = EAST
	order.forward = 1

	return state, order
end

-- Steps a body until it is on a ladder or the ticks run out, and gives why it never got there, or nil
local function mount(state: State, world: World, order: Command): string?
	for _ = 1, MOUNT_TICKS do
		Course.advance(state, world, order, 1)
		if state.mode == "Ladder" then
			return nil
		end
	end

	return `it walked into the ladder's box and was still {state.mode} after {MOUNT_TICKS} ticks`
end

-- A body halfway up the ladder, and the command it climbed on
local function halfway(world: World): (State, Command, string?)
	local state: State, order: Command = walker(0)
	local failure: string? = mount(state, world, order)
	if not failure then
		Course.advance(state, world, order, CLIMB_TICKS)
		failure = is("the mode halfway up", state.mode, "Ladder")
	end

	return state, order, failure
end

local TRIALS: { Trial } = {
	{
		-- Walking into the box while facing it mounts the ladder, climbing holds with no gravity, and climbing up the
		-- whole ladder steps off ahead onto the block's top at its top
		name = "climbTop",
		run = function (collision: Collision): string?
			local world: World = withLadders(collision, { Course.ladder })
			local id: number = world.ladders[1].id
			local state: State, order: Command, failure: string? = halfway(world)
			if failure then
				return failure
			end

			local mounted: string? = is("the ladder climbed", state.ladder, id)
			if mounted then
				return mounted
			end

			-- With no input the climber holds where it is
			local height: number = state.position.y
			order.forward = 0
			Course.advance(state, world, order, 10)
			local held: string? = is("the height it held", state.position.y, height)
				or is("the mode it held", state.mode, "Ladder")
			if held then
				return held
			end

			order.forward = 1
			for _ = 1, TOP_TICKS do
				Course.advance(state, world, order, 1)
				if state.mode ~= "Ladder" then
					break
				end
			end

			local off: string? = is("the mode off the top", state.mode, "Ground")
				or is("the ladder off the top", state.ladder, 0)
			if off then
				return off
			end

			-- On the top, a skin or less over it where the ground snap leaves a body resting, its hull's front past the
			-- block's face
			local at: vector = state.position
			if at.y < Course.blockTop or at.y > Course.blockTop + SKIN + Course.quantum then
				return `it stood at y {at.y}, not on the top at {Course.blockTop}`
			elseif at.x + SETTINGS.radius <= Course.blockFace then
				return `its hull's front stood at x {at.x + SETTINGS.radius}, short of the top past {Course.blockFace}`
			end

			return nil
		end,
	},

	{
		-- Halfway up, a look far enough down climbs down along it to stand on the ground at the foot, and from halfway
		-- up again back input moves back off the ladder, which drops the body to the floor
		name = "climbOff",
		run = function (collision: Collision): string?
			local world: World = withLadders(collision, { Course.ladder })
			local state: State, order: Command, failure: string? = halfway(world)
			if failure then
				return failure
			end

			order.pitch = LOOK_DOWN
			for _ = 1, DOWN_TICKS do
				Course.advance(state, world, order, 1)
				if state.mode ~= "Ladder" then
					break
				end
			end

			local down: string? = is("the mode at the foot", state.mode, "Ground")
				or is("the ladder at the foot", state.ladder, 0)
				or near("y at the foot", state.position.y, GROUND)
			if down then
				return down
			end

			-- Looking down at the foot, the walk into the box steps nobody back on
			Course.advance(state, world, order, 2)
			local stayed: string? = is("the mode looking down at the foot", state.mode, "Ground")
			if stayed then
				return stayed
			end

			local back: State, backOrder: Command, again: string? = halfway(world)
			if again then
				return again
			end

			backOrder.forward = -1
			Course.advance(back, world, backOrder, 10)
			local off: string? = is("the ladder after backing off", back.ladder, 0)
			if off then
				return off
			end

			Course.advance(back, world, backOrder, DOWN_TICKS)

			return is("grounded after backing off", back.grounded, true)
				or near("y after backing off", back.position.y, GROUND)
		end,
	},

	{
		-- A jump press on the ladder launches the body off along its look at the game's ladder jump, and counts a jump
		name = "jumpOff",
		run = function (collision: Collision): string?
			local world: World = withLadders(collision, { Course.ladder })
			local state: State, order: Command, failure: string? = halfway(world)
			if failure then
				return failure
			end

			order.forward = 0
			order.yaw = WEST
			order.jump, order.pressed.jump = true, true
			Course.advance(state, world, order, 1)

			return is("the mode after the jump", state.mode, "Air")
				or is("the ladder after the jump", state.ladder, 0)
				or is("the jumps", state.jumps, 1)
				or is("the launch's x", state.velocity.x, -SETTINGS.ladderJump)
				or is("the launch's y", state.velocity.y, 0)
		end,
	},

	{
		-- A ladder taken out while climbed drops the body into the air, and it falls to the floor
		name = "removed",
		run = function (collision: Collision): string?
			local world: World, remove: () -> () = withLadders(collision, { Course.ladder })
			local state: State, order: Command, failure: string? = halfway(world)
			if failure then
				return failure
			end

			remove()
			Course.advance(state, world, order, 1)
			local dropped: string? = is("the mode once taken out", state.mode, "Air")
				or is("the ladder once taken out", state.ladder, 0)
			if dropped then
				return dropped
			end

			Course.advance(state, world, order, DOWN_TICKS)

			return is("grounded after the drop", state.grounded, true)
		end,
	},

	{
		-- A body touching two ladders climbs the one with the lower id
		name = "lowestId",
		run = function (collision: Collision): string?
			local world: World = withLadders(collision, { Course.ladder, Course.beside })
			local lowest: number = math.min(world.ladders[1].id, world.ladders[2].id)
			local between: number = Course.beside.cframe.Position.Z / 2 -- Where the two boxes overlap along Z
			local state: State, order: Command = walker(between)
			local failure: string? = mount(state, world, order)
			if failure then
				return failure
			end

			Course.advance(state, world, order, CLIMB_TICKS)

			return is("the ladder climbed", state.ladder, lowest)
		end,
	},

	{
		-- No ladder is mounted backing into its box, facing away, or downed
		name = "refusesMount",
		run = function (collision: Collision): string?
			local world: World = withLadders(collision, { Course.ladder })

			-- Feet at the box's edge, the hull already in it
			local inside: number = Course.blockFace - SETTINGS.radius - SKIN

			local backing: State = Course.state(vector.create(inside, GROUND, 0), true)
			local backward: Command = Course.command()
			backward.yaw = WEST
			backward.forward = -1
			Course.advance(backing, world, backward, 1)
			local backed: string? = is("the mode backing in", backing.mode, "Ground")
			if backed then
				return backed
			end

			local away: State = Course.state(vector.create(inside, GROUND, 0), true)
			local turned: Command = Course.command()
			turned.yaw = WEST
			turned.forward = 1
			Course.advance(away, world, turned, 1)
			local facingAway: string? = is("the mode facing away", away.mode, "Ground")
			if facingAway then
				return facingAway
			end

			local downed: State = Course.state(vector.create(inside, GROUND, 0), true)
			downed.posture = "Downed"
			local crawl: Command = Course.command()
			crawl.yaw = EAST
			crawl.forward = 1
			Course.advance(downed, world, crawl, 1)

			return is("the downed body's mode", downed.mode, "Ground")
		end,
	},
}

-- Every trial's name, in the order a live scenario runs them
Ladders.names = {} :: { string }

for _, trial: Trial in TRIALS do
	table.insert(Ladders.names, trial.name)
end

--[[
    Runs one trial by name over a collision, Lune's fixture casts over the
    course when none is given, and gives whether it ended where it should,
    with the reason when it did not
--]]

function Ladders.run(name: string, collision: Collision?): (boolean, string | nil)
	return Course.run(TRIALS, name, collision)
end

return Ladders
