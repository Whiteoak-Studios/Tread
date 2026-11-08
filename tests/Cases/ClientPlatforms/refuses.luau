--[[
    ClientPlatforms.add refuses a model with a part that has CanCollide on,
    deep in it or not, and a model that is no Model, before it registers
    anything, and passes the step's own refusals through
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local CLIENT_PLATFORMS: string = "src/Client/Platforms.luau"
local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

local function platform(id: any, model: any): { [string]: any }
	return {
		id = id,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.one } },
		path = function (_: number, _: number?): any
			return roblox.Vector3.zero
		end,
		model = model,
	}
end

-- A model holding one part off and, in a folder inside it, one part with CanCollide as given
local function model(deepCollides: boolean): any
	local made: any = roblox.Instance.new("Model")
	local shell: any = roblox.Instance.new("Part")
	shell.CanCollide = false
	shell.Parent = made

	local folder: any = roblox.Instance.new("Folder")
	folder.Parent = made

	local deep: any = roblox.Instance.new("Part")
	deep.Name = "Deep"
	deep.CanCollide = deepCollides
	deep.Parent = folder

	return made
end

return function (): (boolean, string | nil)
	local ClientPlatforms: any = Environment.load(CLIENT_PLATFORMS)
	local Riders: any = Environment.load(RIDERS)
	local world: any = Riders.world()

	local refusals: { { platform: any, words: string } } = {
		{ platform = platform(3, model(true)), words = "Deep must have CanCollide off" },
		{ platform = platform(3, roblox.Instance.new("Part")), words = "model must be a Model" },
		{ platform = platform(3, "model"), words = "model must be a Model" },
		{ platform = platform(0, model(false)), words = "id must be a whole number from 1 to 127" },
		{ platform = "platform", words = "A platform must be a table" },
	}

	for index: number, refusal: { platform: any, words: string } in refusals do
		local ran: boolean, message: any = pcall(ClientPlatforms.add, world, refusal.platform)
		if ran then
			return false, `refusal {index} was taken`
		elseif not string.find(`{message}`, refusal.words, 1, true) then
			return false, `refusal {index}'s message was something else: {message}`
		elseif next(world.platforms) ~= nil or ClientPlatforms.position(3) ~= nil then
			return false, `refusal {index} left a platform registered`
		end
	end

	-- A model whose every part has CanCollide off is taken
	ClientPlatforms.add(world, platform(3, model(false)))
	if world.platforms[3] == nil then
		return false, "A model with every part's CanCollide off was not registered"
	end

	return true, nil
end
