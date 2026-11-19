--[[
    character:teleport on bots on a floor of the scenario's own and on the
    real player along the plaza: when each lands, what the landing sets, a
    replaced, a cancelled and a refused teleport, and the timeout path
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Promise: any = require(Packages.Promise)
local Tread = require(Packages.Tread)

local Constants = require(Packages.Tread.Constants)

local Game = require(ServerScriptService.Server.Game)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local PLAY_BOUND: number = Constants.PLAY_BOUND
local CENTER: Vector3 = require(ServerScriptService.Server.Config.Staff).teleport.center
local PLATFORM: number = require(ServerScriptService.Server.Config.Staff).teleport.platform
local DECK: Vector3 = require(ServerScriptService.Server.Config.Staff).teleport.deck
local HEIGHT: number = require(ServerScriptService.Server.Config.Staff).teleport.height
local WALKING: number = require(ServerScriptService.Server.Config.Staff).teleport.walking
local ALONG: number = require(ServerScriptService.Server.Config.Staff).teleport.along
local PROBE: number = require(ServerScriptService.Server.Config.Staff).teleport.probe
local CANCEL: number = require(ServerScriptService.Server.Config.Staff).teleport.cancel
local SPOTS = require(ServerScriptService.Server.Config.Staff).teleport.spots
local LIFT: number = require(ServerScriptService.Server.Config.Staff).floor.lift
local SETTLE: number = require(ServerScriptService.Server.Config.Staff).waits.settle
local LANDING: number = require(ServerScriptService.Server.Config.Staff).waits.landing
local CLOSE: number = require(ServerScriptService.Server.Config.Staff).close
local FACING: number = require(ServerScriptService.Server.Config.Staff).facing
local NAME: string = "Teleport"
local TOWARD_X: number = -math.pi / 2 -- The step's yaw that looks along +X
local EPOCH_WRAP: number = 2 ^ 8 -- The full epoch is a u8, so one past its top wraps to 0
local OUTSIDE: number = PLAY_BOUND + 1 -- A stud past the play bound along X, where a destination is refused
local NAN: number = 0 / 0 -- The one number that differs from itself, for a look that is not finite
local TURN: number = 2 * math.pi
local SEPARATOR: string = "; " -- Between the parts of a report

-- How far apart two points are across the ground
local function across(from: Vector3, to: Vector3): number
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
end

-- The step's facing a CFrame's look gives, along -Z at 0 and -X at a quarter turn
local function facingOf(at: CFrame): number
	local look: Vector3 = at.LookVector

	return math.atan2(-look.X, -look.Z)
end

-- How far one facing lies from another on the shortest arc, from -π to π
local function arc(from: number, to: number): number
	return (to - from + math.pi) % TURN - math.pi
end

--[[
    Checks what every landing sets: the feet at the destination facing
    along its look, no velocity, the epoch one on, no command left queued,
    and onTeleported heard once
--]]

local function judge(name: string, landing: Testbed.Landing, problems: { string })
	local after: Testbed.Snapshot? = landing.after
	if not after then
		table.insert(problems, `{name} never landed`)

		return
	end

	local before: Testbed.Snapshot = landing.before
	local at: CFrame = landing.at
	local off: number = (after.root - at.Position).Magnitude
	local turned: number = math.abs(arc(facingOf(at), after.facing))

	if off > CLOSE then
		table.insert(problems, `{name} landed {off} studs from its destination {at.Position}`)
	end

	if turned > FACING then
		table.insert(problems, `{name} landed facing {turned} radians off its destination's look`)
	end

	if after.velocity.Magnitude > 0 then
		table.insert(problems, `{name} landed moving at {after.velocity}`)
	end

	if after.epoch ~= (before.epoch + 1) % EPOCH_WRAP then
		table.insert(problems, `{name}'s epoch went from {before.epoch} to {after.epoch}, not one on`)
	end

	if after.queued > 0 then
		table.insert(problems, `{name} landed with {after.queued} commands still queued`)
	end

	if landing.heard ~= 1 then
		table.insert(problems, `onTeleported heard {name} land {landing.heard} times, not once`)
	end
end

--[[
    Where the real player is sent along the plaza: its spawn area's longer
    axis, toward the area's middle, the destination's ground found by a cast
    down through the shared table's collision include, the facing kept
--]]

local function along(before: Testbed.Snapshot, include: { Instance }): CFrame
	local testContent: Instance? = Workspace:FindFirstChild("TestContent")
	local cityBlock: Instance? = testContent and testContent:FindFirstChild("CityBlock")
	if not cityBlock then
		error("Workspace.TestContent.CityBlock is missing, so the plaza has no spawn area to move along")
	end

	local low: any = cityBlock:GetAttribute("SpawnAreaMin")
	local high: any = cityBlock:GetAttribute("SpawnAreaMax")
	if typeof(low) ~= "Vector3" or typeof(high) ~= "Vector3" then
		error(`{cityBlock:GetFullName()} has no SpawnAreaMin and SpawnAreaMax, so the plaza has no axis to move along`)
	end

	local span: Vector3 = high - low
	local middle: Vector3 = (low + high) / 2
	local axis: Vector3 = Vector3.zAxis
	if math.abs(span.X) >= math.abs(span.Z) then
		axis = Vector3.xAxis
	end

	local toward: number = (middle - before.root):Dot(axis) < 0 and -1 or 1
	local point: Vector3 = before.root + axis * toward * ALONG

	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = true
	params.IgnoreWater = true

	local hit: RaycastResult? =
		Workspace:Raycast(point + Vector3.new(0, PROBE, 0), Vector3.new(0, -(PROBE + PROBE), 0), params)
	if not hit then
		error(`no ground lies within {PROBE} studs of {point}, {ALONG} studs along the plaza`)
	end

	return CFrame.new(hit.Position + Vector3.new(0, LIFT, 0)) * CFrame.Angles(0, before.facing, 0)
end

--[[
    The bots: a mover teleported off a platform while walking, a second
    call replacing a first, a death cancelling one, and the destinations
    refused
--]]

local function bots(testbed: Testbed.Testbed, problems: { string }, figures: { string }, seconds: number)
	local server: Tread.Server, shared: Tread.Shared = Game.get()
	local deckCenter: Vector3 = CENTER + Vector3.new(0, HEIGHT, 0)

	local platform: Tread.Platform = {
		id = PLATFORM,
		boxes = { { center = Vector3.zero, size = DECK } },

		path = function (_: number, _: number?): Vector3
			return deckCenter
		end,
	}

	testbed:own(server:addPlatform(platform))

	local heard: { [Tread.Character]: number } = {}
	testbed:own(server:onTeleported(function (moved: Tread.Character)
		heard[moved] = (heard[moved] or 0) + 1
	end))

	local moverInputs: Testbed.Inputs = { forward = 0, right = 0, yaw = 0, sprint = false, crouch = false }
	local onDeck: CFrame = testbed:place(Vector3.new(0, HEIGHT + DECK.Y / 2, 0), 0)
	local mover: Tread.Character = testbed:bot("Mover", onDeck, moverInputs)
	local replacer: Tread.Character = testbed:plain("Replacer", testbed:place(SPOTS.replacer, 0))
	local cancelled: Tread.Character = testbed:plain("Cancelled", testbed:place(SPOTS.cancelled, 0))

	local boarded: boolean, boardFailure: any = testbed
		:waitFor("the bots to land and the mover to board the deck", function (_: number): boolean
			local state: Tread.State = mover:getState()

			return state.grounded
				and state.platform == PLATFORM
				and replacer:getState().grounded
				and cancelled:getState().grounded
		end, SETTLE)
		:await()

	if not boarded then
		table.insert(problems, tostring(boardFailure))

		return
	end

	-- 1) The mover walks on the deck, and is teleported off it in mid-stride
	moverInputs.forward = 1

	local walking: boolean, walkFailure: any = testbed
		:waitFor("the mover to walk on the deck", function (_: number): boolean
			local state: Tread.State = mover:getState()
			local speed: number = Vector3.new(state.velocity.X, 0, state.velocity.Z).Magnitude

			return state.platform == PLATFORM and speed >= WALKING * shared.step.walk
		end, SETTLE)
		:await()

	if not walking then
		table.insert(problems, tostring(walkFailure))

		return
	end

	local moved: boolean, moverLanding: any = testbed
		:teleport(mover, function (_: Testbed.Snapshot): { CFrame }
			return { testbed:place(SPOTS.mover, TOWARD_X) }
		end, seconds)
		:await()

	moverInputs.forward = 0

	if not moved then
		table.insert(problems, `the mover: {moverLanding}`)

		return
	end

	local landing: Testbed.Landing = moverLanding
	local before: Testbed.Snapshot = landing.before
	local after: Testbed.Snapshot? = landing.after
	judge("the mover", landing, problems)

	if before.platform ~= PLATFORM or before.queued == 0 or across(Vector3.zero, before.velocity) == 0 then
		local held: string = `platform {before.platform}, {before.queued} queued, velocity {before.velocity}`
		table.insert(problems, `the mover was not riding, walking and queued before its teleport: {held}`)
	end

	if after and after.platform ~= 0 then
		table.insert(problems, `the mover landed still riding platform {after.platform}`)
	end

	local moverTicks: number = (landing.landed or 0) - landing.scheduled
	if landing.landed and moverTicks ~= 1 then
		table.insert(problems, `the mover, a bot, landed {moverTicks} ticks after its call, not on the next tick`)
	end

	if after then
		local line: string = `epoch {before.epoch} to {after.epoch}, {before.queued} queued to {after.queued}`
		table.insert(
			figures,
			`the mover landed {moverTicks} tick after its call, {line}, off platform {before.platform}`
		)
	end

	-- 2) A second call before the first lands replaces it
	local first: CFrame = testbed:place(SPOTS.first, 0)
	local second: CFrame = testbed:place(SPOTS.second, TOWARD_X)
	local replaced: boolean, replaceLanding: any = testbed
		:teleport(replacer, function (_: Testbed.Snapshot): { CFrame }
			return { first, second }
		end, seconds)
		:await()

	if not replaced then
		table.insert(problems, `the replacer: {replaceLanding}`)
	else
		local replacement: Testbed.Landing = replaceLanding
		local landed: Testbed.Snapshot? = replacement.after
		judge("the replaced teleport", replacement, problems)

		if landed then
			local fromFirst: number = (landed.root - first.Position).Magnitude
			local fromSecond: number = (landed.root - second.Position).Magnitude
			local heardIt: number = replacement.heard
			local where: string =
				string.format("%.3f studs from the second destination, %.1f from the first", fromSecond, fromFirst)
			table.insert(figures, `the replaced teleport landed {where}, heard {heardIt} times`)
		end
	end

	-- 3) A death before the landing cancels it
	cancelled:teleport(testbed:place(SPOTS.away, 0))
	local body: Tread.Body = cancelled:die(nil)
	testbed:own(function ()
		body:destroy()
	end)

	-- 4) A destination out of bounds and a look that is not finite are refused, and schedule nothing
	local unlooked: CFrame = CFrame.new(CENTER) * CFrame.Angles(0, NAN, 0)
	local look: Vector3 = unlooked.LookVector
	if look.X == look.X and look.Z == look.Z then
		table.insert(problems, `the engine gave the look meant to be NaN as {look}, so that refusal went untested`)
	end

	local heardBefore: number = heard[replacer] or 0
	local destinations: { CFrame } = { CFrame.new(OUTSIDE, CENTER.Y, CENTER.Z), unlooked }
	local refusals: number = 0
	for _, refused: CFrame in destinations do
		if pcall(replacer.teleport, replacer, refused) then
			table.insert(problems, `teleport took {refused.Position} looking along {refused.LookVector}`)
		else
			refusals += 1
		end
	end

	local waited: boolean, waitFailure: any = testbed:ticks(CANCEL):await()
	if not waited then
		table.insert(problems, tostring(waitFailure))
	end

	if (heard[cancelled] or 0) > 0 then
		table.insert(problems, "the teleport of the character that died landed anyway")
	end

	if (heard[replacer] or 0) ~= heardBefore then
		table.insert(problems, "a refused teleport landed")
	end

	table.insert(figures, `a death cancelled its teleport, and {refusals} of {#destinations} destinations were refused`)
end

--[[
    The real player: about 50 studs along the plaza and back, each through
    the engine's stream-around and landing inside the timeout, then in place
    with a prestream hook whose Promise is held, so it lands on the timeout
--]]

local function realPlayer(testbed: Testbed.Testbed, problems: { string }, figures: { string }, seconds: number)
	local _: Tread.Server, shared: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	local limit: number = math.ceil(settings.teleport.timeout * shared.rates.simulation)
	local include: { Instance }? = shared.collision.include

	local _: Player?, character: Tread.Character? = testbed:real()
	if not character then
		table.insert(problems, "no real player in the server has a character to teleport along the plaza")

		return
	elseif not include then
		table.insert(problems, "the shared table's collision has no include list to find the plaza's ground with")

		return
	end

	local body: Tread.Character = character
	local ground: { Instance } = include
	local found: Tread.State = body:getState()
	local home: CFrame = CFrame.new(found.root) * CFrame.Angles(0, found.facing, 0)

	-- Sent back where it stood unless the run brought it back itself
	local returned: boolean = true
	testbed:own(function ()
		if not returned then
			body:teleport(home)
		end
	end)

	-- One leg, landing through the engine's stream-around before the timeout's tick, giving whether it landed
	local function leg(name: string, destinations: (before: Testbed.Snapshot) -> { CFrame }): boolean
		local went: boolean, result: any = testbed:teleport(body, destinations, seconds):await()
		if not went then
			table.insert(problems, `{name}: {result}`)

			return false
		end

		local landing: Testbed.Landing = result
		judge(name, landing, problems)

		local landed: number? = landing.landed
		if not landed then
			return false
		end

		local took: number = landed - landing.scheduled
		local moved: number = across(landing.before.root, landing.at.Position)
		if took >= limit then
			table.insert(problems, `{name} took {took} ticks to land, the timeout's {limit} or more`)
		end

		table.insert(
			figures,
			string.format("%s, %.1f studs, landed in %d of the timeout's %d ticks", name, moved, took, limit)
		)

		return true
	end

	returned = false
	leg("the real player's move along the plaza", function (before: Testbed.Snapshot): { CFrame }
		return { along(before, ground) }
	end)

	returned = leg("the real player's move back", function (_: Testbed.Snapshot): { CFrame }
		return { home }
	end)

	-- Each leg waits on the engine's stream-around only while streaming is on
	table.insert(figures, `Workspace.StreamingEnabled {Workspace.StreamingEnabled}`)

	-- In place, with a prestream hook whose Promise is held until the landing, so the timeout sets it down
	local release: ((...any) -> ())? = nil
	local held: any = Promise.new(function (resolve: (...any) -> ())
		release = resolve
	end)

	settings.prestream = function (_: Player, _: CFrame): any
		return held
	end

	testbed:own(function ()
		settings.prestream = nil

		local free: ((...any) -> ())? = release
		if free then
			free()
		end
	end)

	local waited: boolean, result: any = testbed
		:teleport(body, function (_: Testbed.Snapshot): { CFrame }
			return { home }
		end, seconds)
		:await()

	settings.prestream = nil
	local free: ((...any) -> ())? = release
	if free then
		free()
	end

	if not waited then
		table.insert(problems, `the teleport held by its prestream hook: {result}`)

		return
	end

	local landing: Testbed.Landing = result
	local took: number = (landing.landed or 0) - landing.scheduled
	if not landing.landed or took ~= limit then
		table.insert(
			problems,
			`the teleport held by its prestream hook landed after {took} ticks, not the timeout's {limit}`
		)
	elseif landing.heard ~= 1 then
		table.insert(problems, `onTeleported heard the held teleport land {landing.heard} times, not once`)
	else
		table.insert(figures, `the teleport held by its hook landed on the timeout's tick, {took} after its call`)
	end
end

return function (): (boolean, string | nil)
	local built: boolean, made: any = pcall(Testbed.new, NAME, CENTER)
	if not built then
		return false, `its floor could not be laid: {made}`
	end

	local testbed: Testbed.Testbed = made
	local problems: { string } = {}
	local figures: { string } = {}
	local _: Tread.Server, _: Tread.Shared, settings: Tread.ServerSettings = Game.get()
	local seconds: number = settings.teleport.timeout + LANDING

	local ran: boolean, failure: any = pcall(function ()
		local beat: boolean, beatFailure: any = testbed:heartbeat():await()
		if not beat then
			table.insert(problems, tostring(beatFailure))

			return
		end

		bots(testbed, problems, figures, seconds)
		realPlayer(testbed, problems, figures, seconds)
	end)

	if not ran then
		table.insert(problems, `the checks threw: {failure}`)
	end

	-- Everything it made goes, whatever the checks found
	for _, problem: string in testbed:clean() do
		table.insert(problems, problem)
	end

	local line: string = table.concat(figures, SEPARATOR)
	print(`{NAME}: {line}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
