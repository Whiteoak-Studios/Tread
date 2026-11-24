--[[
    With no cap key the start sets no cap, the five cap fields of stats read
    0 each tick, and each tick's bytes out and the bots' tap frames hold the
    values this load gives with every cap off
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 8
local FIELDS: { string } = { "antiEspCut", "npcsWaited", "relayLeft", "relayOver", "farHalved" }

-- Each bot's x and z, clear of the fixture's obstacles, and each NPC's, walking along -Z
local BOTS: { { number } } = {
	{ -24, -6 },
	{ -18, -6 },
	{ -12, -6 },
	{ -6, -6 },
	{ -24, 6 },
	{ -18, 6 },
	{ -12, 6 },
	{ -6, 6 },
}
local NPCS: { { number } } = { { 2, -12 }, { 2, 0 }, { 2, 12 } }

-- Each tick's bytes out and the digest of the bots' tap frames, measured from a run of this load with every cap off
local BYTES: { number } = { 1024, 2312, 2312, 2312, 2312, 2312, 2312, 2312 }
local DIGESTS: { number } = {
	2741917612,
	1332849378,
	2145591313,
	415932788,
	479943523,
	471198982,
	539057932,
	1342521553,
}

-- A command walking forward along -Z with nothing pressed
local function walking(): any
	return {
		forward = 1,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = { slot = 0, shots = {} },
	}
end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local settings: any = rig.settings
	local relay: any = settings.relay
	if settings.npcs.budget ~= nil or settings.antiEsp.whole ~= nil or settings.tiers.underLoad ~= nil then
		return false, "The example's server settings give a cap key, so this case tests nothing"
	elseif relay ~= nil and relay.budget ~= nil then
		return false, "The example's server settings give relay.budget, so this case tests nothing"
	end

	local server: any = rig:start()
	local tread: any = rig.tread
	local AntiEsp: any = rig:require(tread.Server.AntiEsp)
	local Hash: any = rig:require(tread.Codec.Hash)
	local Npcs: any = rig:require(tread.Server.Npcs)
	local Relay: any = rig:require(tread.Server.Relay)

	if Npcs.budget() ~= nil or Relay.budget() ~= nil or Relay.underLoad() ~= nil or AntiEsp.wholeOn() then
		local relaySet: string = `relay budget {Relay.budget()}, far rate under load {Relay.underLoad()}`
		return false,
			`With no cap key the start set the NPC budget {Npcs.budget()}, {relaySet}, whole {AntiEsp.wholeOn()}`
	end

	-- Each frame's digest with its bot's place in BOTS, by the relay tick, sorted as the sinks may run in any order
	local heard: { [number]: { string } } = {}
	for index: number, at: { number } in BOTS do
		local bot: any = rig.mock:addBot(`Bot{index}`)
		server:create(bot, rig:at(at[1], at[2]))
		server:observe(bot, function (tick: number, data: buffer)
			local frames: { string } = heard[tick] or {}
			heard[tick] = frames
			table.insert(frames, `{index}:{Hash.range(data, 0, buffer.len(data))}`)
		end)
	end

	for _, at: { number } in NPCS do
		server:createNpc(rig:at(at[1], at[2])):command(walking())
	end

	server:stats()

	for tick: number = 1, TICKS do
		rig:tick(1)
		local read: any = server:stats()

		for _, name: string in FIELDS do
			if read[name] ~= 0 then
				return false, `With no cap key tick {tick}'s read gave {name} {read[name]}, not 0`
			end
		end

		local frames: { string } = heard[tick] or {}
		table.sort(frames)
		local digest: number = Hash.text(table.concat(frames, ","))

		if read.ticks ~= 1 or read.bytesOut ~= BYTES[tick] then
			return false, `Tick {tick} ran {read.ticks} ticks and sent {read.bytesOut} B, not 1 and {BYTES[tick]} B`
		elseif #frames ~= #BOTS or digest ~= DIGESTS[tick] then
			return false, `Tick {tick}'s {#frames} tap frames gave the digest {digest}, not {DIGESTS[tick]}`
		end
	end

	return true, nil
end
