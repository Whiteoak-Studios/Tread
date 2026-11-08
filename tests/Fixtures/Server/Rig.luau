--[[
    What the server handle's cases share: Tread's server in a fresh environment
    over Volt.mock on the example's tables, its casts on the step's fixture
    geometry and anti-ESP's on walls a case sets, its reports kept, its frames
--]]

--!strict
local Rig = {}
Rig.__index = Rig

local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Frames = require("./Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local ENGINE: string = "src/Step/Engine.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local ENGINE_PATH: string = "ReplicatedStorage.Packages.Tread.Step.Engine"
local BOT_RTT: number = 0.1 -- Seconds every bot's connection reports
local MOCK_STEPS: number = 3 -- Mock frames that carry a flush across, as manualFlush.luau finds
local LIFT: number = 0.5 -- Studs above the fixture floor a body is built at, so it lands on its first ticks

-- Studs the step's fixture geometry is moved down, from 1,100 into the record's and the history's height window of
-- -1,024 to 1,024, so what they hold of a body standing on it is where it stands
local SHIFT: number = -100

-- One report the rig heard
export type Heard = {
	player: any,
	kind: string,
	measurement: number | string,
}

-- An axis-aligned occluder anti-ESP's rays meet, by its two corners
type Wall = {
	low: vector,
	high: vector,
}

-- What anti-ESP's stand-in cast sees: the walls a case set, and the include list the server handed it
type Sight = {
	walls: { Wall },
	include: { any }?,
}

type Fields = {
	globals: any, -- The environment's game, script and require
	tread: any, -- The package's ModuleScript in it
	Server: any, -- The server handle's module
	server: any, -- The started handle, nil until start
	shared: any, -- The example's shared table, with the case's changes
	settings: any, -- The example's server settings, with a bot round trip and the case's changes
	floor: number, -- The top of the floor the casts see, the fixture's moved down by SHIFT
	vault: vector, -- The center of the fixture's vault, moved the same, where no spot frees a body
	mock: any, -- The environment's Volt.mock
	frames: Frames.Frames,
	rate: number, -- The simulation rate, ticks a second
	heard: { Heard },
	sight: Sight,
}

-- The shares of a segment's move at which it enters and leaves a slab between low and high on one axis
local function span(low: number, high: number, from: number, move: number): (number, number)
	if move == 0 then
		if from > low and from < high then
			return -math.huge, math.huge
		end

		return math.huge, -math.huge
	end

	local enter: number = (low - from) / move
	local leave: number = (high - from) / move
	if enter > leave then
		return leave, enter
	end

	return enter, leave
end

-- Whether a ray from origin along direction, its whole length, passes through a wall
local function crosses(wall: Wall, origin: vector, direction: vector): boolean
	local enterX: number, leaveX: number = span(wall.low.x, wall.high.x, origin.x, direction.x)
	local enterY: number, leaveY: number = span(wall.low.y, wall.high.y, origin.y, direction.y)
	local enterZ: number, leaveZ: number = span(wall.low.z, wall.high.z, origin.z, direction.z)
	local enter: number = math.max(enterX, enterY, enterZ, 0)
	local leave: number = math.min(leaveX, leaveY, leaveZ, 1)

	return enter < leave
end

--[[
    A rig with the example's tables, which tweak may change before start,
    the environment's Engine answering with the fixture casts in place of
    the engine's and anti-ESP's rays meeting only the walls a case sets,
    and overrides answering any other require given
--]]

function Rig.new(tweak: ((shared: any, settings: any) -> ())?, overrides: { [string]: any }?): Self
	-- Lune has no engine query for the overlap probe, so the casts run on the fixture geometry
	local engine: any = Environment.load(ENGINE)
	local casts: any = Environment.load(CASTS)
	local geometry: any = Environment.load(GEOMETRY)
	local down: vector = vector.create(0, SHIFT, 0)
	local sight: Sight = { walls = {}, include = nil }

	local parts: { any } = {}
	for _, part: any in geometry.parts do
		table.insert(parts, { name = part.name, center = part.center + down, size = part.size, tilt = part.tilt })
	end

	local answers: { [string]: any } = {
		[ENGINE_PATH] = {
			toVector = engine.toVector,
			toVector3 = engine.toVector3,
			box = engine.box,

			collision = function (_: { Instance }): any
				return casts(parts)
			end,

			wrap = function (_: any): any
				return casts(parts)
			end,

			casts = function (_: any): any
				return casts(parts)
			end,

			-- Lune casts no ray on the engine, so anti-ESP's occlusion meets the walls the case set
			occlusion = function (include: { any }): any
				sight.include = include

				return function (origin: vector, direction: vector): boolean
					for _, wall: Wall in sight.walls do
						if crosses(wall, origin, direction) then
							return true
						end
					end

					return false
				end
			end,
		},
	}

	for path: string, value: any in overrides or {} do
		answers[path] = value
	end

	local globals: any = Environment.load(GLOBALS, answers)
	local frames: Frames.Frames = Frames.new(globals)
	local replicatedStorage: any = globals.game:GetService("ReplicatedStorage")
	local fixtures: any = globals.game:GetService("ServerScriptService").Fixtures
	local example: any = globals.require(fixtures.Config.Example)

	local shared: any = example.shared()
	local settings: any = example.server()
	settings.bots = { rtt = BOT_RTT }

	if tweak then
		tweak(shared, settings)
	end

	local tread: any = replicatedStorage.Packages.Tread

	return setmetatable({
		globals = globals,
		tread = tread,
		Server = globals.require(tread.Server),
		server = nil :: any,
		shared = shared,
		settings = settings,
		floor = geometry.floor + SHIFT,
		vault = geometry.vault.center + down,
		mock = globals.require(replicatedStorage.Packages.Volt).mock,
		frames = frames,
		rate = shared.rates.simulation,
		heard = {} :: { Heard },
		sight = sight,
	}, Rig)
end

--[[
    Starts the server on the rig's tables and keeps every report it raises
--]]

function Rig.start(self: Self): any
	self.server = self.Server.start(self.shared, self.settings)
	self.server:onReport(function (player: any, kind: string, measurement: number | string)
		table.insert(self.heard, { player = player, kind = kind, measurement = measurement })
	end)

	return self.server
end

-- A module of the environment's, by the instance it is mounted at
function Rig.require(self: Self, module: any): any
	return self.globals.require(module)
end

-- Runs count ticks, one Heartbeat of a tick's time each
function Rig.tick(self: Self, count: number)
	for _ = 1, count do
		self.frames:run(1 / self.rate)
	end
end

-- Steps the mock until what was flushed has crossed both ways
function Rig.deliver(self: Self)
	for _ = 1, MOCK_STEPS do
		self.mock:step()
	end
end

-- A CFrame over the fixture floor at x and z, looking along -Z
function Rig.at(self: Self, x: number, z: number): any
	return roblox.CFrame.new(x, self.floor + LIFT, z)
end

-- Stands an occluder anti-ESP's rays meet, centered at a point with a size, and gives back the closure that removes it
function Rig.wall(self: Self, center: vector, size: vector): () -> ()
	local wall: Wall = { low = center - size / 2, high = center + size / 2 }
	table.insert(self.sight.walls, wall)

	return function ()
		local index: number? = table.find(self.sight.walls, wall)
		if index then
			table.remove(self.sight.walls, index)
		end
	end
end

-- The include list the server handed anti-ESP's occlusion, nil before start
function Rig.occluders(self: Self): { any }?
	return self.sight.include
end

-- The measurements of every report of a kind heard, in the order they were raised
function Rig.reported(self: Self, kind: string): { number | string }
	local measurements: { number | string } = {}

	for _, heard: Heard in self.heard do
		if heard.kind == kind then
			table.insert(measurements, heard.measurement)
		end
	end

	return measurements
end

-- The reports of a kind heard about one player or bot
function Rig.reportedFor(self: Self, kind: string, player: any): { Heard }
	local found: { Heard } = {}

	for _, heard: Heard in self.heard do
		if heard.kind == kind and heard.player == player then
			table.insert(found, heard)
		end
	end

	return found
end

export type Rig = Self
type Self = typeof(setmetatable({} :: Fields, Rig))

return Rig
