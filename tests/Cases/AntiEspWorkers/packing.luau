--[[
    A sleeper's LYING_RAYS rays and a player pair's PLAYER_RAYS are packed
    into one batch of a u32 count and then 73 and 145 bytes, each a u8 count
    and each ray's origin and direction as f32s, bit for bit as cast in process
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local CONSTANTS: string = "src/Constants.luau"
local HEADER_FORMAT: string = "<I4"
local COUNT_FORMAT: string = "<B"
local RAY_FORMAT: string = "<ffffff"
local PAIRS: number = 2
local LYING_BYTES: number = 73 -- The design's sleeper pair: a count and 3 rays of 24 B
local PLAYER_BYTES: number = 145 -- And its player pair: a count and 6 rays

-- The harness after one slice of one scene, in process or packed for one worker, and its pool
local function scene(workers: number?): (any, any)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = workers
	end)

	harness.wall = Harness.solid

	local pool: any = override.made
	if pool then
		pool.wall = Harness.solid
	end

	-- Moving, so the moved eye and the pushed sides differ from the plain rays
	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	harness.states[slot].velocity = vector.create(4, 0, -2)

	local target: number = harness:body("Player", vector.create(10, 0, -50), 0.5)
	harness.states[target].velocity = vector.create(-6, 0, 3)
	local sleeper: number = harness:body("Sleeper", vector.create(30, 0, 5), 1.25)

	Harness.AntiEsp.isHidden(viewer, target)
	Harness.AntiEsp.isHidden(viewer, sleeper)
	harness:slice(0)

	return harness, pool
end

local function packRay(ray: any): string
	local origin: vector = ray.origin
	local direction: vector = ray.direction

	return string.pack(RAY_FORMAT, origin.x, origin.y, origin.z, direction.x, direction.y, direction.z)
end

return function (): (boolean, string | nil)
	local Constants: any = Environment.load(CONSTANTS)
	local playerRays: number = Constants.PLAYER_RAYS
	local lyingRays: number = Constants.LYING_RAYS

	local lyingBytes: number = string.packsize(COUNT_FORMAT) + lyingRays * string.packsize(RAY_FORMAT)
	local playerBytes: number = string.packsize(COUNT_FORMAT) + playerRays * string.packsize(RAY_FORMAT)
	if lyingBytes ~= LYING_BYTES or playerBytes ~= PLAYER_BYTES then
		return false, `A sleeper pair takes {lyingBytes} B and a player pair {playerBytes} B, not the design's`
	end

	local serial: any = scene(nil)
	local _, pool: any = scene(1)

	if #serial.rays ~= playerRays + lyingRays then
		return false, `In process {#serial.rays} rays were cast, not the player pair's and the sleeper's`
	elseif #pool.sends ~= 1 or pool.sends[1].pairs ~= PAIRS then
		return false, "The two pairs were not sent in one batch"
	end

	-- The sleepers' share comes first, so in process the sleeper is tested before the player pair, as packed
	local parts: { string } = { string.pack(HEADER_FORMAT, PAIRS), string.pack(COUNT_FORMAT, lyingRays) }
	for index: number, ray: any in serial.rays do
		if index == lyingRays + 1 then
			table.insert(parts, string.pack(COUNT_FORMAT, playerRays))
		end

		table.insert(parts, packRay(ray))
	end

	local expected: string = table.concat(parts)
	local batch: buffer = pool.sends[1].batch
	local size: number = string.packsize(HEADER_FORMAT) + LYING_BYTES + PLAYER_BYTES

	if buffer.len(batch) ~= size or #expected ~= size then
		return false, `The batch was {buffer.len(batch)} bytes, not {size}`
	elseif buffer.tostring(batch) ~= expected then
		return false, "The batch's bytes were not the rays cast in process, bit for bit"
	end

	return true, nil
end
