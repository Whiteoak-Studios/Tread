--[[
    Through a seeded scene of moving, crouching, swimming and teleporting
    bodies, walls added, removed and moved, and memory flipped, every slice
    gives memory off's verdicts, counts and fail-opens, on fewer engine rays
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SEED: number = 20261119 -- Park and Miller's generator's start, any whole number from 1 below its modulus
local MULTIPLIER: number = 16807
local MODULUS: number = 2147483647
local STEPS: number = 400
local STRAY: number = 9 -- Studs a walk moves a body across each axis, centered on 0
local SPEED: number = 20 -- A walking body's velocity, studs a second for each stud of its step
local LOW: vector = vector.create(-60, 0, -80) -- The field's corners every body and added wall stays inside
local HIGH: vector = vector.create(60, 0, 40)
local SLICE: number = 60 -- Seconds a full slice may take, so neither side's tests run out on a loaded machine
local LYING_SHARE: number = SLICE -- The whole slice, so each slice tests its sleepers first in one order
local DELAYS: { number } = { 1 / 60, 1 / 30, 0.1, 0.2 } -- Seconds from one slice to the next, the last past the fail-open
local SLICINGS: number = 6 -- A step runs no slice for 0 of these, a starved one for 1 and a full one for the rest
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }
local SIZES: { vector } =
	{ vector.create(16, 6, 1), vector.create(8, 4, 1), vector.create(10, 8, 2), vector.create(1, 8, 20) }
local TURNS: { number } = { -0.6, -0.3, 0, 0.3, 0.6 } -- An added wall's turn about the vertical, in radians
local WALL_HEIGHT: number = 2 -- An added or moved wall's center above the ground
local PUSH: vector = vector.create(0, 0, 1) -- Added to a pushed body's velocity, so a zero step still pushes it
local OFF_STEPS: number = 4 -- The most steps memory stays off once the scene turns it off
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false

-- Each body by its name and kind, where it starts, and whether it is a viewer
local BODIES: { { name: string, kind: string, at: vector, sees: boolean } } = {
	{ name = "North", kind = "Player", at = vector.create(0, 0, 0), sees = true },
	{ name = "East", kind = "Player", at = vector.create(40, 0, 10), sees = true },
	{ name = "West", kind = "Player", at = vector.create(-30, 0, -20), sees = true },
	{ name = "Runner", kind = "Player", at = vector.create(0, 0, -40), sees = false },
	{ name = "Lurker", kind = "Player", at = vector.create(20, 0, -35), sees = false },
	{ name = "Crawler", kind = "Player", at = vector.create(-25, 0, -50), sees = false },
	{ name = "Swimmer", kind = "Player", at = vector.create(10, 0, 30), sees = false },
	{ name = "Sleeper", kind = "Sleeper", at = vector.create(-10, 0, -60), sees = false },
	{ name = "Peeker", kind = "Player", at = vector.create(0, 0, 70), sees = false },
	{ name = "Strider", kind = "Player", at = vector.create(-40, 0, 60), sees = true },
	{ name = "Mark", kind = "Player", at = vector.create(-40, 0, 90), sees = false },
	{ name = "Croucher", kind = "Player", at = vector.create(-70, 0, 0), sees = false },
}

--[[
    Three fixed setups no other change walks, turns or moves. The pushed
    peeker shows past its wall only while an origin viewer's look-ahead is
    the clamp's top; the strider's leading ray clears its wall to the mark
    only while its velocity drifts it; the croucher shows its head over a
    low wall to the ghost's ground-level eye only while it stands, dry. So
    each look-ahead change, stride, posture and swim turns an answer
--]]

local FIXED: { [string]: boolean } = { Peeker = true, Strider = true, Mark = true, Croucher = true }
local PEEK: vector = vector.create(0, 0, 40)
local STRIDE: vector = vector.create(60, 0, 0)
local FIXED_WALLS: { { at: vector, size: vector } } = {
	{ at = vector.create(10, 5, 55), size = vector.create(40, 10, 1) },
	{ at = vector.create(-40, 5, 75), size = vector.create(20, 10, 1) },
	{ at = vector.create(-35, 1, 0), size = vector.create(1, 2, 8) },
}

--[[
    The walls the scene starts with: where each stands, its size and its
    turn about the vertical, in radians, the low ones topping out between a
    standing target's head and a crouched one's
--]]

local WALLS: { { at: vector, size: vector, turn: number } } = {
	{ at = vector.create(0, 2, -20), size = vector.create(40, 4, 1), turn = 0 },
	{ at = vector.create(15, 1.5, -28), size = vector.create(16, 3, 1), turn = 0.4 },
	{ at = vector.create(-20, 3, -35), size = vector.create(10, 8, 2), turn = -0.3 },
	{ at = vector.create(5, 1.75, 18), size = vector.create(24, 3.5, 1), turn = 0.1 },
	{ at = vector.create(25, 3, 0), size = vector.create(1, 8, 20), turn = 0 },
}

-- Every change a step may make, each of which the seed must reach
local EVENT_NAMES: { string } = {
	"walk",
	"stop",
	"viewerWalk",
	"viewerStop",
	"posture",
	"swim",
	"teleport",
	"wallAdded",
	"wallRemoved",
	"wallMoved",
	"intoWall",
	"memory",
	"life",
	"sleep",
	"leave",
	"push",
	"lookAhead",
	"stride",
	"crouch",
	"dive",
}

-- What the roll picks from, still bodies and their postures oftener than walks, and "none" for no change
local DECK: { string } = {
	"walk",
	"walk",
	"stop",
	"stop",
	"stop",
	"viewerWalk",
	"viewerStop",
	"viewerStop",
	"posture",
	"posture",
	"posture",
	"swim",
	"swim",
	"teleport",
	"wallAdded",
	"wallRemoved",
	"wallMoved",
	"intoWall",
	"memory",
	"life",
	"sleep",
	"leave",
	"push",
	"push",
	"lookAhead",
	"stride",
	"stride",
	"crouch",
	"crouch",
	"dive",
	"dive",
	"none",
	"none",
	"none",
}

-- One harness and what it holds, built the same on both sides
type Side = {
	harness: any,
	AntiEsp: any,
	folder: any,
	viewers: { any },
	slots: { [string]: number },
	walls: { any }, -- Each wall's part, in the order the scene's list holds them
}

-- A Block part standing at a place in a folder, turned about the vertical
local function wallPart(folder: any, at: vector, size: vector, turn: number): any
	local part: any = roblox.Instance.new("Part")
	part.Size = roblox.Vector3.new(size.x, size.y, size.z)
	part.CFrame = roblox.CFrame.new(at.x, at.y, at.z) * roblox.CFrame.Angles(0, turn, 0)
	part.Parent = folder

	return part
end

return function (): (boolean, string | nil)
	local seed: number = SEED
	local function roll(count: number): number
		seed = seed * MULTIPLIER % MODULUS

		return seed % count
	end

	local function side(remember: boolean): Side
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new(function (_: any, server: any)
			server.antiEsp.lyingShare = LYING_SHARE

			-- At the top of the look-ahead's clamp, so a viewer losing its connection swings to the bottom
			server.bots.rtt = server.antiEsp.lookAheadMax
		end)
		Harness.AntiEsp.useMemory(remember)

		local folder: any = harness.server.antiEsp.include[1]
		harness.wall = Harness.parts(folder)

		local built: Side = {
			harness = harness,
			AntiEsp = Harness.AntiEsp,
			folder = folder,
			viewers = {},
			slots = {},
			walls = {},
		}

		for _, wall in WALLS do
			table.insert(built.walls, wallPart(folder, wall.at, wall.size, wall.turn))
		end

		-- Kept out of the walls the scene's changes pick from, as the fixed bodies are kept out of its bodies
		for _, wall in FIXED_WALLS do
			wallPart(folder, wall.at, wall.size, 0)
		end

		for _, body in BODIES do
			local slot: number = harness:body(body.kind, body.at)
			built.slots[body.name] = slot

			if body.sees then
				table.insert(built.viewers, harness:viewer(body.name, slot))
			end
		end

		harness.states[built.slots.Peeker].velocity = PEEK

		table.insert(built.viewers, harness:viewer("Ghost", nil))

		return built
	end

	local plain: Side = side(OFF)
	local remembering: Side = side(ON)

	local function both(change: (built: Side) -> ())
		change(plain)
		change(remembering)
	end

	-- Every body's slot in the order each run asks, the same on both sides, and the movable ones
	local asked: { number } = {}
	local targets: { string } = {}
	local walkers: { string } = {}
	local seeing: { string } = {}
	for _, body in BODIES do
		table.insert(asked, plain.slots[body.name])

		if FIXED[body.name] then
			continue
		end

		table.insert(walkers, body.name)

		if body.sees then
			table.insert(seeing, body.name)
		elseif body.kind == "Player" then
			table.insert(targets, body.name)
		end
	end

	local connected: { [string]: boolean } = {}
	for _, viewer: any in plain.viewers do
		connected[viewer.key.Name] = true
	end

	local reached: { [string]: number } = {}
	for _, name: string in EVENT_NAMES do
		reached[name] = 0
	end

	local function inField(at: vector): vector
		return vector.create(math.clamp(at.x, LOW.x, HIGH.x), at.y, math.clamp(at.z, LOW.z, HIGH.z))
	end

	local function stray(): vector
		return vector.create(roll(STRAY) - STRAY // 2, 0, roll(STRAY) - STRAY // 2)
	end

	-- A spot anywhere in the field, at a height
	local function spot(height: number): vector
		local span: vector = HIGH - LOW

		return vector.create(LOW.x + roll(span.x), height, LOW.z + roll(span.z))
	end

	-- A body walked a step, with the velocity that step gives, its viewer's place with it
	local function walk(name: string)
		local step: vector = stray()
		local slot: number = plain.slots[name]
		local at: vector = inField(plain.harness.states[slot].position + step)

		both(function (built: Side)
			local viewer: any = nil
			for _, each: any in built.viewers do
				if each.slot == slot then
					viewer = each
				end
			end

			built.harness:move(slot, at, viewer)
			built.harness.states[slot].velocity = step * SPEED
		end)
	end

	local function setState(name: string, field: string, value: any)
		local slot: number = plain.slots[name]
		both(function (built: Side)
			built.harness.states[slot][field] = value
		end)
	end

	-- The steps left before memory, turned off by the scene, comes on again
	local offFor: number = 0

	-- One change to the world, the same on both sides but for memory's own switch
	local function happen(event: string)
		local target: string = targets[roll(#targets) + 1]
		local viewer: string = seeing[roll(#seeing) + 1]

		if event == "walk" then
			walk(target)
		elseif event == "stop" then
			setState(target, "velocity", vector.zero)
		elseif event == "viewerWalk" then
			walk(viewer)
		elseif event == "viewerStop" then
			setState(viewer, "velocity", vector.zero)
		elseif event == "posture" then
			setState(target, "posture", POSTURES[roll(#POSTURES) + 1])
		elseif event == "swim" then
			local slot: number = plain.slots[target]
			local swimming: boolean = plain.harness.states[slot].mode == "Swim"
			setState(target, "mode", swimming and "Ground" or "Swim")
		elseif event == "teleport" then
			local name: string = walkers[roll(#walkers) + 1]
			local slot: number = plain.slots[name]
			local at: vector = spot(0)

			both(function (built: Side)
				local moved: any = nil
				for _, each: any in built.viewers do
					if each.slot == slot then
						moved = each
					end
				end

				built.harness:move(slot, at, moved)
				built.harness.states[slot].velocity = vector.zero
				built.AntiEsp.moved(slot)
			end)
		elseif event == "wallAdded" then
			local at: vector = spot(WALL_HEIGHT)
			local size: vector = SIZES[roll(#SIZES) + 1]
			local turn: number = TURNS[roll(#TURNS) + 1]

			both(function (built: Side)
				local part: any = wallPart(built.folder, at, size, turn)
				table.insert(built.walls, part)
				built.folder.DescendantAdded:Fire(part)
			end)
		elseif event == "wallRemoved" and #plain.walls > 0 then
			local index: number = roll(#plain.walls) + 1

			both(function (built: Side)
				local part: any = table.remove(built.walls, index)
				built.folder.DescendantRemoving:Fire(part)
				part.Parent = nil
			end)
		elseif event == "wallMoved" and #plain.walls > 0 then
			local index: number = roll(#plain.walls) + 1
			local at: vector = spot(WALL_HEIGHT)
			local turn: number = TURNS[roll(#TURNS) + 1]

			both(function (built: Side)
				local part: any = built.walls[index]
				part.CFrame = roblox.CFrame.new(at.x, at.y, at.z) * roblox.CFrame.Angles(0, turn, 0)
				built.AntiEsp.occludersChanged()
			end)
		elseif event == "intoWall" and #plain.walls > 0 then
			local index: number = roll(#plain.walls) + 1
			local slot: number = plain.slots[viewer]
			local center: any = plain.walls[index].CFrame.Position
			local at: vector = vector.create(center.X, 0, center.Z)

			both(function (built: Side)
				for _, each: any in built.viewers do
					if each.slot == slot then
						built.harness:move(slot, at, each)
					end
				end

				built.AntiEsp.moved(slot)
			end)
		elseif event == "memory" then
			-- Off for a few steps, the strider's drift changing while it is, so turning it on must drop what it kept
			if not remembering.AntiEsp.memoryOn() then
				return
			end

			remembering.AntiEsp.useMemory(OFF)
			offFor = roll(OFF_STEPS) + 1
			happen("stride")
		elseif event == "life" then
			-- The harness's new life takes every other free slot of the kind in turn, which a sleeper can't past the reserve
			local slot: number = plain.slots[target]
			local _, entry: any = plain.harness.Slots.get(slot)
			if entry.kind == "Sleeper" then
				return
			end

			both(function (built: Side)
				built.harness:reborn(slot)
			end)
		elseif event == "sleep" then
			local slot: number = plain.slots.Crawler
			local _, entry: any = plain.harness.Slots.get(slot)
			local kind: string = entry.kind == "Sleeper" and "Player" or "Sleeper"

			both(function (built: Side)
				built.harness.Slots.setEntry(slot, { kind = kind, rig = "A" })
			end)
		elseif event == "leave" then
			local index: number = roll(#plain.viewers) + 1
			both(function (built: Side)
				built.AntiEsp.leave(built.viewers[index].key)
			end)
		elseif event == "push" then
			setState(target, "velocity", stray() * SPEED + PUSH)
		elseif event == "stride" then
			local striding: boolean = plain.harness.states[plain.slots.Strider].velocity ~= vector.zero
			setState("Strider", "velocity", striding and vector.zero or STRIDE)
		elseif event == "crouch" then
			setState("Croucher", "posture", POSTURES[roll(#POSTURES) + 1])
		elseif event == "dive" then
			local swimming: boolean = plain.harness.states[plain.slots.Croucher].mode == "Swim"
			setState("Croucher", "mode", swimming and "Ground" or "Swim")
		elseif event == "lookAhead" then
			local index: number = roll(#plain.viewers) + 1
			local name: string = plain.viewers[index].key.Name
			local on: boolean = connected[name]
			connected[name] = not on

			both(function (built: Side)
				local key: any = built.viewers[index].key
				if on then
					built.harness.Connections.remove(key)
				else
					built.harness.Connections.add(key)
				end
			end)
		else
			return
		end

		reached[event] += 1
	end

	-- Every reason, count and answer the same on both sides, or what differed
	local function differs(): string?
		for index: number, viewer: any in plain.viewers do
			for _, target: number in asked do
				local reason: string = plain.AntiEsp.reason(viewer.key, target)
				local other: string = remembering.AntiEsp.reason(remembering.viewers[index].key, target)
				if reason ~= other then
					return `{viewer.key.Name}'s pair with slot {target} was {reason} against memory's {other}`
				end
			end
		end

		local tests: number, hidden: number, failOpens: number = plain.AntiEsp.counts()
		local keptTests: number, keptHidden: number, keptFailOpens: number = remembering.AntiEsp.counts()
		local lying: number, waiting: number = plain.AntiEsp.lying()
		local keptLying: number, keptWaiting: number = remembering.AntiEsp.lying()

		if tests ~= keptTests or hidden ~= keptHidden or failOpens ~= keptFailOpens then
			return `the counts were {tests}, {hidden}, {failOpens} against memory's {keptTests}, {keptHidden}, {keptFailOpens}`
		elseif lying ~= keptLying or waiting ~= keptWaiting then
			return `the lying counts were {lying} and {waiting} against memory's {keptLying} and {keptWaiting}`
		end

		local answers: any = plain.AntiEsp.answers(plain.viewers)
		local keptAnswers: any = remembering.AntiEsp.answers(remembering.viewers)
		if buffer.tostring(answers.visible) ~= buffer.tostring(keptAnswers.visible) then
			return "the answers' visible rows differed"
		end

		return nil
	end

	local now: number = 0
	local plainRays: number = 0
	local keptRays: number = 0
	local keptTotal: number = 0
	local boxTotal: number = 0
	local hiddenSeen: number = 0
	local clearSeen: number = 0

	for step: number = 1, STEPS do
		if offFor > 0 then
			offFor -= 1
			if offFor == 0 then
				remembering.AntiEsp.useMemory(ON)
			end
		end

		local name: string = DECK[roll(#DECK) + 1]
		happen(name)

		-- A new tick, so every body's eye is found again
		both(function (built: Side)
			built.harness.world.clock += 1
		end)

		for index: number, viewer: any in plain.viewers do
			local other: any = remembering.viewers[index]
			for _, target: number in asked do
				if target ~= viewer.slot then
					plain.AntiEsp.isHidden(viewer, target)
					remembering.AntiEsp.isHidden(other, target)
				end
			end
		end

		local slicing: number = roll(SLICINGS)
		if slicing ~= 0 then
			now += DELAYS[roll(#DELAYS) + 1]
			local budget: number = SLICE
			if slicing == 1 then
				budget = 0
			end

			both(function (built: Side)
				built.harness:slice(now, budget)
			end)

			local kept: number, boxRays: number = remembering.harness:remembered()
			local cast: number = #plain.harness.rays
			local remembered: number = #remembering.harness.rays

			if remembered + boxRays > cast then
				return false,
					`Step {step}'s slice cast {remembered} rays and {boxRays} box rays, past the other's {cast}`
			end

			plainRays += cast
			keptRays += remembered
			keptTotal += kept
			boxTotal += boxRays
		end

		local differed: string? = differs()
		if differed then
			return false, `After step {step} ({name}), {differed}`
		end

		for _, viewer: any in plain.viewers do
			for _, target: number in asked do
				local reason: string = plain.AntiEsp.reason(viewer.key, target)
				if reason == "Hidden" then
					hiddenSeen += 1
				elseif reason == "Clear" then
					clearSeen += 1
				end
			end
		end
	end

	for _, name: string in EVENT_NAMES do
		if reached[name] == 0 then
			return false, `The seed never reached a {name}`
		end
	end

	if not (keptRays < plainRays) or keptTotal == 0 or boxTotal == 0 then
		return false,
			`Memory cast {keptRays} rays against {plainRays}, with {keptTotal} kept tests and {boxTotal} box rays`
	elseif hiddenSeen == 0 or clearSeen == 0 then
		return false, `The scene left {hiddenSeen} hidden and {clearSeen} clear pairs, so its walls decided nothing`
	end

	return true, nil
end
