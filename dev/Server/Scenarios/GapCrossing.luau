--[[
    The 2-stud gap check: the real player set down facing two walls while a bot
    sprints behind them across the gap and back, each crossing's reveal, its
    past, the client's draw, the frozen rig's jump and the hold a line each
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local AntiEsp = require(Packages.Tread.Server.AntiEsp)
local Engine = require(Packages.Tread.Step.Engine)

local ClientLines = require(ServerScriptService.Server.Bots.ClientLines)
local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Gap = require(ServerScriptService.Server.Gap)
local GapLine = require(ReplicatedStorage.Shared.Dev.GapLine)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Reveals = require(ServerScriptService.Server.Reveals)

local Config = require(ServerScriptService.Server.Config.GapCrossing)
local GRACE: number = require(ServerScriptService.Server.Config.Reveals).grace

local CROSSINGS: number = Config.crossings
local ZONE: number = Config.zone
local LIFT: Vector3 = Vector3.new(0, Config.lift, 0)
local LANDED: number = Config.landed
local STILL: number = Config.still
local SETTLE: number = Config.settle
local SLACK: number = Config.slack
local SECONDS: number = Config.seconds
local WAIT: number = Config.wait
local RATE: { perSecond: number, burst: number } = Config.rate
local SEED: number = Config.seed
local VERSION: number = Tread.CODEC_VERSION
local FOLDER: string = "GapCrossing" -- The folder under the test content it lays its floor and walls in
local GROUP: string = "gap" -- What the fleet's entries call its bot
local TARGET: string = "GapTarget" -- The bot's name
local ALONG: Vector3 = Vector3.new(0, 0, 1) -- The path's way, which the target starts along
local LEVEL: number = 1e-6 -- Below this a look flattened onto the ground has no direction
local LENIENT: string = "lenient" -- G8's reading that counts a stretch longer than the grace
local FIGURE: string = "%.3f" -- Studs and degrees, as the lines print them
local SEPARATOR: string = "; " -- Between the problems in one report

-- How the target is steered: at rest until it goes, then along the path, turning at each end
type Motion = {
	going: boolean,
	direction: number, -- 1 along +Z, -1 along -Z
	turns: number, -- Ends it has turned at since it went
	near: number, -- The Z of the path's -Z end
	far: number, -- And of its +Z end
}

-- What the bot harness's runs call around a window, which the client's lines open and close
type Probe = {
	start: (entries: { any }) -> (),
	stop: (samples: { [string]: { number } }) -> string,
}

-- What every pass reads, from the check's start to its clean-up
type Context = {
	server: Tread.Server,
	player: Player,
	character: Tread.Character,
	layout: Gap.Layout,
	blocked: Reveals.Blocked,
	window: ClientLines.Window,
	probe: Probe,
	sprint: number, -- Studs a second the target sprints at
	rate: number, -- Relay ticks a second
	nearRadius: number, -- Anti-ESP's, inside which a pass is near
	cone: number?, -- The out-of-view cone's degrees either side of the look, nil while it is off
	pastOn: boolean, -- Whether the relay carries a past with a reveal
}

-- What the check made, which its clean-up ends whatever it did
type Made = {
	parts: { Instance },
	stops: { () -> () }, -- Each listener's and tap's disconnect
	moved: boolean, -- Whether the real player was set down, so it is respawned after
}

-- Waits a frame at a time until done says so or seconds pass, and gives whether it got there
local function waitFor(seconds: number, done: () -> boolean): boolean
	local deadline: number = os.clock() + seconds
	while not done() do
		if os.clock() >= deadline then
			return false
		end

		RunService.Heartbeat:Wait()
	end

	return true
end

-- An anchored part that touches nothing, colliding and queried or not, in a parent
local function part(name: string, shape: Gap.Part, collides: boolean, queried: boolean, parent: Instance): Part
	local made: Part = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = collides
	made.CanQuery = queried
	made.CanTouch = false
	made.Size = shape.size
	made.CFrame = CFrame.new(shape.center)
	made.Parent = parent

	return made
end

-- The first real player holding a character, with it, or nil
local function playerOf(): (Player?, Tread.Character?)
	for _, player: Player in Players:GetPlayers() do
		local character: Tread.Character? = Game.characterOf(player)
		if character then
			return player, character
		end
	end

	return nil, nil
end

-- A character's slot and generation, which its handle keeps private
local function lifeOf(character: Tread.Character): (number, number)
	local inner: any = character
	return inner._slot, inner._generation
end

-- Degrees a look turns from a level way across the ground, 0 for a look straight up or down
local function lookOff(look: Vector3, toward: Vector3): number
	local flat: Vector3 = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < LEVEL then
		return 0
	end

	return math.deg(math.acos(math.clamp(flat.Unit:Dot(toward), -1, 1)))
end

--[[
    The target's program: at rest until it goes, then a sprint along the
    path with its yaw held, turning at each end until it has made every
    crossing, then at rest again
--]]

local function steer(motion: Motion): Programs.Steer
	return function (command: Tread.Command, _: number, position: vector)
		if not motion.going then
			return
		end

		local past: boolean = (motion.direction > 0 and position.z >= motion.far)
			or (motion.direction < 0 and position.z <= motion.near)
		if past then
			motion.turns += 1
			motion.direction = -motion.direction

			if motion.turns >= CROSSINGS then
				motion.going = false
				return
			end
		end

		-- The step's yaw 0 looks along -Z, so a half turn looks along +Z
		command.yaw = motion.direction > 0 and math.pi or 0
		command.forward = 1
		command.sprint = true
	end
end

--[[
    Whether the server's exact tests from an eye find a standing body like
    the one given hidden on both sets, set at a place on the floor
--]]

local function hiddenFrom(
	eye: Vector3,
	like: Tread.State,
	floor: number,
	blocked: Reveals.Blocked
): (place: GapLine.Place) -> boolean
	local body: Reveals.Sighting = Reveals.sighting("body")
	local hull: Reveals.Sighting = Reveals.sighting("hull")
	local size: Vector3 = like.standingBox.size

	return function (place: GapLine.Place): boolean
		local feet: Vector3 = Vector3.new(place.x, floor, place.z)
		local middle: Vector3 = feet + Vector3.new(0, size.Y / 2, 0)

		local state: Tread.State = table.clone(like)
		state.root = feet
		state.velocity = Vector3.zero
		state.hullCenter = middle
		state.standingBox = { cframe = CFrame.new(middle), size = size }
		Reveals.sight(body, hull, eye, state, blocked)

		return not body.visible and not hull.visible
	end
end

-- Takes the client's line for a crossing's window, or why there is none
local function hear(crossing: Gap.Crossing, context: Context)
	local line: string? = context.window.lines[context.player]
	if not line then
		crossing.missing = `{context.player.Name} sent no line within {WAIT} s`
		return
	end

	local capture: GapLine.Capture? = GapLine.decode(line)
	if not capture then
		crossing.missing = "its line held no frames the check could read"
		return
	end

	crossing.client = capture
end

--[[
    Ends a crossing: G8's episodes counted, the client's frames judged
    against each set's open ticks, the body set's it drew no frame in named,
    the frozen rig's jump tested from the viewer's eye on a body like the
    target's, and its line printed
--]]

local function finish(crossing: Gap.Crossing, context: Context, episodes: { Reveals.Episode }, target: Tread.Character)
	for _, episode: Reveals.Episode in episodes do
		if episode.reading == LENIENT then
			crossing.lenient += 1
		else
			crossing.strict += 1
		end
	end

	local capture: GapLine.Capture? = crossing.client
	if capture then
		local late: number, drawnAt: number? = Gap.judge(capture.frames, capture.arrival, crossing.bodyOpen)
		local hullLate: number = Gap.judge(capture.frames, capture.arrival, crossing.open)
		local eye: Vector3 = context.character:getState().eye
		local hidden: (place: GapLine.Place) -> boolean =
			hiddenFrom(eye, target:getState(), context.layout.center.Y, context.blocked)

		crossing.late = late
		crossing.hullLate = hullLate
		crossing.unwatched = Gap.unwatched(capture.frames, crossing.bodyTicks)
		crossing.drawnAt = drawnAt
		crossing.jump = Gap.behind(capture.frozen, capture.thawed, hidden)
	end

	print(Gap.line(crossing, context.rate, context.pastOn))
end

--[[
    One pass: the viewer set down at its spot and settled, the target built
    in the open at the path's -Z end and settled, then sent across and back.
    Every relay tick of the viewer's tap is tracked, each crossing's window
    opens for the client while the target is in the zone, and each
    crossing's line prints as it ends. Gives its crossings, and adds what
    went wrong to the problems
--]]

local function pass(context: Context, at: Gap.Pass, made: Made, problems: { string }): { Gap.Crossing }
	local server: Tread.Server = context.server
	local player: Player = context.player
	local character: Tread.Character = context.character
	local gapZ: number = context.layout.center.Z
	local crossings: { Gap.Crossing } = {}

	character:teleport(CFrame.lookAlong(at.spot + LIFT, at.look))
	local landed: boolean = waitFor(SECONDS, function (): boolean
		local offset: Vector3 = character:getState().root - at.spot

		return Vector3.new(offset.X, 0, offset.Z).Magnitude <= LANDED
	end)

	if not landed then
		table.insert(problems, `{at.name}: {player.Name}'s teleport to the spot did not land within {SECONDS} s`)
		return crossings
	end

	task.wait(SETTLE)
	local spot: Vector3 = character:getState().root

	local motion: Motion = {
		going = false,
		direction = 1,
		turns = 0,
		near = gapZ - at.reach,
		far = gapZ + at.reach,
	}

	local start: Vector3 = Vector3.new(at.path, context.layout.center.Y, motion.near) + LIFT
	local entry: Fleet.Entry = Fleet.add({
		name = TARGET,
		group = GROUP,
		at = CFrame.lookAlong(start, ALONG),
		steer = steer(motion),
		faults = nil,
		seed = SEED,
	})

	local target: Tread.Character = entry.character
	local slot: number, generation: number = lifeOf(target)
	Workspace:SetAttribute(GapLine.SLOT, slot)

	local kind: string = at.distance <= context.nearRadius and "near" or "far"
	local current: Gap.Crossing = Gap.crossing(at.name, kind, 1, motion.direction)
	local bodyPair: Reveals.Pair = Reveals.pair()
	local episodes: { Reveals.Episode } = {}
	local held: Reveals.Held = {}
	local bodySeen: Reveals.Sighting = Reveals.sighting("body")
	local hullSeen: Reveals.Sighting = Reveals.sighting("hull")
	local seen: Gap.Seen =
		{ tick = 0, zone = false, hull = false, body = false, reason = "", revealed = nil, hid = false }
	local moved: number = 0
	local turned: number = 0

	-- Seeded and connected straight after the target is built, so the sink hears its first reveal
	Reveals.seed(held, Tread.decode(VERSION, "keyframe", server:keyframe(player)))
	local stop: () -> () = server:observe(player, function (tick: number, data: buffer)
		local frame: { [string]: any } = Tread.decode(VERSION, "tap", data)
		Reveals.apply(held, frame)

		local viewer: Tread.State = character:getState()
		moved = math.max(moved, (viewer.root - spot).Magnitude)
		turned = math.max(turned, lookOff(viewer.look, at.look))

		local state: Tread.State = target:getState()
		local reason: string = AntiEsp.reason(player, slot)
		Reveals.sight(bodySeen, hullSeen, viewer.eye, state, context.blocked)
		bodySeen.tick = tick
		bodySeen.sent = held[slot] == generation
		bodySeen.reason = reason
		Reveals.track(bodyPair, bodySeen, GRACE, episodes, player.Name, TARGET, true)

		local revealed: { number }?, hid: boolean = Gap.carried(frame, slot, generation)
		seen.tick = tick
		seen.zone = math.abs(state.root.Z - gapZ) <= ZONE
		seen.hull = hullSeen.visible
		seen.body = bodySeen.visible
		seen.reason = reason
		seen.revealed = revealed
		seen.hid = hid
		Gap.track(current, seen)
	end)

	table.insert(made.stops, stop)

	local sprinting: number = CROSSINGS * 2 * at.reach / context.sprint
	local deadline: number = os.clock() + SETTLE + sprinting * SLACK + CROSSINGS * WAIT
	task.wait(SETTLE)
	motion.going = true

	local windowed: boolean = false -- Whether this crossing's window has opened
	local open: boolean = false -- Whether it is open now
	while true do
		RunService.Heartbeat:Wait()

		local inZone: boolean = math.abs(target:getState().root.Z - gapZ) <= ZONE
		if inZone and not windowed then
			context.probe.start({})
			windowed = true
			open = true
		end

		local ended: boolean = motion.turns >= current.index or not motion.going
		if open and (ended or not inZone) then
			open = false
			context.probe.stop({})
			hear(current, context)
		end

		local late: boolean = os.clock() >= deadline
		if ended or late then
			finish(current, context, episodes, target)
			table.insert(crossings, current)
		end

		if late then
			table.insert(problems, `{at.name}: crossing {current.index} had not ended within its deadline`)
			break
		elseif not ended then
			continue
		elseif not motion.going then
			break
		end

		current = Gap.crossing(at.name, kind, motion.turns + 1, motion.direction)
		bodyPair = Reveals.pair()
		episodes = {}
		windowed = false
	end

	stop()
	Workspace:SetAttribute(GapLine.SLOT, nil)
	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	local movedText: string = string.format(FIGURE, moved)
	local turnedText: string = string.format(FIGURE, turned)
	print(`GapCrossing {at.name}: the viewer moved {movedText} studs at most and looked {turnedText}° off the walls`)

	if moved > STILL then
		table.insert(problems, `{at.name}: {player.Name} moved {movedText} studs, past the {STILL} a pass allows`)
	end

	local cone: number? = context.cone
	if cone ~= nil and turned > cone then
		local rate: string = "so the target's records came at the out-of-view rate"
		table.insert(
			problems,
			`{at.name}: {player.Name} looked {turnedText}° off the walls, past the {cone}° cone, {rate}`
		)
	end

	return crossings
end

--[[
    Every pass in turn, then the line that sums their crossings. A crossing
    whose client drew no frame in some of the body set's open ticks adds a
    problem, since those ticks can't be judged
--]]

local function drive(context: Context, made: Made, problems: { string }): string
	made.moved = true

	local all: { Gap.Crossing } = {}
	for _, at: Gap.Pass in context.layout.passes do
		for _, crossing: Gap.Crossing in pass(context, at, made, problems) do
			table.insert(all, crossing)
		end
	end

	local late: number = 0
	local unwatched: number = 0
	local atArrival: number = 0
	local behind: number = 0
	local carried: number = 0
	for _, crossing: Gap.Crossing in all do
		late += crossing.late or 0

		local ticks: { number }? = crossing.unwatched
		if ticks and #ticks > 0 then
			unwatched += #ticks

			local where: string = `{crossing.pass} crossing {crossing.index}`
			local drew: string = `the client drew no frame in {#ticks} of the body set's open ticks ({Gap.list(ticks)})`
			table.insert(problems, `{where}: {drew}, so the check can't say whether the rig was drawn in them`)
		end

		local capture: GapLine.Capture? = crossing.client
		if capture and capture.arrival ~= nil and crossing.drawnAt == capture.arrival then
			atArrival += 1
		end

		if crossing.jump == true then
			behind += 1
		end

		local past: { number }? = crossing.past
		if past and #past > 0 then
			carried += 1
		end
	end

	local relay: string = context.pastOn and "on" or "off"
	local bodySet: string = `{late} late frames by the body set, {unwatched} of its open ticks unwatched`
	local counts: string = `{bodySet}, {atArrival} drawn at the reveal's arrival frame`
	local rest: string = `{behind} jumps behind the walls, {carried} reveals with a past, relay.past {relay}`

	return `{#all} crossings over {#context.layout.passes} passes: {counts}, {rest}`
end

return function (): (boolean, string | nil)
	local server: Tread.Server, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	Fleet.start()
	if #Fleet.entries() > 0 then
		return false, `another run's {#Fleet.entries()} bots are still on the server`
	end

	local player: Player?, character: Tread.Character? = playerOf()
	if not player or not character then
		return false, "no real player has a character to set down as the viewer"
	end

	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	local cityBlock: Instance? = testContent and testContent:FindFirstChild("CityBlock")
	local occluders: Instance? = cityBlock and cityBlock:FindFirstChild("Occluders")
	if not testContent or not occluders then
		return false, "Workspace.TestContent.CityBlock.Occluders is missing, so no wall this lays would hide anything"
	end

	local layout: Gap.Layout = Gap.layout(Config)
	local folder: Folder = Instance.new("Folder")
	folder.Name = FOLDER
	part("Floor", layout.floor, true, true, folder)
	for index: number, wall: Gap.Part in layout.walls do
		part(`Wall{index}`, wall, false, false, folder)
	end

	folder.Parent = testContent

	local made: Made = { parts = { folder }, stops = {}, moved = false }
	for index: number, occluder: Gap.Part in layout.occluders do
		table.insert(made.parts, part(`GapOccluder{index}`, occluder, false, true, occluders))
	end

	local window: ClientLines.Window = ClientLines.new(GapLine.ATTRIBUTE, WAIT)
	table.insert(made.stops, ClientLines.listen(window, RATE))

	local relay: { read past: boolean? }? = settings.relay
	local cone: number? = nil
	local outOfView: { rate: number, cone: number, radius: number }? = settings.tiers.outOfView
	if outOfView then
		cone = outOfView.cone
	end

	local context: Context = {
		server = server,
		player = player,
		character = character,
		layout = layout,
		blocked = Engine.occlusion(settings.antiEsp.include),
		window = window,
		probe = ClientLines.probe(window, nil),
		sprint = shared.step.sprint,
		rate = shared.rates.relay,
		nearRadius = settings.antiEsp.nearRadius,
		cone = cone,
		pastOn = relay ~= nil and relay.past == true,
	}

	local problems: { string } = {}
	local ran: boolean, result: any = pcall(drive, context, made, problems)

	-- Everything it made goes, whatever the passes did
	for _, stop: () -> () in made.stops do
		stop()
	end

	Workspace:SetAttribute(GapLine.SLOT, nil)
	for _, problem: string in Fleet.clear() do
		table.insert(problems, problem)
	end

	for _, instance: Instance in made.parts do
		instance:Destroy()
	end

	if made.moved then
		local respawned: boolean, failure: any = pcall(Game.respawn, player)
		if not respawned then
			table.insert(problems, `{player.Name} was not respawned: {failure}`)
		end
	end

	local line: string = ""
	if ran then
		line = result
	else
		table.insert(problems, `the check threw: {result}`)
	end

	for _, problem: string in window.problems do
		table.insert(problems, problem)
	end

	print(`GapCrossing: {line}`)

	if #problems > 0 then
		return false, `{line}{SEPARATOR}{table.concat(problems, SEPARATOR)}`
	end

	return true, line
end
