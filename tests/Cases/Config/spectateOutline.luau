--[[
    The client's check takes the spectate outline's two colors and two
    transparencies from 0 to 1, and refuses the block or any of its keys
    missing, a color that isn't a Color3, a transparency outside 0 to 1, and
    a key it doesn't read
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

type Refusal = { path: string, value: any }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local refusals: { Refusal } = {
		{ path = "spectate", value = nil },
		{ path = "spectate", value = "outline" },
		{ path = "spectate.outline", value = nil },
		{ path = "spectate.outline.fill", value = nil },
		{ path = "spectate.outline.fill", value = roblox.Vector3.new(1, 0, 0) },
		{ path = "spectate.outline.fill", value = "Red" },
		{ path = "spectate.outline.outline", value = 0xFFFFFF },
		{ path = "spectate.outline.fillTransparency", value = nil },
		{ path = "spectate.outline.fillTransparency", value = 1.5 },
		{ path = "spectate.outline.outlineTransparency", value = -0.1 },
		{ path = "spectate.outline.outlineTransparency", value = 0 / 0 },
		{ path = "spectate.outline.width", value = 2 },
		{ path = "spectate.color", value = roblox.Color3.new(1, 1, 1) },
	}

	for _, refusal: Refusal in refusals do
		local client = Example.client()
		Example.set(client, refusal.path, refusal.value)

		local problem: string? = Example.refusal(Config.client, `client.{refusal.path}`, Example.shared(), client)
		if problem then
			return false, problem
		end
	end

	-- Each transparency's two edges pass
	for _, edge: number in { 0, 1 } do
		local client = Example.client()
		client.spectate.outline.fillTransparency = edge
		client.spectate.outline.outlineTransparency = edge

		local passed: boolean, failure: any = pcall(Config.client, Example.shared(), client)
		if not passed then
			return false, `Config.client refused transparencies of {edge}: {failure}`
		end
	end

	return true, nil
end
