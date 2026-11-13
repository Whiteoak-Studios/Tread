--[[
    The server's check takes each posture's 1 to 6 aim points and a sleeper's
    rays up to its 3, refusing a missing posture, a list empty, too long or
    gapped, a bad point, a leftover antiEsp.rays and a bad include list
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
	local point: { up: number, side: number } = { up = 2, side = 0 }

	local refusals: { Refusal } = {
		{ path = "antiEsp.aim", value = nil },
		{ path = "antiEsp.aim.Stand", value = nil },
		{ path = "antiEsp.aim.Downed", value = "flat" },
		{ path = "antiEsp.aim.Prone", value = { point } },
		{ path = "antiEsp.aim.Crouch", value = {}, named = "antiEsp.aim.Crouch[1]" },
		{ path = "antiEsp.aim.Downed.7", value = point, named = "antiEsp.aim.Downed[7]" },
		{ path = "antiEsp.aim.Stand.8", value = point, named = "antiEsp.aim.Stand[8]" },
		{ path = "antiEsp.aim.Stand.extra", value = point },
		{ path = "antiEsp.aim.Stand.1", value = 5, named = "antiEsp.aim.Stand[1]" },
		{ path = "antiEsp.aim.Stand.1.up", value = nil, named = "antiEsp.aim.Stand[1].up" },
		{ path = "antiEsp.aim.Stand.2.side", value = "left", named = "antiEsp.aim.Stand[2].side" },
		{ path = "antiEsp.aim.Crouch.3.side", value = 0 / 0, named = "antiEsp.aim.Crouch[3].side" },
		{ path = "antiEsp.aim.Downed.5.up", value = math.huge, named = "antiEsp.aim.Downed[5].up" },
		{ path = "antiEsp.aim.Stand.4.lead", value = 1, named = "antiEsp.aim.Stand[4].lead" },
		{ path = "antiEsp.rays", value = 5 },
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
		{ path = "antiEsp.aim.Stand", value = { point } },
		{ path = "antiEsp.aim.Crouch.4.lead", value = false },
		{ path = "antiEsp.aim.Downed.1.up", value = -0.5 },
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
