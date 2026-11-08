--[[
    The server's check takes anti-ESP's rays up to the 5 a player pair's
    test has and a sleeper's up to its 3, refusing more, and refuses an
    anti-ESP include list that is missing, no table or holds a non-Instance
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

type Refusal = { path: string, value: any, named: string? }
type Taken = { path: string, value: any }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)
	local folder: any = roblox.Instance.new("Folder")

	local refusals: { Refusal } = {
		{ path = "antiEsp.rays", value = 6 },
		{ path = "antiEsp.rays", value = 4.5 },
		{ path = "sleepers.rays", value = 4 },
		{ path = "sleepers.rays", value = 0 },
		{ path = "antiEsp.include", value = nil },
		{ path = "antiEsp.include", value = "Occluders" },
		{ path = "antiEsp.include", value = { folder, 7 }, named = "antiEsp.include[2]" },
	}

	for _, refusal: Refusal in refusals do
		local server = Example.server()
		Example.set(server, refusal.path, refusal.value)

		local named: string = refusal.named or refusal.path
		local problem: string? = Example.refusal(Config.server, `server.{named}`, Example.shared(), server)
		if problem then
			return false, problem
		end
	end

	local taken: { Taken } = {
		{ path = "antiEsp.rays", value = 5 },
		{ path = "antiEsp.rays", value = 1 },
		{ path = "sleepers.rays", value = 3 },
		{ path = "sleepers.rays", value = 1 },
		{ path = "antiEsp.include", value = {} },
		{ path = "antiEsp.include", value = { folder, roblox.Instance.new("Camera") } },
	}

	for _, take: Taken in taken do
		local server = Example.server()
		Example.set(server, take.path, take.value)

		local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
		if not served then
			return false, `Config.server refused {take.path} at {take.value}: {failure}`
		end
	end

	return true, nil
end
