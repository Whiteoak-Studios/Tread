--[[
    Builds the step's fixture geometry under Workspace.SpikeFixtures, runs the
    Lune cases' trials over it on Engine.collision and on a game's own casts
    with no include list, checks the crossing, and removes all it made
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local Geometry = require(ServerScriptService.Fixtures.Step.Geometry)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Walks = require(ServerScriptService.Fixtures.Step.Walks)

local CROSSINGS: number = 100000 -- Crossings timed each way
local NANOSECONDS: number = 1e9
local SEPARATOR: string = "; " -- Between the problems in one report

-- A value at the play bound's edge, one float32 rounds and a quantized height, each kept whole by a copy
local SAMPLE: Vector3 = Vector3.new(8191.998046875, 0.1, -1100.01953125)

type Collision = State.Collision
type GameCollision = State.GameCollision
type GameHit = State.GameHit
type Hit = State.Hit
type Piece = Geometry.Part

--[[
    Roblox's side of the crossing: a copy each way keeps every component,
    and what the two types are here and what each copy costs, printed for
    the run's record
--]]

local function crossing(problems: { string })
	local inner: vector = Engine.toVector(SAMPLE)
	local back: Vector3 = Engine.toVector3(inner)

	if inner.x ~= SAMPLE.X or inner.y ~= SAMPLE.Y or inner.z ~= SAMPLE.Z then
		table.insert(problems, `Engine.toVector of {SAMPLE} gave {inner}`)
	end

	if back ~= SAMPLE then
		table.insert(problems, `Engine.toVector3 of {inner} gave {back}, where {SAMPLE} went in`)
	end

	-- Whether a vector and a Vector3 are one value here, which says whether a cast would have done
	local made: vector = vector.create(SAMPLE.X, SAMPLE.Y, SAMPLE.Z)
	local same: boolean = (made :: unknown) == (SAMPLE :: unknown)
	local kinds: string = `typeof(vector) {typeof(made)}, type(Vector3) {type(SAMPLE)}, one value {same}`

	local sink: number = 0
	local started: number = os.clock()
	for _ = 1, CROSSINGS do
		sink += Engine.toVector(SAMPLE).x
	end

	local inward: number = (os.clock() - started) / CROSSINGS * NANOSECONDS
	started = os.clock()
	for _ = 1, CROSSINGS do
		sink += Engine.toVector3(inner).X
	end

	local outward: number = (os.clock() - started) / CROSSINGS * NANOSECONDS
	local costs: string = string.format("Vector3 to vector %.1f ns, vector to Vector3 %.1f ns", inward, outward)
	print(`Engine crossing: {kinds}; {costs} over {CROSSINGS} each, sink {sink}`)
end

-- Builds every fixture part, anchored and collidable, into the folder
local function build(folder: Folder)
	for _, piece: Piece in Geometry.parts do
		local part: Part = Instance.new("Part")
		part.Name = piece.name
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.Size = Engine.toVector3(piece.size)
		part.CFrame = CFrame.new(Engine.toVector3(piece.center)) * CFrame.Angles(0, 0, math.rad(piece.tilt))
		part.Parent = folder
	end
end

-- Runs every trial on a collision, and collects why each one that failed did under the route's name
local function trials(collision: Collision, route: string, problems: { string })
	for _, name: string in Walks.names do
		local passed: boolean, reason: string? = Walks.run(name, collision)
		if not passed then
			table.insert(problems, `{route}: {reason or name}`)
		end
	end
end

local function toGameHit(found: Hit?): GameHit?
	if not found then
		return nil
	end

	return {
		distance = found.distance,
		position = Engine.toVector3(found.position),
		normal = Engine.toVector3(found.normal),
		material = found.material,
		instance = found.instance,
	}
end

--[[
    A game's own four functions, as Frontier Zero passes its cast wrapper's:
    here the engine's casts over the fixture handed out on Vector3, with no
    include list beside them, so the overlap probe tests every collidable part
--]]

local function gameFunctions(casts: Collision): GameCollision
	return {
		ray = function (origin: Vector3, direction: Vector3): GameHit?
			return toGameHit(casts.ray(Engine.toVector(origin), Engine.toVector(direction)))
		end,

		sweep = function (center: Vector3, size: Vector3, direction: Vector3): GameHit?
			return toGameHit(casts.sweep(Engine.toVector(center), Engine.toVector(size), Engine.toVector(direction)))
		end,

		rest = function (center: Vector3, size: Vector3): number?
			return casts.rest(Engine.toVector(center), Engine.toVector(size))
		end,

		sphere = function (center: Vector3, radius: number, direction: Vector3): GameHit?
			return toGameHit(casts.sphere(Engine.toVector(center), radius, Engine.toVector(direction)))
		end,
	}
end

return function (): (boolean, string | nil)
	local problems: { string } = {}
	crossing(problems)

	local root: Instance? = Workspace:FindFirstChild("SpikeFixtures")
	local madeRoot: boolean = root == nil
	if not root then
		local made: Folder = Instance.new("Folder")
		made.Name = "SpikeFixtures"
		made.Parent = Workspace
		root = made
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = "StepEngine"
	build(folder)
	folder.Parent = root

	local made: { Collision } = {}
	local ran: boolean, failure: any = pcall(function ()
		local casts: Collision = Engine.collision({ folder })
		table.insert(made, casts)
		trials(casts, "engine casts", problems)

		local wrapped: Collision = Engine.wrap(gameFunctions(casts))
		table.insert(made, wrapped)
		trials(wrapped, "four functions with no include", problems)
	end)

	if not ran then
		table.insert(problems, `the trials threw: {failure}`)
	end

	-- Everything it made goes, each probe's camera included, whatever the trials did
	for _, collision: Collision in made do
		collision.destroy()
	end

	folder:Destroy()
	if madeRoot and root and #root:GetChildren() == 0 then
		root:Destroy()
	end

	if Workspace:FindFirstChild("TreadProbe") then
		table.insert(problems, "an overlap probe's camera was left in Workspace")
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
