--[[
    Each frame moves a platform's model pivot to where its path puts it at
    the drawn tick, between whole ticks through the step's lerp, with the
    model's turn kept, and only when that place changed; position gives
    the same place, nil before the first frame and for an unknown id, and
    the closure takes the copy out with the platform
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementMethod

local Environment = require("../../Environment")

local CLIENT_PLATFORMS: string = "src/Client/Platforms.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local CAR: number = 21
local BARE: number = 22 -- A platform with no model
local DRAWN: number = 40.25 -- The drawn tick, a quarter of the way to the next
local TURN: number = 0.7 -- The model's own turn about Y, in radians
local TOLERANCE: number = 1e-6 -- How near a CFrame's rotation must keep, past its float32 storage

-- Each model's pivot, which the stand-in GetPivot and PivotTo read and write, and how many moves each took
local Pivots: { [any]: any } = {}
local Moves: { [any]: number } = {}

roblox.implementMethod("Model", "GetPivot", function (model: any): any
	return Pivots[model] or roblox.CFrame.identity
end)

roblox.implementMethod("Model", "PivotTo", function (model: any, cframe: any)
	Pivots[model] = cframe
	Moves[model] = (Moves[model] or 0) + 1
end)

-- A platform sliding along X a tenth of a stud a tick, off the quantum
local function sliding(id: number, model: any): { [string]: any }
	return {
		id = id,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.new(4, 1, 4) } },
		path = function (tick: number, _: number?): any
			return roblox.Vector3.new(200 + tick / 10, 1200, 0)
		end,
		model = model,
	}
end

local function sameTurn(a: any, b: any): boolean
	local ax: any, ay: any, az: any = a.XVector, a.YVector, a.ZVector
	local bx: any, by: any, bz: any = b.XVector, b.YVector, b.ZVector

	return (ax - bx).Magnitude < TOLERANCE and (ay - by).Magnitude < TOLERANCE and (az - bz).Magnitude < TOLERANCE
end

return function (): (boolean, string | nil)
	local ClientPlatforms: any = Environment.load(CLIENT_PLATFORMS)
	local Platforms: any = Environment.load(PLATFORMS)
	local Riders: any = Environment.load(RIDERS)
	local world: any = Riders.world()

	local model: any = roblox.Instance.new("Model")
	local part: any = roblox.Instance.new("Part")
	part.CanCollide = false
	part.Parent = model

	local start: any = roblox.CFrame.new(5, 5, 5) * roblox.CFrame.Angles(0, TURN, 0)
	Pivots[model] = start

	local remove: () -> () = ClientPlatforms.add(world, sliding(CAR, model))
	ClientPlatforms.add(world, sliding(BARE, nil))
	if ClientPlatforms.position(CAR) ~= nil or ClientPlatforms.position(99) ~= nil then
		return false, "position gave a place before the first frame, or for an id no platform holds"
	end

	ClientPlatforms.frame(world, DRAWN)

	local expected: vector = Platforms.at(world, CAR, DRAWN)
	local pivot: any = Pivots[model]
	if ClientPlatforms.position(CAR) ~= expected or ClientPlatforms.position(BARE) ~= expected then
		return false, `position gave {ClientPlatforms.position(CAR)}, where the path's place at {DRAWN} is {expected}`
	elseif pivot.Position ~= roblox.Vector3.new(expected.x, expected.y, expected.z) then
		return false, `The model's pivot moved to {pivot.Position}, where the path's place at {DRAWN} is {expected}`
	elseif not sameTurn(pivot, start) then
		return false, `The model's pivot turned to {pivot}, where its own turn was {start}`
	end

	-- The same drawn tick moves nothing again, and the next one does
	ClientPlatforms.frame(world, DRAWN)
	ClientPlatforms.frame(world, DRAWN + 1)
	if Moves[model] ~= 2 then
		return false, `Three frames on two drawn ticks moved the model {Moves[model]} times, not 2`
	end

	-- The closure takes the copy out with the platform, harmless twice
	remove()
	remove()
	ClientPlatforms.frame(world, DRAWN + 2)
	if ClientPlatforms.position(CAR) ~= nil or world.platforms[CAR] ~= nil then
		return false, "Taking the car out left its copy's place or its platform behind"
	elseif Moves[model] ~= 2 then
		return false, "A frame after the car was taken out still moved its model"
	elseif ClientPlatforms.position(BARE) ~= Platforms.at(world, BARE, DRAWN + 2) then
		return false, "Taking the car out stopped the platform beside it from being placed"
	end

	return true, nil
end
