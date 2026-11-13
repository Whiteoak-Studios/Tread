--[[
    Collide refuses a move that is not finite on every axis, and a clear test
    of a box with no size on some axis, before any cast runs
--]]

--!strict
local Environment = require("../../Environment")

local COLLIDE: string = "src/Step/Collide.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local MOVE_REFUSAL: string = "A move must be finite"
local SIZE_REFUSAL: string = "A box needs a size above 0"

return function (): (boolean, string | nil)
	local Collide: any = Environment.load(COLLIDE)
	local Scene: any = Environment.load(SCENE)
	local casts: { number } = {}

	-- Casts over no parts that count every call, so a refusal is shown to come before any
	local collision: any = Environment.load(CASTS)({})
	for _, name: string in { "ray", "sweep", "rest", "sphere", "overlap" } do
		local cast: (...any) -> ...any = collision[name]
		collision[name] = function (...: any): ...any
			table.insert(casts, 1)
			return cast(...)
		end
	end

	local world: any = Scene.world(collision)
	local infinite: number = math.huge
	local undefined: number = 0 / 0

	for _, delta: vector in
		{ vector.create(undefined, 0, 0), vector.create(0, infinite, 0), vector.create(0, 0, -infinite) }
	do
		local state: any = Scene.state(vector.create(0, 1100.02, 0), true)
		local ran: boolean, message: any = pcall(Collide.move, state, delta, world)

		if ran then
			return false, `Collide.move took the move {delta}`
		elseif not string.find(`{message}`, MOVE_REFUSAL, 1, true) then
			return false, `Collide.move of {delta} failed with something other than its refusal: {message}`
		end
	end

	for _, size: vector in { vector.create(0, 5, 2.78), vector.create(2.78, -5, 2.78) } do
		local ran: boolean, message: any = pcall(Collide.clear, vector.create(0, 1103, 0), size, world)

		if ran then
			return false, `Collide.clear took the size {size}`
		elseif not string.find(`{message}`, SIZE_REFUSAL, 1, true) then
			return false, `Collide.clear of the size {size} failed with something other than its refusal: {message}`
		end
	end

	if #casts > 0 then
		return false, `{#casts} casts ran before a refusal`
	end

	return true, nil
end
