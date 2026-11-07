--[[
    The client's check refuses client settings with a hook that isn't a
    function, a rig that isn't a Model, a state with no Animation, a joint
    named by no string, or a key missing, out of range or unknown
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

	local folder: any = roblox.Instance.new("Folder")

	local refusals: { Refusal } = {
		{ path = "sample", value = nil },
		{ path = "sample", value = 5 },
		{ path = "rig", value = nil },
		{ path = "rig", value = folder },
		{ path = "rig", value = "Character" },
		{ path = "joints", value = "Root" },
		{ path = "joints.Neck", value = 5 },
		{ path = "animations", value = nil },
		{ path = "animations.crawl", value = nil },
		{ path = "animations.walk", value = folder },
		{ path = "animations.reload", value = folder },
		{ path = "dress", value = nil },
		{ path = "undress", value = 1 },
		{ path = "hold", value = nil },
		{ path = "interpolation.scaleMin", value = nil },
		{ path = "bodies.jointLimits.Neck.tilt", value = -1 },
		{ path = "bodies.jointLimits.Neck", value = 30 },
		{ path = "bodies.jointLimits.Neck.bend", value = 10 },
		{ path = "bodies.pushUpBias", value = "0.5" },
		{ path = "smoothing.decay", value = 0 },
		{ path = "drawDistance.phone", value = nil },
		{ path = "lod.aim", value = -1 },
		{ path = "lod.far", value = 100 },
	}

	for _, refusal: Refusal in refusals do
		local client = Example.client()
		Example.set(client, refusal.path, refusal.value)

		local problem: string? = Example.refusal(Config.client, `client.{refusal.path}`, Example.shared(), client)
		if problem then
			return false, problem
		end
	end

	local missing: string? = Example.refusal(Config.client, "client", Example.shared(), nil)
	if missing then
		return false, missing
	end

	return true, nil
end
