--[[
    A platform's calls reach prediction's world: one added before its first
    call takes each call as it comes, one called before it is added takes
    the calls heard at its add, the latest two as the step keeps them, and
    so does one added again; a repeat changes nothing, and a client the
    handshake refused takes no call
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local EARLY: number = 3 -- Added before its first call
local LATE: number = 4 -- Called before it is added
local SPARE: number = 5 -- Added to a client the handshake refused

-- Why a platform's calls in prediction's world aren't the two given, or nil when they are
local function calls(world: any, id: number, latest: number?, before: number?): string?
	local entry: any = world.platforms[id]
	if entry == nil then
		return `Platform {id} isn't registered in prediction's world`
	elseif entry.calledAt ~= latest or entry.calledBefore ~= before then
		local held: string = `called at {entry.calledAt} and before at {entry.calledBefore}`
		return `Platform {id} was {held}, where {latest} and {before} were expected`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local function lift(id: number): any
		return Riders.lift(id, roblox.Vector3.new(id * 20, 1200, 0), 0, 0)
	end

	local rig: any = Handle.new()
	local handle: any = rig.handle
	local world: any = handle._world

	-- 1) Calls heard before the handshake and before the platform is added wait for its add
	rig.send("Platform", LATE, 2000)
	rig.send("Platform", LATE, 2005)
	rig.send("Platform", LATE, 1990)
	if world.platforms[LATE] ~= nil then
		return false, "A call for a platform never added registered one"
	end

	rig.handshake()

	-- 2) One added first takes each call as it comes, a repeat changing nothing
	handle:addPlatform(lift(EARLY))
	local problem: string? = calls(world, EARLY, nil, nil)
	if problem then
		return false, `Before any call: {problem}`
	end

	rig.send("Platform", EARLY, 1000)
	problem = calls(world, EARLY, 1000, nil)
	if problem then
		return false, `After its first call: {problem}`
	end

	rig.send("Platform", EARLY, 1010)
	rig.send("Platform", EARLY, 1010)
	problem = calls(world, EARLY, 1010, 1000)
	if problem then
		return false, `After its second call and a repeat: {problem}`
	end

	-- 3) One called before its add takes the latest two of the calls heard, as the server keeps them
	local remove: () -> () = handle:addPlatform(lift(LATE))
	problem = calls(world, LATE, 2005, 2000)
	if problem then
		return false, `At its add after three calls: {problem}`
	end

	-- 4) Taken out, called while out and added again, it takes every call heard
	remove()
	rig.send("Platform", LATE, 2020)
	if world.platforms[LATE] ~= nil then
		return false, "Taking the platform out left it registered"
	end

	handle:addPlatform(lift(LATE))
	problem = calls(world, LATE, 2020, 2005)
	if problem then
		return false, `Added again after a call while out: {problem}`
	end

	-- 5) A client the handshake refused takes no call
	local refused: any = Handle.new()
	refused.handshake(1)
	refused.handle:addPlatform(lift(SPARE))
	refused.send("Platform", SPARE, 3000)

	problem = calls(refused.handle._world, SPARE, nil, nil)
	if problem then
		return false, `On a refused client: {problem}`
	end

	return true, nil
end
