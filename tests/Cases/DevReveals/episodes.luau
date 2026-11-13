--[[
    A scripted run of one pair's reveals, hides and sightings counts its
    late reveals once a stretch under each reading, with the grace, and a
    repeated pending hide never starts its unsent stretch again
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local SLOT: number = 7
local GENERATION: number = 1
local DISTANCE: number = 10 -- Studs, plus the tick, so each episode's distance names the tick it was read on

-- One relay tick: what its blocks carried for the pair, and whether the exact test found the target visible
type Tick = { entry: string?, visible: boolean }

local SCRIPT: { Tick } = {
	{ entry = "reveal", visible = true }, -- 1: sent
	{ entry = "hide", visible = false }, -- 2: unsent from here
	{ entry = "hide", visible = false }, -- 3: the pending hide again
	{ entry = "hide", visible = true }, -- 4: strict opens, its stretch 2 ticks old; lenient's run starts
	{ entry = nil, visible = true }, -- 5: lenient's run passes the grace; strict goes on
	{ entry = nil, visible = false }, -- 6: both runs end
	{ entry = "hide", visible = true }, -- 7: strict opens again, the stretch still from 2; lenient's run starts
	{ entry = "reveal", visible = true }, -- 8: sent, so lenient's run of 1 never counts
	{ entry = "hide", visible = true }, -- 9: unsent from here, inside the grace for strict; lenient's run starts
	{ entry = nil, visible = false }, -- 10: its run of 1 ends
	{ entry = "hide", visible = true }, -- 11: strict opens, the stretch 2 ticks old
	{ entry = "reveal", visible = true }, -- 12: sent
	{ entry = "reveal", visible = true }, -- 13: the pending reveal again
}

-- The known answer: each reading's episodes in the order they opened, as start and length
local LENIENT: { { number } } = { { 4, 2 } }
local STRICT: { { number } } = { { 4, 2 }, { 7, 1 }, { 11, 1 } }

-- A decoded tap frame carrying one entry for the pair, or none
local function frameOf(entry: string?): { [string]: any }
	local reveals: { any } = {}
	local hides: { any } = {}

	if entry == "reveal" then
		table.insert(reveals, { slot = SLOT, generation = GENERATION, kind = "Player" })
	elseif entry == "hide" then
		table.insert(hides, { slot = SLOT, generation = GENERATION })
	end

	return { blocks = { { reveals = reveals, hides = hides, records = {} } } }
end

-- Why a reading's episodes differ from what they should be, or nil when they match
local function mismatch(reading: string, found: { any }, expected: { { number } }): string?
	local episodes: { any } = {}
	for _, episode: any in found do
		if episode.reading == reading then
			table.insert(episodes, episode)
		end
	end

	if #episodes ~= #expected then
		return `The run counted {#episodes} {reading} episodes, not {#expected}`
	end

	for index: number, want: { number } in expected do
		local episode: any = episodes[index]
		if episode.start ~= want[1] or episode.length ~= want[2] then
			return `{reading} episode {index} ran from {episode.start} for {episode.length}, not {want[1]} for {want[2]}`
		elseif episode.distance ~= DISTANCE + want[1] or episode.reason ~= `R{want[1]}` then
			return `{reading} episode {index} kept the distance and reason of tick {episode.distance - DISTANCE}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local Reveals: any = loaded.require(server.Reveals)
	local grace: number = loaded.require(server.Config.Reveals).grace

	local held: { [number]: number } = {}
	local pair: any = Reveals.pair()
	local found: { any } = {}
	local seen: any = Reveals.sighting("body")

	for tick: number, step: Tick in SCRIPT do
		Reveals.apply(held, frameOf(step.entry))

		seen.tick = tick
		seen.sent = held[SLOT] == GENERATION
		seen.visible = step.visible
		seen.distance = DISTANCE + tick
		seen.reason = `R{tick}`

		Reveals.track(pair, seen, grace, found, "Viewer", "Target", false)
	end

	local failure: string? = mismatch("lenient", found, LENIENT) or mismatch("strict", found, STRICT)
	if failure then
		return false, failure
	elseif found[1].viewer ~= "Viewer" or found[1].target ~= "Target" or found[1].real ~= false then
		return false, "An episode did not keep its viewer, target and whether the viewer is real"
	elseif found[1].set ~= "body" then
		return false, `An episode of the body set's sighting kept the set {found[1].set}`
	end

	-- A hide of another life leaves the stretch of the life held
	Reveals.apply(held, frameOf("reveal"))
	Reveals.apply(held, { blocks = { { reveals = {}, hides = { { slot = SLOT, generation = GENERATION + 1 } } } } })
	if held[SLOT] ~= GENERATION then
		return false, "A hide of another life ended the held life's stretch"
	end

	return true, nil
end
