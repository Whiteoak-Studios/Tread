--[[
    Over Volt.mock a bot and a player each send the same commands, the
    player through its client's remote and the bot through its own client
    side of the scope, and each tick both bodies end in the same state
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/DevBot/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local PLAYER_X: number = -28 -- Where each body is built, clear of the fixture's obstacles and in one float binade
local BOT_X: number = -20
local START_Z: number = 10
local TICKS: number = 120
local SETTLED: number = 4 -- Ticks after which neither body may run a stand-in, both clients' commands arriving
local MOVED: number = 4 -- Studs the bodies must cover, so the states compared are of moving bodies
local SEED: number = 1
local FLAGS: { string } = { "moveTamper", "rate", "schema", "ahead", "late" } -- Neither honest client may raise one

-- The command stream both send, from the tick alone: forward and back, a sideways drift, a sway, jumps and crouches
local LEG: number = 40 -- Ticks of one forward leg and its way back
local SPRINTING: number = 10 -- Ticks of each leg's start spent sprinting
local DRIFT_LEG: number = 16
local DRIFT: number = 0.25
local JUMP_EVERY: number = 30
local CROUCH_LEG: number = 50
local CROUCHING: number = 10 -- Ticks at each crouch leg's end spent crouched
local SWAY: number = 0.2 -- Radians the look sways either way
local SWAY_TICKS: number = 10 -- Ticks a radian of the sway's phase takes
local FORWARD: number = math.sqrt(1 - DRIFT * DRIFT) -- So the move's length stays 1, as a client's sample keeps it

-- The run's ticks come faster than real time, so the Move's rate is raised past what they send in a real second
local MOVES_A_SECOND: number = 10000

local function steer(command: any, tick: number, _: vector)
	local phase: number = tick % LEG

	command.forward = phase < LEG / 2 and FORWARD or -FORWARD
	command.right = tick % DRIFT_LEG < DRIFT_LEG / 2 and DRIFT or -DRIFT
	command.sprint = phase < SPRINTING
	command.jump = tick % JUMP_EVERY == 0
	command.crouch = tick % CROUCH_LEG >= CROUCH_LEG - CROUCHING
	command.yaw = SWAY * math.sin(tick / SWAY_TICKS)
end

-- The first way two states differ, the bot's moved by the offset, or nil when none does
local function differs(mine: any, theirs: any, offset: number): string?
	local root: any = theirs.root - mine.root

	if root.X ~= offset or root.Y ~= 0 or root.Z ~= 0 then
		return `roots {mine.root} and {theirs.root} differ by {root}`
	elseif theirs.velocity ~= mine.velocity then
		return `velocities {mine.velocity} and {theirs.velocity}`
	elseif theirs.facing ~= mine.facing or theirs.apex ~= mine.apex then
		return `facings {mine.facing} and {theirs.facing}, apexes {mine.apex} and {theirs.apex}`
	elseif theirs.grounded ~= mine.grounded or theirs.mode ~= mine.mode or theirs.posture ~= mine.posture then
		return `{mine.mode} {mine.posture} and {theirs.mode} {theirs.posture}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.rates.move = { perSecond = MOVES_A_SECOND, burst = MOVES_A_SECOND }
	end)

	local server: any = rig:start()
	local harness: Harness.Loaded = Harness.load()
	local Bot: any = harness.Bot
	local context: any = Bot.context(rig.shared, harness.Config.delay, harness.Config.fields)

	-- The player's client side joins the mock as its player, and the bot's is the generated module on its transport
	local playerNetwork: any = rig:require(rig.tread.Network.Client)
	local player: any = rig.mock.players[1]
	local volt: any = rig.mock:addBot("Bot")
	local transport: any = rig.mock:connectBot(volt)
	local botNetwork: any = Environment.load(CLIENT, {
		[VOLT] = {
			start = function (schema: any): any
				return Volt.start(schema, transport)
			end,
		},
	})

	local playerBot: any = Bot.new(playerNetwork, context, steer, nil, SEED)
	local botBot: any = Bot.new(botNetwork, context, steer, nil, SEED)
	local playerCharacter: any = server:create(player, rig:at(PLAYER_X, START_Z))
	local botCharacter: any = server:create(volt, rig:at(BOT_X, START_Z))

	server:addStage("bots", "relay", function (tick: number)
		playerBot:tick(tick)
		botBot:tick(tick)
	end)

	-- Both handshakes in before the first tick
	rig:deliver()

	local start: any = playerCharacter:getState().root
	local covered: number = 0 -- The farthest the player's body got from where it was built
	local standIns: { [any]: number } = {}

	for tick: number = 1, TICKS do
		rig:tick(1)
		rig:deliver()

		local mine: any = playerCharacter:getState()
		local difference: string? = differs(mine, botCharacter:getState(), BOT_X - PLAYER_X)
		if difference then
			return false, `After tick {tick} the bodies differ: {difference}`
		end

		covered = math.max(covered, (mine.root - start).Magnitude)

		if tick == SETTLED then
			standIns[player] = #rig:reportedFor("standIn", player)
			standIns[volt] = #rig:reportedFor("standIn", volt)
		end
	end

	local playerLater: number = #rig:reportedFor("standIn", player) - standIns[player]
	local botLater: number = #rig:reportedFor("standIn", volt) - standIns[volt]

	if playerLater > 0 or botLater > 0 then
		local counts: string = `the player's ran {playerLater} and the bot's {botLater}`
		return false, `Past the first {SETTLED} ticks {counts} stand-ins, so a client's commands went missing`
	elseif covered < MOVED then
		return false, `The bodies got {covered} studs out, too little for the states compared to show their commands`
	elseif botBot:measure().heard == 0 or playerBot:measure().heard == 0 then
		return false, "A client side never heard its OwnerState"
	end

	for _, kind: string in FLAGS do
		local raised: number = #rig:reportedFor(kind, player) + #rig:reportedFor(kind, volt)
		if raised > 0 then
			return false, `The honest command stream raised {raised} {kind} reports`
		end
	end

	playerBot:destroy()
	botBot:destroy()

	return true, nil
end
