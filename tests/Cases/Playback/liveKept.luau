--[[
    While a playback runs the live client carries on unseen: play puts the
    live rigs away, a live reveal checks no rig out, a live footstep is
    never raised, the Moves still acknowledge each live block, and the end
    draws every live stretch still open again in its look
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 900
local OWN: number = 2
local SEEN: number = 20 -- Drawn live before the playback
local ARRIVED: number = 21 -- Revealed live while it runs
local TARGET: number = 9
local GENERATION: number = 1
local LIVE_TICK: number = 40 -- The live relay's first tick
local HEAD: number = 3 -- The live look, a slot-table field the example declares
local OTHER_HEAD: number = 4
local FRAMES: number = 3

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.slots({
		{ slot = SEEN, generation = GENERATION, rig = "A" },
		{ slot = ARRIVED, generation = GENERATION, rig = "A" },
	})
	rig.owner(rig.body(vector.zero, 0, LIVE_TICK))

	local heard: number = 0
	handle:onFootstep(function (_: any)
		heard += 1
	end)

	rig.relay({
		tick = LIVE_TICK,
		reveals = { { slot = SEEN, generation = GENERATION, kind = "Player" } },
		looks = { { slot = SEEN, generation = GENERATION, outfit = { head = HEAD } } },
		records = { { slot = SEEN, generation = GENERATION, position = vector.create(5, 0, 0) } },
	})
	rig.frames(FRAMES)

	if Clip.out(pool)[SEEN] == nil then
		return false, "The live character wasn't drawn before the playback"
	end

	local clip: any = Clip.new(rig)
	Clip.log(rig)
	local ticks: { buffer } = {
		clip.keyframe({ tick = K }),
		clip.frame({
			tick = K,
			owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, K), lag = 0 },
		}),
	}

	-- 1) Play puts every live rig away
	local playback: any = handle:play(ticks)
	local out: { [number]: any } = Clip.out(pool)
	if out[SEEN] ~= nil or out[OWN] ~= nil then
		return false, "A live rig stayed out once the playback began"
	end

	-- 2) A live reveal checks nothing out, a live footstep is silent, and the Moves acknowledge the live block
	local checkouts: number = #pool.of("checkout")
	rig.relay({
		tick = LIVE_TICK + 1,
		reveals = { { slot = ARRIVED, generation = GENERATION, kind = "Player" } },
		looks = { { slot = ARRIVED, generation = GENERATION, outfit = { head = OTHER_HEAD } } },
		records = {
			{ slot = SEEN, generation = GENERATION, position = vector.create(5, 0, 0) },
			{ slot = ARRIVED, generation = GENERATION, position = vector.create(6, 0, 0) },
		},
		footsteps = { { at = vector.create(1, 0, 0), kind = "Walk", material = roblox.Enum.Material.Grass } },
	})
	rig.frames(FRAMES)
	rig.step()
	playback:render(0)

	local liveCheckouts: number = 0
	for index: number = checkouts + 1, #pool.of("checkout") do
		local slot: number = pool.of("checkout")[index].slot
		if slot == SEEN or slot == ARRIVED or slot == OWN then
			liveCheckouts += 1
		end
	end

	local move: any = rig.moves[#rig.moves]
	if liveCheckouts > 0 then
		return false, `The live client checked {liveCheckouts} rigs out while the playback ran`
	elseif heard ~= 0 then
		return false, "A live footstep was raised while the playback ran"
	elseif move == nil or move.acknowledged ~= rig.sequence then
		return false, `The Moves acknowledged {move and move.acknowledged}, not the live block {rig.sequence}`
	end

	-- 3) The end draws both live stretches again, each in its own look
	playback:destroy()
	local drawn: { [number]: any } = {}
	for index: number = checkouts + 1, #pool.of("checkout") do
		local call: any = pool.of("checkout")[index]
		drawn[call.slot] = call.outfit
	end

	if drawn[SEEN] == nil or drawn[SEEN].head ~= HEAD then
		return false, "The character drawn live before the playback wasn't drawn again in its look at its end"
	elseif drawn[ARRIVED] == nil or drawn[ARRIVED].head ~= OTHER_HEAD then
		return false, "The character revealed live during the playback wasn't drawn in its look at its end"
	end

	return true, nil
end
