--[[
    The client draws its frame in one render step of its own, bound after
    Input priority and before Camera's, and runs it once a frame, so nothing
    of its frame waits on PreRender
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

local INPUT: number = roblox.Enum.RenderPriority.Input.Value
local CAMERA: number = roblox.Enum.RenderPriority.Camera.Value
local SLOT: number = 7
local GENERATION: number = 1
local COMMAND: number = 40
local TICK: number = 300
local FRAMES: number = 5

return function (): (boolean, string | nil)
	local rig: any = Handle.new({ start = false })

	-- The game's look, read once each time the owner's frame runs
	local looks: number = 0
	rig.client.look = function (): (number, number, number, number)
		looks += 1

		return 0, 0, 0, 0
	end

	rig.start()

	local bindings: { Handle.Binding } = rig.bindings
	if #bindings ~= 1 then
		return false, `Starting the client made {#bindings} render-step bindings, not 1`
	end

	local binding: Handle.Binding = bindings[1]
	local between: string = `after Input's {INPUT} and before Camera's {CAMERA}`
	if type(binding.name) ~= "string" or binding.name == "" then
		return false, `The client's render step is named {binding.name}, not a name of its own`
	elseif binding.priority <= INPUT or binding.priority >= CAMERA then
		return false, `The client's frame is bound at {binding.priority}, not {between}`
	end

	rig.handshake()
	rig.own(SLOT, GENERATION)
	rig.owner(rig.body(vector.create(0, 20, 0), COMMAND, TICK))

	-- The frame reads the look once a run, so a frame also connected to PreRender would read it twice a frame
	rig.frames(FRAMES)
	if looks ~= FRAMES then
		return false, `{FRAMES} frames ran the owner's frame {looks} times, not once each`
	end

	return true, nil
end
