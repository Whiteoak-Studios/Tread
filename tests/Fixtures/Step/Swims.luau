--[[
    The swim's trials in the course's pool, each from a fixed state with
    fixed commands and the ending it must reach: the swim depths, floating,
    diving, the crouch depth, a landing in water and the water levels
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Course = require(script.Parent.Course)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local SKIN: number = Constants.SKIN
local VELOCITY_QUANTUM: number = Constants.VELOCITY_QUANTUM
local SETTINGS = Course.settings
local SURFACE: number = Course.surface
local FLOAT: number = Course.float
local EAST: number = Course.east
local WEST: number = Course.west
local SHELF_X: number = 136 -- The shelves' center along X
local DEEP_X: number = 155 -- Open water with no shelf, over the pool's floor
local BELOW_FLOAT: number = 4 -- A diver's feet this far under the surface, deeper than the float depth
local ABOVE_FLOAT: number = 0.5 -- And this far, shallower than it
local DROP: number = 10 -- How far over the surface a falling body starts
local FLOAT_TICKS: number = 80 -- Past the most a swimmer takes to settle at the float depth
local DIVE_TICKS: number = 20
local FALL_TICKS: number = 40 -- Past the most the fall into the water takes
local UP_LOOK: number = math.pi / 3 -- A look up steep enough that forward input rises fast
local DOWN_LOOK: number = -math.pi / 3

type Collision = State.Collision
type Command = State.Command
type Part = Geometry.Part
type State = State.State
type World = State.World

type Trial = {
	name: string,
	run: (collision: Collision) -> string?,
}

local near = Course.near
local is = Course.is

local Swims = {}

-- Feet at rest on a shelf, on the quanta
local function onShelf(shelf: Part): vector
	return vector.create(SHELF_X, Math.quantize(Course.top(shelf) + SKIN), shelf.center.z)
end

-- Why a swimmer did not end at the float depth, or nil
local function floating(label: string, state: State): string?
	return near(`{label}'s feet`, state.position.y, FLOAT)
		or is(`{label}'s mode`, state.mode, "Swim")
		or is(`{label}'s water level`, state.waterLevel, "Surface")
end

local TRIALS: { Trial } = {
	{
		-- A wader in water just under the enter depth keeps wading and one just over it starts to swim, keeping the
		-- game's entry share of its velocity; a swimmer in water just over the leave depth keeps swimming and one just
		-- under it stops
		name = "depths",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)
			local shelves = Course.shelves
			local idle: Command = Course.command()

			local wader: State = Course.state(onShelf(shelves.enterBelow), true)
			Course.advance(wader, world, idle, 1)
			local wading: string? = is("the wader's mode under the enter depth", wader.mode, "Ground")
				or is("the wader's water level", wader.waterLevel, "Wading")
			if wading then
				return wading
			end

			local entering: State = Course.state(onShelf(shelves.enterAbove), true)
			local walk: Command = Course.command()
			walk.yaw = WEST
			walk.forward = 1
			Course.advance(entering, world, walk, 1)
			local entered: string? = is("the mode over the enter depth", entering.mode, "Swim")
				or is("the velocity kept entering", entering.velocity.x, -SETTINGS.walk * SETTINGS.waterEntry)
				or is("grounded entering", entering.grounded, false)
			if entered then
				return entered
			end

			local staying: State = Course.swimmer(onShelf(shelves.leaveAbove))
			Course.advance(staying, world, Course.command(), 1)
			local stayed: string? = is("the mode over the leave depth", staying.mode, "Swim")
			if stayed then
				return stayed
			end

			local leaving: State = Course.swimmer(onShelf(shelves.leaveBelow))
			Course.advance(leaving, world, Course.command(), 1)
			if leaving.mode == "Swim" then
				return "a swimmer in water under the leave depth kept swimming"
			end

			return nil
		end,
	},

	{
		-- An idle swimmer floats at the game's float depth, rising to it from under it and sinking to it from over
		-- it, its head above the water, and stays there
		name = "float",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)

			local under: State = Course.swimmer(vector.create(DEEP_X, SURFACE - BELOW_FLOAT, 0))
			Course.advance(under, world, Course.command(), FLOAT_TICKS)
			local rose: string? = floating("the swimmer from under", under)
			if rose then
				return rose
			end

			local settled: number = under.position.y
			Course.advance(under, world, Course.command(), FLOAT_TICKS)
			local stays: string? = is("the floating feet a while on", under.position.y, settled)
			if stays then
				return stays
			end

			local over: State = Course.swimmer(vector.create(DEEP_X, SURFACE - ABOVE_FLOAT, 6))
			Course.advance(over, world, Course.command(), FLOAT_TICKS)

			return floating("the swimmer from over", over)
		end,
	},

	{
		-- Looking up while swimming ahead rises no higher than the float depth, and looking down dives the swimmer
		-- until its head is under
		name = "dive",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)

			local rising: State = Course.swimmer(vector.create(DEEP_X, SURFACE - BELOW_FLOAT, 12))
			local up: Command = Course.command()
			up.yaw = EAST
			up.pitch = UP_LOOK
			up.forward = 1

			local highest: number = rising.position.y
			for _ = 1, FLOAT_TICKS do
				Course.advance(rising, world, up, 1)
				highest = math.max(highest, rising.position.y)
			end

			if highest > FLOAT + Course.quantum then
				return `swimming up rose to {highest}, over the float depth at {FLOAT}`
			end

			local surfaced: string? = floating("the swimmer swimming up", rising)
			if surfaced then
				return surfaced
			end

			local diving: State = Course.swimmer(vector.create(DEEP_X, FLOAT, 18))
			local down: Command = Course.command()
			down.yaw = WEST
			down.pitch = DOWN_LOOK
			down.forward = 1
			Course.advance(diving, world, down, DIVE_TICKS)

			if diving.position.y >= FLOAT then
				return `the dive ended at {diving.position.y}, no deeper than the float depth at {FLOAT}`
			end

			return is("the diver's mode", diving.mode, "Swim")
				or is("the diver's water level", diving.waterLevel, "Under")
		end,
	},

	{
		-- Feet deeper than the game's crouch depth refuse a crouch, and stand a crouched wader up, while feet shallower
		-- than it crouch
		name = "crouchDepth",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)
			local shelves = Course.shelves
			local crouch: Command = Course.command()
			crouch.crouch = true
			crouch.pressed.crouch = true

			local deep: State = Course.state(onShelf(shelves.deep), true)
			Course.advance(deep, world, crouch, 1)
			local refused: string? = is("the deep wader's posture", deep.posture, "Stand")
				or is("the deep wader's mode", deep.mode, "Ground")
			if refused then
				return refused
			end

			local held: State = Course.state(onShelf(shelves.deep), true)
			held.posture = "Crouch"
			local holding: Command = Course.command()
			holding.crouch = true
			Course.advance(held, world, holding, 1)
			local stood: string? = is("the crouched deep wader's posture", held.posture, "Stand")
			if stood then
				return stood
			end

			local shallow: State = Course.state(onShelf(shelves.shallow), true)
			crouch.pressed.crouch = true
			Course.advance(shallow, world, crouch, 1)

			return is("the shallow wader's posture", shallow.posture, "Crouch")
		end,
	},

	{
		-- A fall that ends in deep water lands with water as its material, counting the landing, and keeps the game's
		-- entry share of its fall
		name = "waterLanding",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)
			local state: State = Course.state(vector.create(DEEP_X, SURFACE + DROP, 24), false)

			local landing: number = 0
			for _ = 1, FALL_TICKS do
				landing = Course.advance(state, world, Course.command(), 1)
				if landing > 0 then
					break
				end
			end

			if landing <= 0 then
				return "the fall into the water counted no landing"
			end

			local kept: number = landing * SETTINGS.waterEntry
			if math.abs(-state.velocity.y - kept) > VELOCITY_QUANTUM then
				return `it kept a fall of {-state.velocity.y}, where {kept} was expected`
			end

			return is("the mode", state.mode, "Swim")
				or is("the landing's material", state.groundMaterial, Enum.Material.Water)
				or is("the landings", state.lands, 1)
		end,
	},

	{
		-- The water level the state word carries: dry out of the water, wading on a shelf, at the surface floating
		-- and under while the eye is below the surface
		name = "levels",
		run = function (collision: Collision): string?
			local world: World = Course.world(collision)

			local dry: State = Course.state(vector.create(Course.approach, Course.resting, 0), true)
			dry.waterLevel = "Under"
			Course.advance(dry, world, Course.command(), 1)
			local outside: string? = is("the level out of the water", dry.waterLevel, "Dry")
			if outside then
				return outside
			end

			local wader: State = Course.state(onShelf(Course.shelves.shallow), true)
			Course.advance(wader, world, Course.command(), 1)
			local wading: string? = is("the wader's level", wader.waterLevel, "Wading")
			if wading then
				return wading
			end

			local floater: State = Course.swimmer(vector.create(DEEP_X, FLOAT, 30))
			Course.advance(floater, world, Course.command(), 1)
			local surface: string? = is("the floater's level", floater.waterLevel, "Surface")
			if surface then
				return surface
			end

			local diver: State = Course.swimmer(vector.create(DEEP_X, SURFACE - BELOW_FLOAT, 36))
			local down: Command = Course.command()
			down.pitch = DOWN_LOOK
			down.forward = 1
			Course.advance(diver, world, down, 1)

			return is("the diver's level", diver.waterLevel, "Under")
		end,
	},

	{
		-- A water query that gives anything but a finite height or nil is refused, naming what it gave
		name = "refusesWater",
		run = function (collision: Collision): string?
			local answers: { any } = { "deep", 0 / 0, math.huge, true }

			for _, answer: any in answers do
				local world: World = Course.world(collision)
				world.water = function (_: number, _: number): number?
					return answer
				end

				local state: State = Course.state(vector.create(DEEP_X, SURFACE, 0), false)
				local ran: boolean, message: any = pcall(Course.advance, state, world, Course.command(), 1)
				if ran then
					return `the step took a water query that gave {answer}`
				elseif not string.find(`{message}`, "must give a finite height or nil", 1, true) then
					return `the step's refusal of a water query that gave {answer} was something else: {message}`
				end
			end

			return nil
		end,
	},
}

-- Every trial's name, in the order a live scenario runs them
Swims.names = {} :: { string }

for _, trial: Trial in TRIALS do
	table.insert(Swims.names, trial.name)
end

--[[
    Runs one trial by name over a collision, Lune's fixture casts over the
    course when none is given, and gives whether it ended where it should,
    with the reason when it did not
--]]

function Swims.run(name: string, collision: Collision?): (boolean, string | nil)
	return Course.run(TRIALS, name, collision)
end

return Swims
