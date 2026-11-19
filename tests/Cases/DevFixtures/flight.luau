--[[
    A Bow shot's bullet tests each tick of its flight at the present less
    the render offset it kept from its fire: aimed where a sprinting NPC
    stood at its third tick's time, it strikes there, where both the fire's
    render time and the present would have missed
--]]

--!strict
local DevServer = require("../../Fixtures/DevServer/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local TURN: number = 2 * math.pi
local DELAY: number = 150 -- Milliseconds of interpolation delay the shooter's Move reports, the rewind's least
local REWOUND: number = 5 -- Relay ticks a command's expected render time lies behind it: the 0.1 s round trip and the delay
local SETTLE: number = 20 -- Ticks for both bodies to land and the shooter's eye to settle
local SPRINT: number = 10 -- Ticks the NPC sprints before the shot's command, so it crosses at full speed
local BOW: number = 2 -- The fixture weapon's hotbar slot, 26.05 studs a tick
local ARRIVAL: number = 2 -- Ticks after its fire the bullet's step reaches the NPC 72 studs off, its third
local CLOSE: number = 1e-6

-- A shot claiming a render tick, aimed from a point at another with its look packed as the dev table packs it
local function shot(from: any, to: any, renderTick: number, steps: number): { [string]: number }
	local direction: any = (to - from).Unit

	return {
		sequence = 1,
		class = 0,
		renderTick = renderTick,
		fraction = 0,
		yaw = math.round(math.atan2(-direction.X, -direction.Z) / TURN * steps) % steps,
		pitch = math.round(math.asin(direction.Y) / TURN * steps),
	}
end

-- Fires one command's Move from the shooter's client with these game fields, carried across before the next tick
local function send(rig: Rig.Rig, client: any, number: number, fields: { [string]: any })
	local Command: any = rig:require(rig.tread.Codec.Command)
	local Fields: any = rig:require(rig.tread.Codec.Fields)
	local Move: any = rig:require(rig.tread.Codec.Move)

	local command: any = Command.new()
	command.number = number
	command.fields = fields

	local move: any = Move.new()
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	Move.encode(move, { command }, 1, 0, 0, DELAY, Fields.compile(rig.shared.fields), limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()
end

-- The middle of a sample's chest capsule
local function chestOf(sample: any): any
	return (sample.zones.chest.from + sample.zones.chest.to) / 2
end

-- How far a point lies from a line through an origin along a unit direction
local function offLine(point: any, origin: any, direction: any): number
	local relative: any = point - origin

	return (relative - direction * relative:Dot(direction)).Magnitude
end

return function (): (boolean, string | nil)
	local dev: DevServer.Loaded = DevServer.load()
	local Shots: any = dev.require(dev.game:GetService("ServerScriptService").Server.Fixtures.Shots)

	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.beforeCommand = Shots.queue
	end)

	local server: any = rig:start()
	Shots.start(server, rig.shared, rig.settings)

	local steps: number = rig:require(rig.tread.Constants).ANGLE_STEPS
	local radius: number = rig.shared.hitShapes.Stand.zones.chest.radius

	local client: any = rig:require(rig.tread.Network.Client)
	client.flush()
	rig:deliver()

	-- The shooter across the floor from the NPC, which sprints along -Z through the line
	local shooter: any = server:create(rig.mock.players[1], rig:at(-36, 7))
	local npc: any = server:createNpc(rig:at(36, 14))
	rig:tick(SETTLE)

	npc:command({
		number = 0,
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = true,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = { slot = 0, shots = {} },
	})

	rig:tick(SPRINT)
	rig:deliver()

	-- Aimed where the NPC's chest stood at the render time of the step that reaches it
	local fired: number = SETTLE + SPRINT + 1
	local arrival: number = fired + ARRIVAL
	local eye: any = shooter:getState().eye
	local aim: any = chestOf(server:sampleAt(npc, arrival - REWOUND))
	local atFire: any = chestOf(server:sampleAt(npc, fired - REWOUND))

	send(rig, client, fired, { slot = BOW, shots = { shot(eye, aim, fired - REWOUND, steps) } })
	rig:tick(ARRIVAL + 1)

	local results: { any } = Shots.results()
	local result: any = results[1]
	if #results ~= 1 then
		return false, `{#results} shots resolved by the arrival's tick, not the one fired`
	end

	local struck: any = result.strike
	if not struck or struck.target ~= npc then
		return false, `The bullet ended on tick {result.tick} for {result.reason}, striking nothing`
	elseif result.tick ~= arrival or math.abs(result.offset - REWOUND) > CLOSE then
		return false, `It struck on tick {result.tick}, {result.offset} relay ticks behind, not {arrival} and {REWOUND}`
	elseif math.abs(result.renderTime - (fired - REWOUND)) > CLOSE or not result.inside then
		return false, `It was rewound to {result.renderTime}, inside the band {result.inside}, not {fired - REWOUND}`
	end

	-- The case has power only if the NPC stood clear of the line both at the fire's render time and at the present
	local atPresent: any = chestOf(server:sampleAt(npc, arrival))
	local fireMiss: number = offLine(atFire, result.origin, result.direction)
	local presentMiss: number = offLine(atPresent, result.origin, result.direction)

	if fireMiss <= radius or presentMiss <= radius then
		local apart: string = `{fireMiss} studs off the line at the fire's time and {presentMiss} at the present`
		return false, `The NPC's chest stood {apart}, inside its {radius}-stud radius, so the case proves nothing`
	end

	return true, nil
end
