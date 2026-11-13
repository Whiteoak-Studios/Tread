--[[
    A fixture shot leaves the shooter's cleared eye at the render time its
    command rewinds to and strikes the nearer of two targets standing in its
    line, never one beside it, and a shot aimed beside them flies its range
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevServer = require("../../Fixtures/DevServer/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local TURN: number = 2 * math.pi
local DELAY: number = 150 -- Milliseconds of interpolation delay the shooter's Move reports, the rewind's least
local REWOUND: number = 5 -- Relay ticks a command's expected render time lies behind it: the 0.1 s round trip and the delay
local SETTLE: number = 30 -- Ticks for every body to land and the shooter's eye to settle
local AKM: number = 1 -- The fixture weapon's hotbar slot
local RANGE_TICKS: number = 5 -- The AKM's 750 studs at 150.15 a tick
local SIDE: number = 3 -- Studs the missing shot is aimed beside the target, clear of every capsule
local CLOSE: number = 1e-6

-- A shot claiming a render tick, aimed from a point at another with its look packed as the dev table packs it
local function shot(sequence: number, from: any, to: any, renderTick: number, steps: number): { [string]: number }
	local direction: any = (to - from).Unit

	return {
		sequence = sequence,
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
	local center: any = (chest.from + chest.to) / 2

	-- The shooter's client joins the mock as its player; the targets are bots standing on stand-ins
	local client: any = rig:require(rig.tread.Network.Client)
	client.flush()
	rig:deliver()

	-- The far target takes the lower slot, so the test meets it first and must still strike the nearer
	local shooter: any = server:create(rig.mock.players[1], rig:at(-20, 25))
	local far: any = server:create(rig.mock:addBot("Far"), rig:at(-20, -15))
	local near: any = server:create(rig.mock:addBot("Near"), rig:at(-20, -5))
	local beside: any = server:create(rig.mock:addBot("Beside"), rig:at(-17, 5))

	rig:tick(SETTLE)
	rig:deliver()

	local fired: number = SETTLE + 1
	local eye: any = shooter:getState().eye
	local aim: any = near:getState().root + center
	local wide: any = aim - roblox.Vector3.new(SIDE, 0, 0)

	send(rig, client, fired, {
		slot = AKM,
		shots = { shot(1, eye, aim, fired - REWOUND, steps), shot(2, eye, wide, fired - REWOUND, steps) },
	})

	rig:tick(RANGE_TICKS)

	local results: { any } = Shots.results()
	if #results ~= 2 then
		return false, `{#results} of the two shots resolved`
	end

	local hit: any = results[1].sequence == 1 and results[1] or results[2]
	local miss: any = results[1].sequence == 2 and results[1] or results[2]

	local struck: any = hit.strike
	if not struck or struck.target ~= near or struck.zone ~= "chest" then
		local what: string = struck and `{struck.zone} of {struck.target.player.Name}` or `nothing, {hit.reason}`
		return false, `The shot at the near target's chest struck {what}`
	elseif hit.fired ~= fired or hit.tick ~= fired or hit.command ~= fired then
		return false,
			`The hit was fired on {hit.fired} in command {hit.command} and struck on {hit.tick}, not all {fired}`
	elseif math.abs(hit.renderTime - (fired - REWOUND)) > CLOSE or not hit.inside then
		return false, `The hit was rewound to {hit.renderTime}, inside the band {hit.inside}, not {fired - REWOUND}`
	elseif math.abs(hit.offset - REWOUND) > CLOSE then
		return false, `The hit flew {hit.offset} relay ticks behind its fire, not {REWOUND}`
	elseif (hit.origin - eye).Magnitude > CLOSE then
		return false, `The hit left {hit.origin}, not the shooter's cleared eye at {eye}`
	end

	if miss.strike or miss.reason ~= "range" or miss.tick ~= fired + RANGE_TICKS - 1 then
		return false, `The wide shot ended on tick {miss.tick} for {miss.reason}, not at the end of its range`
	elseif #Shots.hits(near) ~= 1 or #Shots.hits(far) ~= 0 or #Shots.hits(beside) ~= 0 then
		return false, `The targets took {#Shots.hits(near)}, {#Shots.hits(far)} and {#Shots.hits(beside)} hits`
	end

	return true, nil
end
