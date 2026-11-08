--[[
    The dev client's settings, built as its bootstrap builds them, pass
    Tread's client check beside the dev game's shared table, and carry
    Frontier Zero's numbers as the approved example's fixture gives them
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")
local Shared = require("../../Fixtures/DevShared/Harness")

local INPUT: string = "dev/Client/Input.luau"
local RIG: string = "dev/Client/Rig.luau"
local CONFIG: string = "dev/Client/Config.luau"

-- The keys whose every value is Frontier Zero's, the same as the example's
local SAME: { string } = { "interpolation", "smoothing", "lod" }

-- Frontier Zero's own numbers inside the blocks that also hold stand-ins
local FRONTIER: { string } = {
	"drawDistance.desktop",
	"drawDistance.console",
	"bodies.radius",
	"bodies.late",
	"bodies.minSeconds",
	"bodies.maxSeconds",
	"bodies.check",
	"bodies.settleSpeed",
	"bodies.pushSpeed",
	"bodies.pushUpBias",
}

return function (): (boolean, string | nil)
	local loaded: Shared.Loaded = Shared.load()
	local place: Harness.Game = Harness.new()
	local Input: any = place.load(INPUT)
	local Rig: any = place.load(RIG)
	local Config: any = place.load(CONFIG)
	local Example: any = loaded.Example

	local input: any = Input.new()
	local settings: any = {
		sample = function (command: any)
			input:sample(command)
		end,

		look = function (): (number, number, number, number)
			return input:look()
		end,

		rig = Rig.template(),
		joints = Rig.joints,
		animations = Rig.animations(),
		dress = Rig.dress,
		undress = Rig.undress,
		hold = Rig.hold,
		interpolation = Config.interpolation,
		bodies = Config.bodies,
		smoothing = Config.smoothing,
		drawDistance = Config.drawDistance,
		lod = Config.lod,
		spectate = Config.spectate,
	}

	local checked: boolean, failure: any = pcall(loaded.Config.client, loaded.shared, settings)
	if not checked then
		return false, `Tread's client check refused the dev client's settings: {failure}`
	end

	local example: any = Example.client()
	for _, key: string in SAME do
		for name: string, value: any in example[key] do
			if Config[key][name] ~= value then
				return false, `{key}.{name} is {Config[key][name]}, where Frontier Zero's is {value}`
			end
		end
	end

	for _, path: string in FRONTIER do
		local ours: any = Example.get(Config, path)
		local theirs: any = Example.get(example, path)
		if ours ~= theirs then
			return false, `{path} is {ours}, where Frontier Zero's is {theirs}`
		end
	end

	return true, nil
end
