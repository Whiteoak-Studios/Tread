--[[
    The crouch slide on bots, on a floor and a ramp of the scenario's own: a
    slide from a sprint run out on the flat, one down the ramp to the top
    speed, and a jump out of one with a second slide inside the cooldown
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Fleet = require(ServerScriptService.Server.Bots.Fleet)
local Game = require(ServerScriptService.Server.Game)
local Programs = require(ServerScriptService.Server.Bots.Programs)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.Slide).center
local FLAT: Vector3 = require(ServerScriptService.Server.Config.Slide).flat
local JUMP: Vector3 = require(ServerScriptService.Server.Config.Slide).jump
local TILT: number = require(ServerScriptService.Server.Config.Slide).ramp.tilt
local RUN: number = require(ServerScriptService.Server.Config.Slide).ramp.run
local WIDTH: number = require(ServerScriptService.Server.Config.Slide).ramp.width
local THICKNESS: number = require(ServerScriptService.Server.Config.Slide).ramp.thickness
local FOOT: Vector3 = require(ServerScriptService.Server.Config.Slide).ramp.foot
local START: number = require(ServerScriptService.Server.Config.Slide).ramp.start
local LIFT: number = require(ServerScriptService.Server.Config.Slide).ramp.lift
local CLOSE: number = require(ServerScriptService.Server.Config.Slide).close
local FEWEST: number = require(ServerScriptService.Server.Config.Slide).ticks.fewest
local MOST: number = require(ServerScriptService.Server.Config.Slide).ticks.most
local SHORTEST: number = require(ServerScriptService.Server.Config.Slide).distance.shortest
local LONGEST: number = require(ServerScriptService.Server.Config.Slide).distance.longest
local READY: number = require(ServerScriptService.Server.Config.Slide).ready
local GLIDE: number = require(ServerScriptService.Server.Config.Slide).glide
local WATCH: number = require(ServerScriptService.Server.Config.Slide).watch
local SETTLE: number = require(ServerScriptService.Server.Config.Slide).waits.settle
local SPRINT_WAIT: number = require(ServerScriptService.Server.Config.Slide).waits.sprint
local SLIDE_WAIT: number = require(ServerScriptService.Server.Config.Slide).waits.slide
local AIR_WAIT: number = require(ServerScriptService.Server.Config.Slide).waits.air
local NAME: string = "Slide"
local SEED: number = 1 -- A driven bot has no faults, so nothing its generator draws ever matters
local AHEAD: number = 0 -- A yaw that looks along -Z
local DOWNHILL: number = math.pi / 2 -- A yaw that looks along -X, down the ramp
local SEPARATOR: string = "; " -- Between the parts of a report

-- What a driven bot sends each tick, a table the scenario changes as it goes
type Inputs = {
	forward: number,
	yaw: number, -- Radians, the step's: along -Z at 0 and -X at a quarter turn
	sprint: boolean,
	crouch: boolean,
	jump: boolean,
}

-- How fast a state moves across the ground
local function speedOf(state: Tread.State): number
	local velocity: Vector3 = state.velocity

	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

-- How far apart two points are across the ground
local function across(from: Vector3, to: Vector3): number
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
end

-- A program that sends whatever its inputs hold on each tick, the jump among them
local function drive(inputs: Inputs): Programs.Steer
	return function (command: Tread.Command, _: number, _: vector)
		command.forward = inputs.forward
		command.yaw = inputs.yaw
		command.sprint = inputs.sprint
		command.crouch = inputs.crouch
		command.jump = inputs.jump
	end
end

-- A bot of the harness driven by its inputs, built facing along a yaw, which the testbed's clean-up removes
local function bot(testbed: Testbed.Testbed, name: string, offset: Vector3, inputs: Inputs): Tread.Character
	local entry: Fleet.Entry = Fleet.add({
		name = `{NAME}{name}`,
		group = NAME,
		at = testbed:place(offset, inputs.yaw),
		steer = drive(inputs),
		faults = nil,
		seed = SEED,
	})

	return entry.character
end

-- Waits for a promise and gives whether it held, a failure becoming a problem
local function held(promise: any, problems: { string }): boolean
	local ok: boolean, failure: any = promise:await()
	if not ok then
		table.insert(problems, tostring(failure))
	end

	return ok
end

--[[
    A bot landed where it was built, then sprinting along its inputs' yaw
    until it runs at the sprint, past the dev rules' jump cooldown from its
    build. Gives whether it got there
--]]

local function sprinting(
	testbed: Testbed.Testbed,
	shared: Tread.Shared,
	body: Tread.Character,
	inputs: Inputs,
	problems: { string }
): boolean
	local landed: boolean = held(
		testbed:waitFor(`the {NAME} bot to land`, function (_: number): boolean
			return body:getState().grounded
		end, SETTLE),
		problems
	)

	if not landed or not held(testbed:ticks(READY), problems) then
		return false
	end

	inputs.forward = 1
	inputs.sprint = true

	return held(
		testbed:waitFor("the bot to reach the sprint", function (_: number): boolean
			return speedOf(body:getState()) >= shared.step.sprint - CLOSE
		end, SPRINT_WAIT),
		problems
	)
end

--[[
    The flat run: a crouch pressed in a sprint slides along -Z, losing the
    friction's share of its speed each tick, until its speed is below the
    stop, then stands crouched on the ground, having covered about 24 studs
--]]

local function flat(testbed: Testbed.Testbed, shared: Tread.Shared, problems: { string }, figures: { string })
	local slide: any = shared.step.slide
	local inputs: Inputs = { forward = 0, yaw = AHEAD, sprint = false, crouch = false, jump = false }
	local body: Tread.Character = bot(testbed, "Flat", FLAT, inputs)
	if not sprinting(testbed, shared, body, inputs, problems) then
		return
	end

	inputs.sprint = false
	inputs.crouch = true

	local perTick: number = slide.friction / shared.rates.simulation
	local previous: Vector3 = body:getState().root
	local from: Vector3? = nil
	local first: number = 0
	local last: number = 0
	local ticks: number = 0

	-- The tick it ends on, read then, since getState's table is refilled on every step after
	local endRoot: Vector3? = nil
	local endMode: string = ""
	local endPosture: string = ""
	local stopped: number = 0

	local ended: boolean = held(
		testbed:waitFor("the flat slide to start and end", function (_: number): boolean
			local state: Tread.State = body:getState()
			local speed: number = speedOf(state)

			if state.mode == "Slide" then
				if ticks == 0 then
					from = previous
					first = speed
				elseif math.abs(last - speed - perTick) > CLOSE then
					table.insert(problems, `slide tick {ticks + 1} went from {last} to {speed} studs/s`)
				end

				ticks += 1
				last = speed
			elseif ticks > 0 then
				endRoot, endMode, endPosture, stopped = state.root, state.mode, state.posture, speed

				return true
			end

			previous = state.root

			return false
		end, SLIDE_WAIT),
		problems
	)

	local start: Vector3? = from
	local final: Vector3? = endRoot
	if not ended or not start or not final then
		return
	end

	-- The tick that ends it is still a slide's, run at its speed, so it counts
	local length: number = ticks + 1
	local covered: number = across(start, final)

	if length < FEWEST or length > MOST then
		table.insert(problems, `the flat slide ended after {length} ticks, not {FEWEST} or {MOST}`)
	end

	if covered < SHORTEST or covered > LONGEST then
		table.insert(problems, `the flat slide covered {covered} studs, outside {SHORTEST} to {LONGEST}`)
	end

	if endMode ~= "Ground" or endPosture ~= "Crouch" or stopped >= slide.stop then
		table.insert(problems, `the flat slide ended {endMode} and {endPosture} at {stopped} studs/s`)
	end

	if math.abs(first - (shared.step.sprint - perTick)) > CLOSE then
		table.insert(problems, `the flat slide's first tick ran at {first}, not the sprint less a tick's friction`)
	end

	inputs.forward = 0
	inputs.crouch = false

	table.insert(
		figures,
		string.format(
			"the flat slide ran %.3f to %.3f studs/s over %d ticks, %.3f studs, then stood %s at %.3f",
			first,
			last,
			length,
			covered,
			endPosture,
			stopped
		)
	)
end

--[[
    The ramp run: a crouch pressed in a sprint down the ramp gains speed to
    the top speed and is held there, never past it, still in a slide
--]]

local function ramp(testbed: Testbed.Testbed, shared: Tread.Shared, problems: { string }, figures: { string })
	local slide: any = shared.step.slide
	local radians: number = math.rad(TILT)
	local along: Vector3 = Vector3.new(math.cos(radians), math.sin(radians), 0)
	local normal: Vector3 = Vector3.new(-math.sin(radians), math.cos(radians), 0)
	local length: number = RUN / math.cos(radians)
	local size: Vector3 = Vector3.new(length, THICKNESS, WIDTH)
	local center: Vector3 = CENTER + FOOT + along * (length / 2) - normal * (THICKNESS / 2)
	testbed:part("Ramp", size, CFrame.new(center) * CFrame.Angles(0, 0, radians), true)

	if not held(testbed:heartbeat(), problems) then
		return
	end

	-- Built over the ramp's face, the start down its tilt from the top
	local fromFoot: number = (length - START) * math.cos(radians)
	local offset: Vector3 = FOOT + Vector3.new(fromFoot, fromFoot * math.tan(radians) + LIFT, 0)
	local inputs: Inputs = { forward = 0, yaw = DOWNHILL, sprint = false, crouch = false, jump = false }
	local body: Tread.Character = bot(testbed, "Ramp", offset, inputs)
	if not sprinting(testbed, shared, body, inputs, problems) then
		return
	end

	inputs.sprint = false
	inputs.crouch = true

	local sliding: boolean = false
	local top: number = 0
	local ticks: number = 0

	local reached: boolean = held(
		testbed:waitFor("the ramp's slide to reach the top speed", function (_: number): boolean
			local state: Tread.State = body:getState()
			local speed: number = speedOf(state)

			if state.mode == "Slide" then
				sliding = true
				ticks += 1
				top = math.max(top, speed)

				if speed > slide.max + CLOSE then
					table.insert(problems, `the ramp's slide ran at {speed}, past the top speed of {slide.max}`)
				end

				return speed >= slide.max - CLOSE
			elseif sliding then
				error(`the ramp's slide ended in {state.mode} at {speed} studs/s, before the top speed`)
			end

			return false
		end, SLIDE_WAIT),
		problems
	)

	-- Let go, so it walks to a stop before the floor's edge
	inputs.forward = 0
	inputs.crouch = false

	if reached then
		table.insert(
			figures,
			string.format("down %d degrees the slide reached %.3f studs/s in %d ticks", TILT, top, ticks)
		)
	end
end

--[[
    The jump run: a jump out of a slide leaves it in the air, and a crouch
    pressed in a sprint after landing, inside the cooldown, starts none
--]]

local function jump(testbed: Testbed.Testbed, shared: Tread.Shared, problems: { string }, figures: { string })
	local slide: any = shared.step.slide
	local rate: number = shared.rates.simulation
	local cooldown: number = math.round(slide.cooldown * rate)
	local inputs: Inputs = { forward = 0, yaw = AHEAD, sprint = false, crouch = false, jump = false }
	local body: Tread.Character = bot(testbed, "Jump", JUMP, inputs)
	if not sprinting(testbed, shared, body, inputs, problems) then
		return
	end

	inputs.sprint = false
	inputs.crouch = true

	local glided: number = 0
	local slid: boolean = held(
		testbed:waitFor("the jump run's slide", function (_: number): boolean
			if body:getState().mode == "Slide" then
				glided += 1
			end

			return glided >= GLIDE
		end, SLIDE_WAIT),
		problems
	)

	if not slid then
		return
	end

	inputs.jump = true

	-- Ticks counted from the jump, which the second press must come well inside the cooldown of
	local since: number = 0
	local left: boolean = held(
		testbed:waitFor("the jump to leave the slide for the air", function (_: number): boolean
			since += 1

			return body:getState().mode == "Air"
		end, AIR_WAIT),
		problems
	)

	inputs.jump = false
	if not left then
		return
	end

	local landed: boolean = held(
		testbed:waitFor("the jump to land", function (_: number): boolean
			since += 1
			local state: Tread.State = body:getState()
			if state.mode == "Slide" then
				error("a slide started on the landing, inside the cooldown")
			end

			return state.grounded
		end, AIR_WAIT),
		problems
	)

	if not landed then
		return
	end

	-- A sprint again, then a second crouch press inside the cooldown
	inputs.crouch = false
	inputs.sprint = true

	local sprinted: boolean = held(
		testbed:waitFor("the sprint after the landing", function (_: number): boolean
			since += 1

			return speedOf(body:getState()) >= shared.step.sprint - CLOSE
		end, SPRINT_WAIT),
		problems
	)

	if not sprinted then
		return
	end

	inputs.sprint = false
	inputs.crouch = true

	local watched: number = 0
	local refused: boolean = held(
		testbed:waitFor("the second press's watch", function (_: number): boolean
			since += 1
			watched += 1
			if body:getState().mode == "Slide" then
				error(`a second slide started {since} ticks after the jump, inside its {cooldown}-tick cooldown`)
			end

			return watched >= WATCH
		end, WATCH / rate + SPRINT_WAIT),
		problems
	)

	inputs.forward = 0
	inputs.crouch = false

	if refused and since >= cooldown then
		table.insert(problems, `the watch ran to {since} ticks after the jump, past its {cooldown}-tick cooldown`)
	elseif refused then
		table.insert(figures, `the jump left the slide, and a second press {since} ticks after it slid none`)
	end
end

local function run(testbed: Testbed.Testbed, problems: { string }, figures: { string })
	local _, shared: Tread.Shared = Game.get()
	if shared.step.slide == nil then
		table.insert(problems, "the dev game's shared table gives no crouch slide")

		return
	end

	flat(testbed, shared, problems, figures)
	ramp(testbed, shared, problems, figures)
	jump(testbed, shared, problems, figures)
end

return function (): (boolean, string | nil)
	local built: boolean, made: any = pcall(Testbed.new, NAME, CENTER)
	if not built then
		return false, `its floor could not be laid: {made}`
	end

	local testbed: Testbed.Testbed = made
	local problems: { string } = {}
	local figures: { string } = {}

	local ran: boolean, failure: any = pcall(run, testbed, problems, figures)
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
