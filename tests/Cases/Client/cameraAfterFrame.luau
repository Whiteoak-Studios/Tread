--[[
    A camera bound at Camera priority and one connected to PreRender, both
    made before Tread's client starts, read each frame the eye and look
    that frame drew, never the frame before's
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

local CAMERA: number = roblox.Enum.RenderPriority.Camera.Value
local SLOT: number = 3
local GENERATION: number = 1
local COMMAND: number = 40
local TICK: number = 300
local FRAMES: number = 4
local TURN: number = 0.05 -- Radians the game's look turns each frame, so every frame draws a look of its own

-- What one camera read in the frame it last ran in
type Seen = {
	eye: Vector3?,
	look: Vector3?,
}

return function (): (boolean, string | nil)
	local rig: any = Handle.new({ start = false })
	local runService: any = rig.globals.game:GetService("RunService")

	local turns: number = 0
	rig.client.look = function (): (number, number, number, number)
		turns += 1

		return turns * TURN, 0, 0, 0
	end

	-- The two places a game's camera goes, each made before Tread's own frame, the order the engine runs least kindly
	local bound: Seen = { eye = nil, look = nil }
	runService:BindToRenderStep("Camera", CAMERA, function (_: number)
		bound.eye, bound.look = rig.handle:getEye()
	end)

	local connected: Seen = { eye = nil, look = nil }
	runService.PreRender:Connect(function (_: number)
		connected.eye, connected.look = rig.handle:getEye()
	end)

	local cameras: { [string]: Seen } = {
		["The camera at Camera priority"] = bound,
		["The PreRender camera"] = connected,
	}

	rig.start()
	rig.handshake()
	rig.own(SLOT, GENERATION)
	rig.owner(rig.body(vector.create(0, 20, 0), COMMAND, TICK))

	for frame: number = 1, FRAMES do
		local _, before: Vector3 = rig.handle:getEye()
		rig.frames(1)
		local eye: Vector3, look: Vector3 = rig.handle:getEye()

		if look == before then
			return false, `Frame {frame} drew the look {look} the frame before had, so it shows no frame's own look`
		end

		for name: string, seen: Seen in cameras do
			if seen.eye ~= eye or seen.look ~= look then
				local drawn: string = `frame {frame} drew {eye} looking {look}`
				return false, `{name} read {seen.eye} looking {seen.look}, where {drawn}`
			end
		end
	end

	return true, nil
end
