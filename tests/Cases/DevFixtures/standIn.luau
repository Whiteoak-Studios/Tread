--[[
    A shot whose command arrives after its tick ran a stand-in does nothing:
    the stand-in fires no shot, the late command is dropped and reported as
    lateShot, and the same shot sent on time strikes the target
--]]

--!strict
local DevServer = require("../../Fixtures/DevServer/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local TURN: number = 2 * math.pi
local DELAY: number = 150 -- Milliseconds of interpolation delay the shooter's Move reports, the rewind's least
local REWOUND: number = 5 -- Relay ticks a command's expected render time lies behind it: the 0.1 s round trip and the delay
local SETTLE: number = 30 -- Ticks for both bodies to land and the shooter's eye to settle
local AFTER: number = 6 -- Ticks run after the late Move, past the AKM's whole flight
local AKM: number = 1 -- The fixture weapon's hotbar slot

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

return function (): (boolean, string | nil)
	local dev: DevServer.Loaded = DevServer.load()
	local Shots: any = dev.require(dev.game:GetService("ServerScriptService").Server.Fixtures.Shots)

	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.beforeCommand = Shots.queue
	end)

	local server: any = rig:start()
	Shots.start(server, rig.shared, rig.settings)

	local steps: number = rig:require(rig.tread.Constants).ANGLE_STEPS
	local chest: any = rig.shared.hitShapes.Stand.zones.chest

	local client: any = rig:require(rig.tread.Network.Client)
	client.flush()
	rig:deliver()

	local player: any = rig.mock.players[1]
	local shooter: any = server:create(player, rig:at(-20, 25))
	local target: any = server:create(rig.mock:addBot("Target"), rig:at(-20, -5))

	rig:tick(SETTLE)

	local eye: any = shooter:getState().eye
	local aim: any = target:getState().root + (chest.from + chest.to) / 2

	-- The shot's tick runs with a stand-in for the Move held back, which then arrives
	local late: number = SETTLE + 1
	rig:tick(1)
	rig:deliver()

	send(rig, client, late, { slot = AKM, shots = { shot(eye, aim, late - REWOUND, steps) } })
	rig:tick(AFTER)

	local dropped: { any } = rig:reportedFor("lateShot", player)
	if #Shots.results() ~= 0 or #Shots.hits(target) ~= 0 then
		return false, `The late shot resolved {#Shots.results()} times, striking the target {#Shots.hits(target)}`
	elseif #dropped ~= 1 or dropped[1].measurement ~= 1 then
		return false, `The late command gave {#dropped} lateShot reports, so its shot never reached the server`
	end

	-- The same shot on time, which the setup must let strike for the case above to mean anything
	local onTime: number = late + AFTER + 1
	send(rig, client, onTime, { slot = AKM, shots = { shot(eye, aim, onTime - REWOUND, steps) } })
	rig:tick(1)

	if #Shots.hits(target) ~= 1 then
		return false, `The shot sent on time struck the target {#Shots.hits(target)} times, not once`
	end

	return true, nil
end
