--[[
    What the harness holds for a viewer, rebuilt from its tap's reveals and
    hides and seeded from its keyframe, is what the relay holds on every
    tick, while a still target is hidden by a wall and sent again
--]]

--!strict
local task = require("@lune/task")

local DevServer = require("../../Fixtures/DevServer/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 30 -- Ticks for the target's reveal to be acknowledged and its records to go still
local WALL_SIZE: vector = vector.create(1, 40, 40) -- Tall and wide enough to block every ray across it
local POLL: number = 0.05 -- Real seconds between ticks while anti-ESP's clock runs toward a change
local DEADLINE: number = 5 -- Real seconds a change may take before the case fails
local DELAY: number = 150 -- Milliseconds of interpolation delay the viewer's Moves report

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Relay: any = rig:require(rig.tread.Server.Relay)
	local Fields: any = rig:require(rig.tread.Codec.Fields)
	local Move: any = rig:require(rig.tread.Codec.Move)

	local dev: DevServer.Loaded = DevServer.load()
	local Reveals: any = dev.require(dev.game:GetService("ServerScriptService").Server.Reveals)
	local Tread: any = dev.require(dev.game:GetService("ReplicatedStorage").Packages.Tread)

	-- The viewer is a player whose client acknowledges each block, so a still target's records stop
	local client: any = rig:require(rig.tread.Network.Client)
	client.flush()
	rig:deliver()

	local viewer: any = rig.mock.players[1]
	server:create(viewer, rig:at(0, 0))
	local target: any = server:create(rig.mock:addBot("Target"), rig:at(6, 0))
	local slot: number, generation: number = target._slot, target._generation

	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }

	local function keyframe(): { [string]: any }
		return Tread.decode(Tread.CODEC_VERSION, "keyframe", server:keyframe(viewer))
	end

	local held: { [number]: number } = {}
	Reveals.seed(held, keyframe())

	local newest: number = 0 -- The newest block's sequence the viewer was sent
	local mismatch: string? = nil
	local sentTicks: number, unsentTicks: number = 0, 0
	local unrecorded: boolean = false -- A tick sent with no record for the target, where records alone would differ

	local stop: () -> () = server:observe(viewer, function (tick: number, data: buffer)
		local frame: { [string]: any } = Tread.decode(Tread.CODEC_VERSION, "tap", data)
		Reveals.apply(held, frame)

		local recorded: boolean = false
		for _, block: any in frame.blocks do
			newest = block.sequence

			for _, record: any in block.records do
				recorded = recorded or record.slot == slot
			end
		end

		local sent: boolean = Relay.isSent(viewer, slot)
		if mismatch == nil and (held[slot] == generation) ~= sent then
			mismatch = `On tick {tick} the relay held the target {sent} and the harness {held[slot] == generation}`
		end

		if sent then
			sentTicks += 1
			unrecorded = unrecorded or not recorded
		else
			unsentTicks += 1
		end
	end)

	-- Runs ticks, the viewer acknowledging the newest block it was sent after each
	local function run(count: number)
		for _ = 1, count do
			rig:tick(1)

			local move: any = Move.new()
			Move.encode(move, {}, 0, newest, 0, DELAY, layout, limits)
			client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
			client.flush()
			rig:deliver()
		end
	end

	-- Ticks until the relay's hold of the target is as wanted, anti-ESP's clock running in real time
	local function waitFor(wanted: boolean): boolean
		local deadline: number = os.clock() + DEADLINE
		while Relay.isSent(viewer, slot) ~= wanted do
			if os.clock() >= deadline then
				return false
			end

			task.wait(POLL)
			run(1)
		end

		return true
	end

	run(SETTLE)

	-- Seeded from a keyframe mid-run, a new hold starts as the relay's stands
	local late: { [number]: number } = {}
	Reveals.seed(late, keyframe())
	if late[slot] ~= generation or not Relay.isSent(viewer, slot) then
		return false, "A hold seeded from the keyframe while the target was sent did not hold it"
	end

	local removeWall: () -> () = rig:wall(vector.create(3, rig.floor + WALL_SIZE.y / 4, 0), WALL_SIZE)
	if not waitFor(false) then
		return false, `The wall never hid the target within {DEADLINE} s`
	end

	run(SETTLE)
	Reveals.seed(late, keyframe())
	if late[slot] ~= nil then
		return false, "A hold seeded from the keyframe while the target was hidden held it"
	end

	removeWall()
	if not waitFor(true) then
		return false, `With the wall gone the target was not sent again within {DEADLINE} s`
	end

	run(SETTLE)
	stop()

	if mismatch then
		return false, mismatch
	elseif sentTicks == 0 or unsentTicks == 0 then
		return false, `The run saw {sentTicks} ticks sent and {unsentTicks} unsent, not both`
	elseif not unrecorded then
		return false, "Every sent tick carried the target's record, so records alone would have matched"
	end

	return true, nil
end
