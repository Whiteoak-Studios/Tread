--[[
    The read-only world the step reads: the game's step settings, casts,
    water and rules, the time a tick covers, the ladders turned into numbers
    once, and the live players and NPCs each tick
--]]

--!strict
--!native
local Engine = require(script.Parent.Engine)
local Hash = require(script.Parent.Parent.Codec.Hash)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local LADDER_IDS: number = 2 ^ 16 -- The ids OwnerState's u16 ladder field holds, 0 among them meaning none
local F64_BYTES: number = 8
local BOX_NUMBERS: number = 15 -- A box's center, its three axes and its size, three numbers each

-- One box's numbers, which a ladder's id hashes, reused by every registration
local Scratch: buffer = buffer.create(BOX_NUMBERS * F64_BYTES)

type Box = State.Box
type Collision = State.Collision
type Ladder = State.Ladder
type Rules = State.Rules
type Settings = State.Settings
type State = State.State
type Water = State.Water
type World = State.World

local World = {}

--[[
    A world for one realm's bodies, its time step from the shared table's
    simulation rate, with no ladders and no live bodies yet

    @ rate | rates.simulation, ticks a second
--]]

function World.new(
	settings: Settings,
	rate: number,
	collision: Collision,
	water: Water?,
	rules: Rules,
	isServer: boolean
): World
	if type(rate) ~= "number" or not (rate > 0) or rate == math.huge then
		error(`A world's simulation rate must be a finite number above 0, and got {rate}`)
	elseif type(rules) ~= "function" then
		error(`A world's rules must be a function, and got a {typeof(rules)}`)
	end

	return {
		settings = settings,
		collision = collision,
		water = water,
		rules = rules,
		isServer = isServer,
		delta = 1 / rate,
		tick = 0,
		leanShift = Engine.toVector(settings.leanShift),
		ladders = {},
		bodies = {},
	}
end

-- Writes a vector's numbers at the 1/512 quantum into the scratch buffer from offset, and gives the next offset
local function put(value: vector, offset: number): number
	-- Adding 0 turns a -0 into 0, so the sign of a zero never gives two realms two ids
	buffer.writef64(Scratch, offset, Math.quantize(value.x) + 0)
	buffer.writef64(Scratch, offset + F64_BYTES, Math.quantize(value.y) + 0)
	buffer.writef64(Scratch, offset + 2 * F64_BYTES, Math.quantize(value.z) + 0)

	return offset + 3 * F64_BYTES
end

--[[
    A ladder's id from its own box: the low 16 bits of the FNV-1a over its
    numbers at the 1/512 quantum, by their 8 bytes, with 0 skipped to 1
--]]

local function idOf(box: Box): number
	local length: number = put(box.center, 0)
	length = put(box.right, length)
	length = put(box.up, length)
	length = put(box.look, length)
	length = put(box.size, length)

	local id: number = Hash.range(Scratch, 0, length) % LADDER_IDS
	if id == 0 then
		id += 1
	end

	return id
end

--[[
    Registers a ladder, its CFrame turned into the step's numbers once, and
    gives back the closure that removes it. Its id comes from its own box,
    so two realms that register the same ladders in any order give each one
    the same id, and a ladder whose id another already holds is refused
--]]

function World.addLadder(world: World, cframe: CFrame, size: Vector3): () -> ()
	if not (size.X > 0 and size.Y > 0 and size.Z > 0) then
		error(`A ladder needs a size above 0 on every axis, and got {size}`)
	end

	local box: Box = Engine.box(cframe, size)
	local id: number = idOf(box)

	for _, other: Ladder in world.ladders do
		if other.id == id then
			local this: string = `The ladder at {box.center} sized {box.size}`
			local holder: string = `the ladder at {other.box.center} sized {other.box.size}`
			error(`{this} takes the id {id}, which {holder} already holds`)
		end
	end

	local ladder: Ladder = { id = id, box = box }
	table.insert(world.ladders, ladder)

	return function ()
		local index: number? = table.find(world.ladders, ladder)
		if index then
			table.remove(world.ladders, index)
		end
	end
end

--[[
    Hands the world the live players and NPCs this tick, each body's state
    where it stands now, so each step blocks against where the bodies before
    it already moved
--]]

function World.setBodies(world: World, bodies: { State })
	if type(bodies) ~= "table" then
		error(`A world's bodies must be a list of states, and got a {typeof(bodies)}`)
	end

	world.bodies = bodies
end

return World
