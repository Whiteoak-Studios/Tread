--[[
    What the relay's Actor workers and their pool share: the topics a worker
    binds, what each carries, and the attributes on a worker's Actor
--]]

--!strict
local Layout = {
	-- The topics a worker binds
	SETUP = "setup", -- (remote: ModuleScript, settings), taken in the serial phase
	RUN = "run", -- (round: number, shared: buffer, own: buffer), taken in the parallel phase

	-- The attributes on a worker's Actor
	WORKER = "Worker", -- Its index from 1, which only a clone the pool parents carries
	BOUND = "Bound", -- Set once it has bound both topics, since a message sent before that is never taken
	READY = "Ready", -- Set once its setup has loaded Remote and run Remote.setup
	FIRE_FAILED = "FireFailed", -- Set to the error the first time its BindableEvent fails to fire desynchronized
}

return Layout
