--[[
    client:play refuses, naming each and changing nothing, a second clip, a
    first buffer that isn't a keyframe, another CODEC_VERSION or
    declarations hash, frames before the keyframe or out of order, and a
    withheld frame with an OwnerState or a reveal; render refuses a time
    that isn't finite and clamps one past either end; destroy runs once
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 1100
local FRAMES: number = 10
local WALKER: number = 8
local TARGET: number = 9
local GENERATION: number = 1
local OTHER_VERSION: number = 2
local OTHER_HASH: number = 1234567
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)

	local function walker(tick: number): { [string]: any }
		return { slot = WALKER, generation = GENERATION, position = vector.create(tick - K, 0, 0) }
	end

	local function frame(tick: number): buffer
		return clip.frame({
			tick = tick,
			blocks = { { tick = tick, records = { walker(tick) } } },
			owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
		})
	end

	local keyframe: buffer = clip.keyframe({
		tick = K,
		characters = { { slot = WALKER, generation = GENERATION, kind = "Player", record = walker(K) } },
	})

	local ticks: { buffer } = { keyframe }
	for index: number = 0, FRAMES - 1 do
		table.insert(ticks, frame(K + index))
	end

	-- A withheld frame carrying an OwnerState, and one carrying a reveal
	local owned: buffer = frame(K)
	local revealing: buffer = clip.frame({
		tick = K,
		blocks = { { tick = K, reveals = { { slot = WALKER, generation = GENERATION, kind = "Player" } } } },
	})

	local refusals: { { name: string, ticks: { buffer }, withheld: { buffer }?, says: string } } = {
		{ name = "a first buffer that isn't a keyframe", ticks = { frame(K) }, says = "isn't a keyframe" },
		{
			name = "another CODEC_VERSION",
			ticks = { clip.keyframe({ tick = K, version = OTHER_VERSION }), frame(K) },
			says = "CODEC_VERSION",
		},
		{
			name = "another declarations hash",
			ticks = { clip.keyframe({ tick = K, hash = OTHER_HASH }), frame(K) },
			says = "hashing to",
		},
		{ name = "a frame before the keyframe", ticks = { keyframe, frame(K - 3) }, says = "before the keyframe" },
		{ name = "frames out of order", ticks = { keyframe, frame(K + 2), frame(K + 1) }, says = "out of order" },
		{ name = "a withheld frame with an OwnerState", ticks = ticks, withheld = { owned }, says = "OwnerState" },
		{ name = "a withheld frame with a reveal", ticks = ticks, withheld = { revealing }, says = "reveal" },
	}

	-- 1) Each refusal errors by name and leaves the pool untouched
	for _, refusal in refusals do
		local calls: number = #pool.calls
		local played: boolean, problem: any = pcall(handle.play, handle, refusal.ticks, refusal.withheld)

		if played then
			return false, `client:play took {refusal.name}`
		elseif not string.find(tostring(problem), "client:play", 1, true) then
			return false, `client:play refused {refusal.name} without naming itself: {problem}`
		elseif not string.find(tostring(problem), refusal.says, 1, true) then
			return false, `client:play refused {refusal.name} as "{problem}"`
		elseif #pool.calls ~= calls or handle._playback ~= nil then
			return false, `client:play changed the client when it refused {refusal.name}`
		end
	end

	-- 2) A second clip is refused while one plays
	local playback: any = handle:play(ticks)
	local again: boolean, twice: any = pcall(handle.play, handle, ticks)
	if again or not string.find(tostring(twice), "one clip at a time", 1, true) then
		return false, `client:play took a second clip, or refused it as "{twice}"`
	end

	-- 3) A time past either end draws that end, and one that isn't finite is refused
	local function walkerAt(time: number): vector?
		local count: number = #log.poses
		playback:render(time)

		local drawn: any = log.since(count)[WALKER]
		return drawn and drawn.position
	end

	local relay: number = rig.shared.rates.relay
	local last: number = (FRAMES - 1) / relay
	local edges: { { number } } = { { -5, 0 }, { 1e6, last } }
	for _, pair: { number } in edges do
		local clamped: vector? = walkerAt(pair[1])
		local edge: vector? = walkerAt(pair[2])
		if clamped == nil or edge == nil or vector.magnitude(clamped - edge) > CLOSE then
			return false, `A render at {pair[1]} s drew {clamped}, not the end's {edge}`
		end
	end

	for _, time: number in { 0 / 0, math.huge, -math.huge } do
		local rendered: boolean, problem: any = pcall(playback.render, playback, time)
		if rendered or not string.find(tostring(problem), "finite", 1, true) then
			return false, `playback:render took {time}, or refused it as "{problem}"`
		end
	end

	-- 4) Destroy runs once, and nothing renders after it
	playback:destroy()
	local destroyed: boolean = pcall(playback.destroy, playback)
	local rendered: boolean = pcall(playback.render, playback, 0)
	if destroyed or rendered then
		return false, `After the end a second destroy ran {destroyed} and a render ran {rendered}`
	end

	return true, nil
end
