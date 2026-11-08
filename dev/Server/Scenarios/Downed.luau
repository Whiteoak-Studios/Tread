--[[
    character:setDowned and the dev game's beingRevived field on bots on a
    floor of the scenario's own: the crawl's speed cap and its stop while
    revived, a fall, the crouched hull, and a revive under a low slab
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Command = require(Packages.Tread.Codec.Command)

local Game = require(ServerScriptService.Server.Game)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.Staff).downed.center
local LANE: number = require(ServerScriptService.Server.Config.Staff).downed.lane
local GAP: number = require(ServerScriptService.Server.Config.Staff).downed.gap
local SLAB: Vector3 = require(ServerScriptService.Server.Config.Staff).downed.slab
local DROP: number = require(ServerScriptService.Server.Config.Staff).downed.drop
local WINDOW: number = require(ServerScriptService.Server.Config.Staff).downed.window
local SHARE: number = require(ServerScriptService.Server.Config.Staff).downed.share
local FASTER: number = require(ServerScriptService.Server.Config.Staff).downed.faster
local STILL: number = require(ServerScriptService.Server.Config.Staff).downed.still
local SHORT: number = require(ServerScriptService.Server.Config.Staff).downed.short
local HOLD: number = require(ServerScriptService.Server.Config.Staff).downed.hold
local UNDER: number = require(ServerScriptService.Server.Config.Staff).downed.under
local SETTLE: number = require(ServerScriptService.Server.Config.Staff).waits.settle
local STEPS: number = require(ServerScriptService.Server.Config.Staff).waits.steps
local SLACK: number = require(ServerScriptService.Server.Config.Staff).waits.slack
local CLOSE: number = require(ServerScriptService.Server.Config.Staff).close
local REST: number = require(ServerScriptService.Server.Config.Staff).rest
local NAME: string = "Downed"
local SEPARATOR: string = "; " -- Between the parts of a report

-- How far apart two points are across the ground
local function across(from: Vector3, to: Vector3): number
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
end

-- A declared field's value when a body is built, as the step's own blocks start it: its start, else false or 0
local function startOf(field: Tread.Field): any
	if field.start ~= nil then
		return field.start
	elseif field.type == "bool" then
		return false
	end

	return 0
end

--[[
    The dev rules' crawl speed: what the shared table's rules function caps
    a downed body's step at on the ground while nobody revives it, read from
    the function itself with the declarations' starts in its blocks
--]]

local function crawlOf(shared: Tread.Shared): number
	local command: Tread.Command = Command.new()
	local block: { [string]: any } = {}
	local fields: { [string]: any } = {}

	for _, field: Tread.Field in shared.fields.rules do
		block[field.name] = startOf(field)
	end

	for _, field: Tread.Field in shared.fields.server do
		fields[field.name] = startOf(field)
	end

	local step: Tread.RuleStep = {
		command = command,
		pressed = command.pressed,
		grounded = true,
		mode = "Ground",
		posture = "Downed",
		airTicks = 0,
		groundTicks = 0,
		fields = fields,
		held = {},
		block = block,
		isNpc = false,
	}

	local allow: Tread.Allow = { jump = true, sprint = true, crouch = true, stand = true }

	return shared.rules(step, allow)
end

-- Whether a ray up into the slab from under it meets it
local function meets(slab: Part): boolean
	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { slab }

	local under: Vector3 = slab.Position - Vector3.new(0, slab.Size.Y, 0)

	return Workspace:Raycast(under, Vector3.new(0, slab.Size.Y, 0), params) ~= nil
end

--[[
    Everything once the floor and the slab stand: the faller's fall, the
    crawl at its cap toward the slab and under it, where the standing walker
    is held, its stop while revived, its revive under the slab, and its
    stand once out from under it
--]]

local function drive(testbed: Testbed.Testbed, problems: { string }, figures: { string })
	local server: Tread.Server, shared: Tread.Shared = Game.get()
	local radius: number = shared.step.radius
	local crouched: number = shared.step.crouched
	local rate: number = shared.rates.simulation
	local crawl: number = crawlOf(shared)

	-- 1) The slab, its underside between the crouched hull's top and the standing one's, across both lanes
	local nearZ: number = -(radius + GAP) -- Its edge nearest the bodies, from the center along Z
	local farZ: number = nearZ - SLAB.Z
	local underside: number = (crouched + shared.step.standing) / 2
	local slabCenter: Vector3 = CENTER + Vector3.new(LANE / 2, underside + SLAB.Y / 2, nearZ - SLAB.Z / 2)
	local slab: Part = testbed:part("Ceiling", SLAB, CFrame.new(slabCenter), true)

	-- Terrain reaches a ray only from the next Heartbeat, so a part may too; a ray now and one after it tell which
	local atOnce: boolean = meets(slab)

	local beat: boolean, beatFailure: any = testbed:heartbeat():await()
	if not beat then
		table.insert(problems, tostring(beatFailure))

		return
	end

	local afterBeat: boolean = meets(slab)
	local now: string = atOnce and "at once" or "not at once"
	local later: string = afterBeat and "after" or "not after"
	table.insert(figures, `a ray met the slab {now}, and {later} the next Heartbeat`)

	if not afterBeat then
		table.insert(problems, "a ray up into the slab missed it a Heartbeat after it was built")

		return
	end

	-- 2) The bodies, each facing -Z toward the slab: the crawler, the standing walker beside it, and the faller
	local crawlInputs: Testbed.Inputs = { forward = 0, right = 0, yaw = 0, sprint = false, crouch = false }
	local walkInputs: Testbed.Inputs = { forward = 0, right = 0, yaw = 0, sprint = false, crouch = false }
	local crawler: Tread.Character = testbed:bot("Crawler", testbed:place(Vector3.zero, 0), crawlInputs)
	local walker: Tread.Character = testbed:bot("Walker", testbed:place(Vector3.new(LANE, 0, 0), 0), walkInputs)
	local faller: Tread.Character = testbed:plain("Faller", testbed:place(Vector3.new(-LANE, DROP, 0), 0))
	local fallFrom: number = CENTER.Y + DROP

	-- Downed in the air before its first step
	faller:setDowned(true)

	local landing: { speed: number, apex: number }? = nil
	testbed:own(server:onLanded(function (target: Tread.Target, speed: number, _: Enum.Material, apex: number)
		if target == faller and not landing then
			landing = { speed = speed, apex = apex }
		end
	end))

	-- 3) The faller falls and lands downed, never leaving the posture on the way
	local upright: number = 0
	local fell: boolean, fallFailure: any = testbed
		:waitFor("the downed faller to land", function (_: number): boolean
			local state: Tread.State = faller:getState()
			if state.posture ~= "Downed" then
				upright += 1
			end

			return landing ~= nil and state.grounded
		end, SETTLE)
		:await()

	local landed: { speed: number, apex: number }? = landing
	if not fell or not landed then
		table.insert(problems, tostring(fallFailure))
	else
		local state: Tread.State = faller:getState()
		local height: number = state.root.Y - CENTER.Y
		local box: number = state.standingBox.size.Y

		if upright > 0 then
			table.insert(problems, `the faller left Downed on {upright} ticks of its fall`)
		end

		if not (landed.speed > 0) or landed.apex < fallFrom then
			table.insert(
				problems,
				`the faller's landing counted at {landed.speed} studs/s from an apex of {landed.apex}`
			)
		end

		if height < 0 or height > REST then
			table.insert(problems, `the faller came to rest {height} studs above the floor`)
		end

		if math.abs(box - crouched) > CLOSE then
			table.insert(problems, `the downed faller's hull stood {box} studs tall, not the crouched {crouched}`)
		end

		table.insert(
			figures,
			string.format("the faller fell downed from %.2f and landed at %.2f studs/s", landed.apex, landed.speed)
		)
	end

	local settled: boolean, settleFailure: any = testbed
		:waitFor("the crawler and the walker to land", function (_: number): boolean
			return crawler:getState().grounded and walker:getState().grounded
		end, SETTLE)
		:await()

	if not settled then
		table.insert(problems, tostring(settleFailure))

		return
	end

	-- 4) Downed: the crouched hull, and a crawl pushed forward with sprint held, measured over the window
	crawler:setDowned(true)
	crawlInputs.forward = 1
	crawlInputs.sprint = true
	walkInputs.forward = 1

	local started: boolean, startFailure: any = testbed:ticks(STEPS):await()
	if not started then
		table.insert(problems, tostring(startFailure))

		return
	end

	local hull: number = crawler:getState().standingBox.size.Y
	if math.abs(hull - crouched) > CLOSE then
		table.insert(problems, `the downed crawler's hull stood {hull} studs tall, not the crouched {crouched}`)
	end

	-- Measures a window of ticks: how far the crawler went across the ground and the fastest it moved on any tick
	local function measure(what: string): (number?, number)
		local from: Vector3 = crawler:getState().root
		local fastest: number = 0
		local seen: number = 0

		local measured: boolean, failure: any = testbed
			:waitFor(what, function (_: number): boolean
				local velocity: Vector3 = crawler:getState().velocity
				fastest = math.max(fastest, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
				seen += 1

				return seen >= WINDOW
			end, WINDOW / rate + SLACK)
			:await()

		if not measured then
			table.insert(problems, tostring(failure))

			return nil, fastest
		end

		return across(from, crawler:getState().root), fastest
	end

	local crawled: number?, fastest: number = measure("the crawl's window")
	if crawled then
		local speed: number = crawled / (WINDOW / rate)

		if speed > crawl + FASTER or fastest > crawl + FASTER then
			table.insert(
				problems,
				`the downed crawler went at {speed} studs/s, {fastest} at its fastest, past the crawl's {crawl}`
			)
		elseif speed < crawl * SHARE then
			table.insert(problems, `the downed crawler went at {speed} studs/s, short of the crawl's {crawl}`)
		end

		table.insert(
			figures,
			string.format(
				"the crawl went at %.3f studs/s, %.3f at its fastest, of the rules' %.3f",
				speed,
				fastest,
				crawl
			)
		)
	end

	-- The standing walker has met the slab's edge, where its hull is too tall to pass
	local walkerZ: number = walker:getState().root.Z - CENTER.Z
	local held: number = walkerZ - (nearZ + radius)
	walkInputs.forward = 0

	if held < -CLOSE then
		table.insert(problems, `the standing walker went {-held} studs under the slab`)
	elseif held > SHORT then
		table.insert(problems, `the standing walker stopped {held} studs short of the slab, never reaching it`)
	else
		table.insert(figures, string.format("the standing walker was held %.3f studs from the slab's edge", held))
	end

	-- 5) Being revived, the crawler moves not at all however it is pushed
	crawler:setField("beingRevived", true)

	local reviving: boolean, reviveFailure: any = testbed:ticks(STEPS):await()
	if not reviving then
		table.insert(problems, tostring(reviveFailure))

		return
	end

	local drifted: number? = measure("the revive's window")
	crawler:setField("beingRevived", false)

	if drifted and drifted > STILL then
		table.insert(problems, `the crawler moved {drifted} studs while being revived`)
	elseif drifted then
		table.insert(figures, string.format("the crawler moved %.4f studs while being revived", drifted))
	end

	-- 6) The crouched hull crawls on under the slab, where the standing walker could not go
	local under: boolean, underFailure: any = testbed
		:waitFor("the crawler to reach under the slab", function (_: number): boolean
			if crawler:getState().root.Z - CENTER.Z <= nearZ - radius then
				crawlInputs.forward = 0
				crawlInputs.sprint = false

				return true
			end

			return false
		end, UNDER)
		:await()

	if not under then
		table.insert(problems, tostring(underFailure))

		return
	end

	local stopped: boolean, stopFailure: any = testbed:ticks(STEPS):await()
	if not stopped then
		table.insert(problems, tostring(stopFailure))

		return
	end

	-- 7) Revived under the slab, too low to stand under, it crouches and stays crouched
	crawler:setDowned(false)

	local seen: number = 0
	local standing: number = 0
	local kept: boolean, keepFailure: any = testbed
		:waitFor("the revived crawler's hold under the slab", function (_: number): boolean
			if crawler:getState().posture ~= "Crouch" then
				standing += 1
			end

			seen += 1

			return seen >= HOLD
		end, HOLD / rate + SLACK)
		:await()

	if not kept then
		table.insert(problems, tostring(keepFailure))

		return
	elseif standing > 0 then
		table.insert(problems, `revived under the slab, the crawler was out of Crouch on {standing} of {HOLD} ticks`)
	end

	-- 8) Walked on out from under it, it stands up once its standing hull clears the slab's far edge
	crawlInputs.forward = 1

	local stood: boolean, standFailure: any = testbed
		:waitFor("the revived crawler to stand once out from under the slab", function (_: number): boolean
			return crawler:getState().posture == "Stand"
		end, UNDER)
		:await()

	crawlInputs.forward = 0

	if not stood then
		table.insert(problems, tostring(standFailure))

		return
	end

	local past: number = (farZ - radius) - (crawler:getState().root.Z - CENTER.Z)
	if past < -CLOSE then
		table.insert(problems, `the revived crawler stood {-past} studs before its hull cleared the slab`)
	else
		table.insert(figures, string.format("it stayed crouched under the slab and stood %.3f studs past it", past))
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

	local ran: boolean, failure: any = pcall(drive, testbed, problems, figures)
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
