--[[
    addPlatform refuses what the platforms' registration refuses, no table,
    an id another holds and a model part with CanCollide on, and a refused
    add leaves the platforms already registered as they were
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and Instance

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local HELD: number = 7
local SOLID: number = 8 -- One whose model has a part with CanCollide on

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local world: any = handle._world

	rig.handshake()
	local first: any = Riders.lift(HELD, roblox.Vector3.new(0, 1200, 0), 0, 0)
	handle:addPlatform(first)

	if pcall(handle.addPlatform, handle, "lift") then
		return false, "addPlatform took a string as a platform"
	elseif pcall(handle.addPlatform, handle, Riders.lift(HELD, roblox.Vector3.new(50, 1200, 0), 0, 0)) then
		return false, `addPlatform took a second platform with the id {HELD}`
	end

	local model: any = roblox.Instance.new("Model")
	local part: any = roblox.Instance.new("Part")
	part.CanCollide = true
	part.Parent = model

	local solid: any = Riders.lift(SOLID, roblox.Vector3.new(100, 1200, 0), 0, 0)
	solid.model = model
	if pcall(handle.addPlatform, handle, solid) then
		return false, "addPlatform took a platform whose model has a part with CanCollide on"
	elseif world.platforms[SOLID] ~= nil then
		return false, "The refused platform was registered anyway"
	end

	-- The platform registered first is still the one its id names, and its copy still moves each frame
	rig.frames(1)

	local Platforms: any = rig.globals.require(rig.tread.Step.Platforms)
	local ClientPlatforms: any = rig.globals.require(rig.tread.Client.Platforms)
	if world.platforms[HELD] == nil or ClientPlatforms.position(HELD) ~= Platforms.at(world, HELD, handle._ticks) then
		return false, "A refused add disturbed the platform registered before it"
	end

	return true, nil
end
