--[[
    Platforms.add refuses an id that is no whole number from 1 to 127 or is
    already held, no boxes, a box with no positive, finite size or center
    and a path that is no function, leaving the world as it was; call
    refuses an id no platform holds and a tick that is not whole, and at
    gives nil for an unknown id and refuses a tick that is not finite
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local PLATFORMS: string = "src/Step/Platforms.luau"
local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local function path(_: number, _: number?): any
	return roblox.Vector3.zero
end

-- A platform with one good box, with the change given made to a copy of it
local function platform(change: (made: { [string]: any }) -> ()): { [string]: any }
	local made: { [string]: any } = {
		id = 5,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.new(4, 1, 4) } },
		path = path,
	}

	change(made)

	return made
end

local function box(center: any, size: any): { [string]: any }
	return { boxes = { { center = center, size = size } } }
end

-- Each refused platform with the words its refusal must carry
local function refusals(): { { platform: any, words: string } }
	local list: { { platform: any, words: string } } = {
		{ platform = "a platform", words = "A platform must be a table" },
	}

	for _, id: any in { 0, 1.5, 128, -3, 0 / 0, math.huge, "1" } do
		table.insert(list, {
			platform = platform(function (made: { [string]: any })
				made.id = id
			end),
			words = "id must be a whole number from 1 to 127",
		})
	end

	table.insert(list, {
		platform = platform(function (made: { [string]: any })
			made.path = roblox.Vector3.zero
		end),
		words = "path must be a function",
	})

	table.insert(list, {
		platform = platform(function (made: { [string]: any })
			made.boxes = nil
		end),
		words = "needs a list of at least one box",
	})

	for _, boxes: any in { {}, "boxes" } do
		table.insert(list, {
			platform = platform(function (made: { [string]: any })
				made.boxes = boxes
			end),
			words = "needs a list of at least one box",
		})
	end

	table.insert(list, {
		platform = platform(function (made: { [string]: any })
			made.boxes = { 3 }
		end),
		words = "must be a table of its center and size",
	})

	local sizes: { any } = { roblox.Vector3.new(0, 1, 1), roblox.Vector3.new(1, -1, 1), roblox.Vector3.new(1, 1, 0) }
	for _, size: any in sizes do
		table.insert(list, {
			platform = platform(function (made: { [string]: any })
				made.boxes = box(roblox.Vector3.zero, size).boxes
			end),
			words = "needs a size above 0 on every axis",
		})
	end

	for _, size: any in { roblox.Vector3.new(math.huge, 1, 1), roblox.Vector3.new(1, 0 / 0, 1) } do
		table.insert(list, {
			platform = platform(function (made: { [string]: any })
				made.boxes = box(roblox.Vector3.zero, size).boxes
			end),
			words = "size must be finite",
		})
	end

	table.insert(list, {
		platform = platform(function (made: { [string]: any })
			made.boxes = box(roblox.Vector3.new(0, 0 / 0, 0), roblox.Vector3.one).boxes
		end),
		words = "center must be finite",
	})

	table.insert(list, {
		platform = platform(function (made: { [string]: any })
			made.boxes = box(vector.zero, roblox.Vector3.one).boxes
		end),
		words = "center must be a Vector3",
	})

	return list
end

-- Why a call that should throw with those words did not, or nil
local function refused(label: string, words: string, call: (...any) -> ...any, ...: any): string?
	local ran: boolean, message: any = pcall(call, ...)
	if ran then
		return `{label} was taken`
	elseif not string.find(`{message}`, words, 1, true) then
		return `{label}'s refusal was something else: {message}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Platforms: any = Environment.load(PLATFORMS)
	local Riders: any = Environment.load(RIDERS)
	local world: any = Riders.world()
	local casts: any = world.collision

	for index: number, refusal: { platform: any, words: string } in refusals() do
		local problem: string? = refused(`refusal {index}`, refusal.words, Platforms.add, world, refusal.platform)
		if problem then
			return false, problem
		elseif next(world.platforms) ~= nil or world.collision ~= casts then
			return false, `refusal {index} left a platform registered or the world's casts wrapped`
		end
	end

	-- A repeated id, after the first took it
	Platforms.add(world, platform(function () end))
	local repeated: string? =
		refused("a repeated id", "already registered", Platforms.add, world, platform(function () end))
	if repeated then
		return false, repeated
	end

	local unknown: string? =
		refused("a call of an unknown id", "No platform with the id 9", Platforms.call, world, 9, 10)
	if unknown then
		return false, unknown
	end

	for _, tick: any in { 1.5, 0 / 0, math.huge, "10" } do
		local problem: string? =
			refused(`a call on the tick {tick}`, "needs a whole tick", Platforms.call, world, 5, tick)
		if problem then
			return false, problem
		end
	end

	if Platforms.at(world, 9, 10) ~= nil then
		return false, "Platforms.at gave a place for an id no platform holds"
	end

	for _, tick: any in { 0 / 0, math.huge } do
		local problem: string? =
			refused(`a place on the tick {tick}`, "needs a finite tick", Platforms.at, world, 5, tick)
		if problem then
			return false, problem
		end
	end

	-- A path that gives no finite Vector3 is refused where it is first placed
	local broken: any = Riders.world()
	Platforms.add(
		broken,
		platform(function (made: { [string]: any })
			made.path = function (): any
				return roblox.Vector3.new(0, 0 / 0, 0)
			end
		end)
	)

	local badPath: string? =
		refused("a path giving no finite place", "must give a finite position", Platforms.at, broken, 5, 3)
	if badPath then
		return false, badPath
	end

	local wrongType: any = Riders.world()
	Platforms.add(
		wrongType,
		platform(function (made: { [string]: any })
			made.path = function (): any
				return vector.zero
			end
		end)
	)

	local badKind: string? = refused("a path giving a vector", "must give a Vector3", Platforms.at, wrongType, 5, 3)
	if badKind then
		return false, badKind
	end

	return true, nil
end
