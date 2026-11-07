--[[
    Takes an environment's Heartbeat into a case's hands: what connects to it
    is kept rather than run on a timer, and the case runs each frame itself
--]]

--!strict
local Frames = {}
Frames.__index = Frames

type Callback = (delta: number) -> ()

type Fields = {
	_callbacks: { Callback },
}

--[[
    Frames for an environment, taking over its Heartbeat's Connect before
    anything in it connects
--]]

function Frames.new(globals: any): Self
	local self: Self = setmetatable({ _callbacks = {} :: { Callback } }, Frames)
	local heartbeat: any = globals.game:GetService("RunService").Heartbeat

	heartbeat.Connect = function (_: any, callback: Callback): any
		table.insert(self._callbacks, callback)

		return {
			Disconnect = function (_: any)
				local index: number? = table.find(self._callbacks, callback)
				if index then
					table.remove(self._callbacks, index)
				end
			end,
		}
	end

	return self
end

-- Runs one frame of delta seconds on everything connected
function Frames.run(self: Self, delta: number)
	for _, callback: Callback in table.clone(self._callbacks) do
		callback(delta)
	end
end

export type Frames = Self
type Self = typeof(setmetatable({} :: Fields, Frames))

return Frames
