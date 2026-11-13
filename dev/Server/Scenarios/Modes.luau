--[[
    The staff move modes on bots on a floor of the scenario's own: Noclip and
    Parked bodies neither block nor are blocked and keep no history, one left
    in a block returns to Walk on top of it, and setMode refuses the rest
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Game = require(ServerScriptService.Server.Game)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.Staff).modes.center
local LANE: number = require(ServerScriptService.Server.Config.Staff).modes.lane
local START: number = require(ServerScriptService.Server.Config.Staff).modes.start
local OBSTACLE: number = require(ServerScriptService.Server.Config.Staff).modes.obstacle
local BLOCK: Vector3 = require(ServerScriptService.Server.Config.Staff).modes.block
local STOP: number = require(ServerScriptService.Server.Config.Staff).modes.stop
local THROUGH: number = require(ServerScriptService.Server.Config.Staff).modes.through
local SHORT: number = require(ServerScriptService.Server.Config.Staff).modes.short
local STILL: number = require(ServerScriptService.Server.Config.Staff).modes.still
local WINDOW: number = require(ServerScriptService.Server.Config.Staff).modes.window
local PASS: number = require(ServerScriptService.Server.Config.Staff).modes.pass
local SETTLE: number = require(ServerScriptService.Server.Config.Staff).waits.settle
local CLOSE: number = require(ServerScriptService.Server.Config.Staff).close
local REST: number = require(ServerScriptService.Server.Config.Staff).rest
local NAME: string = "Modes"
local TOWARD_X: number = -math.pi / 2 -- The step's yaw that looks along +X, the way every mover goes
local MIDDLE_LANE: number = 3 -- The lane at the floor's center, of the five
local BLOCK_LANE: number = 5 -- The lane the block and the flyer it takes in share
local REFUSED: { any } = { "Fly", "walk", 1 } -- What setMode must refuse: no such mode, a wrong case, no string
local SEPARATOR: string = "; " -- Between the parts of a report

-- A mover headed at an obstacle in its lane, and whether it must pass through it
type Run = {
	name: string,
	mover: Tread.Character,
	inputs: Testbed.Inputs,
	obstacle: Tread.Character,
	passed: boolean,
}

-- A mover's inputs, at rest and facing along +X
local function still(): Testbed.Inputs
	return { forward = 0, right = 0, yaw = TOWARD_X, sprint = false, crouch = false }
end

-- How far along Z from the center a lane runs
local function laneZ(lane: number): number
	return (lane - MIDDLE_LANE) * LANE
end

-- Where a body stands in a lane, along X from the center, facing along +X
local function spot(testbed: Testbed.Testbed, x: number, lane: number): CFrame
	return testbed:place(Vector3.new(x, 0, laneZ(lane)), TOWARD_X)
end

-- How far apart two points are across the ground
local function across(from: Vector3, to: Vector3): number
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
end

--[[
    Everything once the floor and the block stand: the bodies built and
    landed, their modes set, the history read, the movers sent at their
    obstacles, the flyer left in the block and returned to Walk, and the
    refusals, each check's figures added as it runs
--]]

local function drive(testbed: Testbed.Testbed, problems: { string }, figures: { string })
	local server: Tread.Server, shared: Tread.Shared = Game.get()
	local touching: number = shared.step.radius + shared.step.radius -- Studs along X between two hulls that touch
	local blockCenter: Vector3 = CENTER + Vector3.new(OBSTACLE, BLOCK.Y / 2, laneZ(BLOCK_LANE))
	local blockTop: number = CENTER.Y + BLOCK.Y

	testbed:part("Block", BLOCK, CFrame.new(blockCenter), true)

	local beat: boolean, beatFailure: any = testbed:heartbeat():await()
	if not beat then
		table.insert(problems, tostring(beatFailure))

		return
	end

	-- 1) The five lanes: a walker held by a walking control, walkers into a Parked and a Noclip body, a Noclip
	-- flyer into a walking body, and a Noclip flyer the block takes in
	local heldInputs: Testbed.Inputs = still()
	local parkedInputs: Testbed.Inputs = still()
	local noclipInputs: Testbed.Inputs = still()
	local flyerInputs: Testbed.Inputs = still()
	local buriedInputs: Testbed.Inputs = still()

	local held: Tread.Character = testbed:bot("HeldWalker", spot(testbed, START, 1), heldInputs)
	local control: Tread.Character = testbed:bot("Control", spot(testbed, OBSTACLE, 1), nil)
	local parkedWalker: Tread.Character = testbed:bot("ParkedWalker", spot(testbed, START, 2), parkedInputs)
	local parked: Tread.Character = testbed:bot("Parked", spot(testbed, OBSTACLE, 2), nil)
	local noclipWalker: Tread.Character = testbed:bot("NoclipWalker", spot(testbed, START, 3), noclipInputs)
	local noclip: Tread.Character = testbed:bot("Noclip", spot(testbed, OBSTACLE, 3), nil)
	local flyer: Tread.Character = testbed:bot("Flyer", spot(testbed, START, 4), flyerInputs)
	local stander: Tread.Character = testbed:bot("Stander", spot(testbed, OBSTACLE, 4), nil)
	local buried: Tread.Character = testbed:bot("Buried", spot(testbed, START, BLOCK_LANE), buriedInputs)
	local everyone: { Tread.Character } =
		{ held, control, parkedWalker, parked, noclipWalker, noclip, flyer, stander, buried }

	local landed: boolean, landFailure: any = testbed
		:waitFor("every body to land on the floor", function (_: number): boolean
			for _, body: Tread.Character in everyone do
				if not body:getState().grounded then
					return false
				end
			end

			return true
		end, SETTLE)
		:await()

	if not landed then
		table.insert(problems, tostring(landFailure))

		return
	end

	parked:setMode("Parked")
	noclip:setMode("Noclip")
	flyer:setMode("Noclip")
	buried:setMode("Noclip")

	local obstacles: { Tread.Character } = { control, parked, noclip, stander }
	local placed: { [Tread.Character]: Vector3 } = {}
	for _, body: Tread.Character in obstacles do
		placed[body] = body:getState().root
	end

	-- 2) Every relay tick the walking control has a sample, and no Noclip or Parked body does
	local quiet: { Tread.Character } = { parked, noclip, flyer, buried }
	local sampled: boolean, history: any = testbed
		:sample(WINDOW, function (relayTick: number): string?
			if server:sampleAt(control, relayTick) == nil then
				return "the walking control had no sample"
			end

			for _, body: Tread.Character in quiet do
				if server:sampleAt(body, relayTick) ~= nil then
					return `{body.player.Name}, in Noclip or Parked, had a sample`
				end
			end

			return nil
		end)
		:await()

	if not sampled then
		table.insert(problems, tostring(history))
	elseif history then
		table.insert(problems, `the history: {history}`)
	else
		table.insert(figures, `no sample of a Noclip or Parked body over {WINDOW} relay ticks, the control's on each`)
	end

	-- 3) The movers go; each that must pass through its obstacle stops once it has
	local runs: { Run } = {
		{
			name = "the walker into the Parked body",
			mover = parkedWalker,
			inputs = parkedInputs,
			obstacle = parked,
			passed = false,
		},
		{
			name = "the walker into the Noclip body",
			mover = noclipWalker,
			inputs = noclipInputs,
			obstacle = noclip,
			passed = false,
		},
		{
			name = "the Noclip flyer into the walking body",
			mover = flyer,
			inputs = flyerInputs,
			obstacle = stander,
			passed = false,
		},
	}

	heldInputs.forward = 1
	for _, run: Run in runs do
		run.inputs.forward = 1
	end

	local passed: boolean, passFailure: any = testbed
		:waitFor("the walkers and the flyer to pass through their obstacles", function (_: number): boolean
			local all: boolean = true

			for _, run: Run in runs do
				if not run.passed then
					local beyond: number = run.mover:getState().root.X - placed[run.obstacle].X
					if beyond >= touching + THROUGH then
						run.passed = true
						run.inputs.forward = 0
					else
						all = false
					end
				end
			end

			return all
		end, PASS)
		:await()

	if not passed then
		for _, run: Run in runs do
			if not run.passed then
				local beyond: number = run.mover:getState().root.X - placed[run.obstacle].X
				table.insert(problems, `{run.name} stood {beyond} studs past it along X, short of passing through`)
			end
		end

		table.insert(problems, tostring(passFailure))
	end

	-- The control's hull holds the walker that kept pushing at it the whole time
	local gap: number = placed[control].X - held:getState().root.X
	heldInputs.forward = 0

	if gap < touching - CLOSE then
		table.insert(problems, `the walker went into the walking control, its feet {gap} studs short of the control's`)
	elseif gap > touching + SHORT then
		table.insert(problems, `the walker stopped {gap} studs short of the walking control, never reaching it`)
	end

	for _, body: Tread.Character in obstacles do
		local moved: number = (body:getState().root - placed[body]).Magnitude
		if moved > CLOSE then
			table.insert(problems, `{body.player.Name} was moved {moved} studs by the bodies sent at it`)
		end
	end

	if passed then
		table.insert(
			figures,
			string.format("each mover passed through, the walker held %.3f studs from the control", gap)
		)
	end

	-- 4) The second flyer stops inside the block, rests, and returns to Walk
	local stopped: boolean = false
	local quietTicks: number = 0
	local last: Vector3? = nil

	buriedInputs.forward = 1

	local rested: boolean, restFailure: any = testbed
		:waitFor("the flyer to come to rest inside the block", function (_: number): boolean
			local root: Vector3 = buried:getState().root
			if not stopped and root.X >= blockCenter.X - STOP then
				stopped = true
				buriedInputs.forward = 0
			end

			if stopped and root == last then
				quietTicks += 1
			else
				quietTicks = 0
			end

			last = root

			return quietTicks >= STILL
		end, PASS)
		:await()

	if not rested then
		table.insert(problems, tostring(restFailure))

		return
	end

	local inside: Vector3 = buried:getState().root
	local halfX: number = BLOCK.X / 2 - shared.step.radius
	local halfZ: number = BLOCK.Z / 2 - shared.step.radius
	if
		math.abs(inside.X - blockCenter.X) > halfX
		or math.abs(inside.Z - blockCenter.Z) > halfZ
		or inside.Y >= blockTop
	then
		table.insert(problems, `the flyer came to rest at {inside}, not wholly inside the block at {blockCenter}`)

		return
	end

	local stuck: number = 0
	testbed:own(server:onReport(function (player: (Player | Tread.Bot)?, kind: string, _: number | string)
		if player == buried.player and kind == "stuck" then
			stuck += 1
		end
	end))

	buried:setMode("Walk")

	local stepped: boolean, stepFailure: any = testbed:ticks(1):await()
	if not stepped then
		table.insert(problems, tostring(stepFailure))

		return
	end

	local out: Vector3 = buried:getState().root
	local rise: number = out.Y - blockTop
	local aside: number = across(inside, out)

	if rise < 0 or rise > REST then
		table.insert(problems, `back in Walk the flyer's feet stood {rise} studs above the block's top, not on it`)
	end

	if aside > CLOSE then
		table.insert(problems, `back in Walk the flyer was pushed {aside} studs aside, not straight up`)
	end

	if stuck > 0 then
		table.insert(problems, `the flyer's return to Walk was reported stuck {stuck} times`)
	end

	table.insert(
		figures,
		string.format("the flyer left in the block rose to %.3f studs above its top, %.4f aside", rise, aside)
	)

	-- 5) setMode refuses anything but Walk, Noclip and Parked
	local refusals: number = 0
	for _, mode: any in REFUSED do
		if pcall(control.setMode, control, mode) then
			table.insert(problems, `setMode took {tostring(mode)}`)
		else
			refusals += 1
		end
	end

	table.insert(figures, `setMode refused {refusals} of {#REFUSED}`)
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
