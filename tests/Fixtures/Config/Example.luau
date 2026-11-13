--[[
    The approved example's three tables with Frontier Zero's values, built
    fresh on every call, and the helpers the Config cases share to break
    one key of a copy and read the refusal it gets
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Scene = require(ServerScriptService.Fixtures.Step.Scene)

local SHOTS_PER_COMMAND: number = 4 -- Frontier Zero's Ballistics.shotsPerCommand
local SEA_LEVEL: number = 0 -- MapGen's sea, the one water surface this fixture has
local NPC_RANGE: number = 800 -- Frontier Zero's NPC draw distance is unset until its NPCs, so this stands in
local HANDHELD_DISTANCE: number = 500 -- Its phone and tablet draw distances wait on the S22's measurement

-- The states Tread plays an animation for, each the name of an Animation in the client settings
local ANIMATIONS: { string } = {
	"idle",
	"walk",
	"sprint",
	"crouchIdle",
	"crouchWalk",
	"jump",
	"fall",
	"land",
	"swimIdle",
	"swim",
	"climb",
	"mantle",
	"downed",
	"crawl",
}

-- The R15 joints, each named alike in the rig template
local JOINTS: { string } = {
	"Root",
	"Neck",
	"Waist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

local Config = require(ReplicatedStorage.Packages.Tread.Config)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

type Allow = State.Allow
type ClientSettings = Config.ClientSettings
type Command = State.Command
type GameHit = State.GameHit
type RuleStep = State.RuleStep
type ServerSettings = Config.ServerSettings
type Shape = Config.Shape
type Shared = Config.Shared

local Example = {}

-- A copy of a value with every table in it copied too
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local result: { [any]: any } = {}

	for key, inner in value do
		result[key] = copy(inner)
	end

	return result
end

-- A capsule in the character's own space, from one point to another
local function capsule(from: Vector3, to: Vector3, radius: number): Shape
	return { from = from, to = to, radius = radius }
end

--[[
    Frontier Zero's shared table: its rates, ticks, step and tolerances,
    stand-in hit shapes until its Ballistics sets them, the cast wrapper's
    four collision functions, the sea and its declared fields
--]]

function Example.shared(): Shared
	return {
		rates = { simulation = 20, relay = 20 },
		ticks = { standIn = 2, ahead = 5, queueWait = 3, leadMin = 1, leadMax = 3, nudge = 0.02, resync = 3, debt = 8 },
		step = copy(Scene.settings),
		tolerances = { Ground = 2, Air = 2, Swim = 2, Ladder = 2, Rider = 2, Mantle = 0 },

		hitShapes = {
			Stand = {
				body = capsule(Vector3.new(0, 1, 0), Vector3.new(0, 4, 0), 1.4),
				zones = {
					head = capsule(Vector3.new(0, 4.3, 0), Vector3.new(0, 4.7, 0), 0.5),
					chest = capsule(Vector3.new(0, 2.9, 0), Vector3.new(0, 3.9, 0), 0.9),
					legs = capsule(Vector3.new(0, 0.4, 0), Vector3.new(0, 2, 0), 0.7),
				},
				waist = 2.5,
			},

			Crouch = {
				body = capsule(Vector3.new(0, 0.9, 0), Vector3.new(0, 2.3, 0), 1.3),
				zones = {
					head = capsule(Vector3.new(0, 2.6, 0), Vector3.new(0, 2.9, 0), 0.5),
					chest = capsule(Vector3.new(0, 1.7, 0), Vector3.new(0, 2.4, 0), 0.9),
					legs = capsule(Vector3.new(0, 0.4, 0), Vector3.new(0, 1.5, 0), 0.7),
				},
				waist = 1.5,
			},

			Downed = {
				body = capsule(Vector3.new(0, 0.6, 1.6), Vector3.new(0, 0.6, -1.6), 0.8),
				zones = {
					head = capsule(Vector3.new(0, 0.6, -2.2), Vector3.new(0, 0.6, -2.5), 0.5),
					chest = capsule(Vector3.new(0, 0.6, -0.6), Vector3.new(0, 0.6, -1.6), 0.8),
					legs = capsule(Vector3.new(0, 0.6, 0.4), Vector3.new(0, 0.6, 2.2), 0.6),
				},
				waist = 0.6,
			},
		},

		collision = {
			ray = function (_: Vector3, _: Vector3): GameHit?
				return nil
			end,

			sweep = function (_: Vector3, _: Vector3, _: Vector3): GameHit?
				return nil
			end,

			rest = function (_: Vector3, _: Vector3): number?
				return nil
			end,

			sphere = function (_: Vector3, _: number, _: Vector3): GameHit?
				return nil
			end,
		},

		water = function (_: number, _: number): number?
			return SEA_LEVEL
		end,

		-- Refuses nothing and caps no speed
		rules = function (_: RuleStep, _: Allow): number
			return math.huge
		end,

		fields = {
			command = {
				{ name = "slot", kind = "held", type = "uint", bits = 3, max = 6 },

				{
					name = "shots",
					kind = "dropped",
					type = "group",
					count = SHOTS_PER_COMMAND,
					fields = {
						{ name = "sequence", type = "uint", bits = 6 },
						{ name = "class", type = "uint", bits = 2 },
						{ name = "renderTick", type = "uint", bits = 16 },
						{ name = "fraction", type = "uint", bits = 8 },
						{ name = "yaw", type = "uint", bits = 16 },
						{ name = "pitch", type = "int", bits = 16 },
					},
				},
			},

			rules = {
				{ name = "sinceJump", type = "uint", bits = 4, start = 0 },
				{ name = "sinceShot", type = "uint", bits = 4, start = 15 },
			},

			server = {
				{ name = "beingRevived", type = "bool", start = false },
			},

			slot = {
				{ name = "head", type = "uint", bits = 16, optional = true },
				{ name = "torso", type = "uint", bits = 16, optional = true },
				{ name = "leg", type = "uint", bits = 16, optional = true },
				{ name = "face", type = "uint", bits = 16, optional = true },
				{ name = "shirt", type = "uint", bits = 16, optional = true },
				{ name = "pants", type = "uint", bits = 16, optional = true },
			},

			held = {
				{ name = "item", type = "uint", bits = 16, optional = true },
				{ name = "skin", type = "uint", bits = 16, optional = true },
			},
		},
	}
end

--[[
    Frontier Zero's server settings, with its two hooks as functions that do
    nothing, a stand-in NPC range until its NPCs set one, and an empty
    folder standing in for its occluders until its anti-ESP prefabs fill one
--]]

function Example.server(): ServerSettings
	local occluders = Instance.new("Folder")
	occluders.Name = "Occluders"

	return {
		rates = {
			move = { perSecond = 35, burst = 60 },
			view = { perSecond = 2, burst = 5 },
		},

		catchUp = 2,
		slots = { reserve = 296 },
		relevancy = { enter = 950, leave = 1000 },
		tiers = {
			nearEnter = 200,
			nearLeave = 220,
			nearFloor = 15,
			nearAim = 20,
			farFloor = 10,
			farAim = 15,
			outOfView = { rate = 5, cone = 70, radius = 40 },
		},

		relay = { changes = true },
		weights = { near = 1, far = 0.5, shooter = 2, cone = 1.5 },
		shotNear = { rate = 10, seconds = 5 },
		budget = { soft = 64, hard = 96 },

		antiEsp = {
			-- Studs above the feet and across the line from the viewer; the torso's ray leads with both bodies' movement
			aim = {
				Stand = {
					{ up = 5, side = 0 },
					{ up = 4, side = -1.4 },
					{ up = 4, side = 1.4 },
					{ up = 3, side = 0, lead = true },
					{ up = 1, side = -0.5 },
					{ up = 1, side = 0.5 },
				},
				Crouch = {
					{ up = 3, side = 0 },
					{ up = 2.4, side = -1.4 },
					{ up = 2.4, side = 1.4 },
					{ up = 1.9, side = 0, lead = true },
					{ up = 0.6, side = -0.5 },
					{ up = 0.6, side = 0.5 },
				},
				Downed = {
					{ up = 1.2, side = 0 },
					{ up = 0.8, side = -1.4 },
					{ up = 0.8, side = 1.4 },
					{ up = 0.6, side = 0, lead = true },
					{ up = 0.4, side = -0.5 },
					{ up = 0.4, side = 0.5 },
				},
			},
			lookAheadMin = 0.15,
			lookAheadMax = 0.45,
			slice = 0.002,
			hiddenRate = 10,
			nearRadius = 250,
			nearRate = 30,
			visibleRate = 2,
			hold = 1,
			failOpen = 0.15,
			lyingShare = 0.0005,
			include = { occluders },
		},

		footsteps = {
			range = { walk = 40, sprint = 60, jump = 60, land = 60 },
			stride = { walk = 4.5, sprint = 6 },
		},

		sleepers = { radius = 500, rays = 3, retest = 4, rate = 1.5, hold = 2 },
		npcs = { near = 197, farRate = 2, range = NPC_RANGE },
		history = { seconds = 1 },

		rewind = {
			ceiling = 0.5,
			rttCap = 0.2,
			delayMin = 0.15,
			delayMax = 0.25,
			extra = 2,
			band = 1,
			bandSigmas = 2,
			bandMax = 2,
			rttSmoothing = 1,
		},

		teleport = { timeout = 3 },
		beforeCommand = function (_: any, _: Command) end,

		-- A game's resolves a Promise once the destination is ready
		prestream = function (_: Player, _: CFrame): any
			return nil
		end,
	}
end

--[[
    Frontier Zero's client settings, with a bare rig template, one Animation
    for each state Tread plays, its hooks as functions that do nothing, and
    stand-in joint limits until its Studio test tunes them
--]]

function Example.client(): ClientSettings
	local animations: { [string]: Animation } = {}
	for _, name: string in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.Name = name
		animations[name] = animation
	end

	local joints: { [string]: string } = {}
	for _, name: string in JOINTS do
		joints[name] = name
	end

	return {
		sample = function (_: Command) end,

		-- A level look ahead, with no head offset
		look = function (): (number, number, number, number)
			return 0, 0, 0, 0
		end,

		rig = Instance.new("Model"),
		joints = joints,
		animations = animations,
		dress = function (_: Model, _: { [string]: any }, _: boolean) end,
		undress = function (_: Model) end,
		hold = function (_: Model, _: { [string]: any }?) end,
		interpolation = { delay = 0.15, delayMax = 0.25, scaleMin = 0.95, scaleMax = 1.05 },

		bodies = {
			radius = 250,
			late = 6,
			minSeconds = 1,
			maxSeconds = 6,
			check = 0.5,
			settleSpeed = 0.33,
			pushSpeed = 6,
			pushUpBias = 0.5,
			jointLimits = {
				Neck = { tilt = 30, twistLower = -40, twistUpper = 40 },
				Waist = { tilt = 20, twistLower = -30, twistUpper = 30 },
				LeftShoulder = { tilt = 90, twistLower = -60, twistUpper = 60 },
				RightShoulder = { tilt = 90, twistLower = -60, twistUpper = 60 },
			},
		},

		-- Frontier Zero sets its outline with its Moderation, so these stand in until it does
		spectate = {
			outline = {
				fill = Color3.fromRGB(255, 60, 60),
				fillTransparency = 0.75,
				outline = Color3.fromRGB(255, 255, 255),
				outlineTransparency = 0,
			},
		},

		smoothing = { decay = 15, snap = 2 },
		drawDistance = { desktop = 1000, console = 1000, phone = HANDHELD_DISTANCE, tablet = HANDHELD_DISTANCE },
		lod = { full = 128, footIk = 128, aim = 600 },

		-- Frontier Zero tunes the copy's distance live with its rig and field of view, so the dev place's stands in
		firstPerson = { back = 1 },
	}
end

-- A path's key: a list's index as a number, any other as its name
local function key(segment: string): any
	return tonumber(segment) or segment
end

--[[
    The value at a dotted path inside a table, each number in the path a
    list's index
--]]

function Example.get(root: { [any]: any }, path: string): any
	local value: any = root

	for _, segment: string in path:split(".") do
		value = value[key(segment)]
	end

	return value
end

--[[
    Sets the value at a dotted path inside a table, nil to remove the key,
    each number in the path a list's index
--]]

function Example.set(root: { [any]: any }, path: string, value: any)
	local segments: { string } = path:split(".")
	local last: string = table.remove(segments) :: string
	local target: any = root

	for _, segment: string in segments do
		target = target[key(segment)]
	end

	target[key(last)] = value
end

--[[
    Why one of Config's checks did not refuse naming a key, or nil when it
    did: the call must error, and its message must start with the key's
    full path and what it expected
--]]

function Example.refusal(check: (...any) -> (), path: string, ...: any): string?
	local passed: boolean, failure: any = pcall(check, ...)
	if passed then
		return `{path} was taken`
	elseif string.find(tostring(failure), `{path} expected`, 1, true) ~= 1 then
		return `{path} was refused as "{failure}"`
	end

	return nil
end

return Example
