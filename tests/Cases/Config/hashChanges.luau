--[[
    The shared table's hash changes with any value in it: a number, even in
    its last bit, a nested key, a field declaration, each Vector3 component
    and an include list's instance
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local LAST_BIT: number = 2 ^ -46 -- The lowest bit of a number from 64 to 128, such as Frontier Zero's gravity

type Change = { label: string, path: string, value: any }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local base: number = Config.hash(Example.shared())
	local gravity: number = Example.shared().step.gravity
	local leanShift: any = Example.shared().step.leanShift
	local head: any = Example.shared().hitShapes.Stand.zones.head
	local to: any = Example.shared().hitShapes.Stand.body.to

	if gravity + LAST_BIT == gravity then
		return false, "The nudge leaves the gravity unchanged, so the last-bit change proves nothing"
	end

	local changes: { Change } = {
		{ label = "a number", path = "step.walk", value = 10.5 },
		{ label = "a number's last bit", path = "step.gravity", value = gravity + LAST_BIT },
		{ label = "a whole tolerance", path = "tolerances.Mantle", value = 1 },
		{ label = "a ratio", path = "ticks.nudge", value = 0.03 },
		{ label = "a zone added", path = "hitShapes.Stand.zones.skull", value = head },
		{ label = "a zone removed", path = "hitShapes.Stand.zones.head", value = nil },
		{ label = "a declaration's width", path = "fields.command.1.bits", value = 4 },
		{ label = "a declaration's kind", path = "fields.command.1.kind", value = "carried" },
		{ label = "a group field's name", path = "fields.command.2.fields.1.name", value = "seq" },
		{ label = "a declaration's start", path = "fields.server.1.start", value = true },
		{ label = "a declaration's flag", path = "fields.slot.1.optional", value = false },
		{
			label = "a declaration added",
			path = "fields.held.3",
			value = { name = "tint", type = "uint", bits = 8, optional = true },
		},
		{
			label = "leanShift's X",
			path = "step.leanShift",
			value = roblox.Vector3.new(0.58, leanShift.Y, leanShift.Z),
		},
		{
			label = "leanShift's Y",
			path = "step.leanShift",
			value = roblox.Vector3.new(leanShift.X, -0.11, leanShift.Z),
		},
		{
			label = "leanShift's Z",
			path = "step.leanShift",
			value = roblox.Vector3.new(leanShift.X, leanShift.Y, 0.01),
		},
		{ label = "a hit shape's end", path = "hitShapes.Stand.body.to", value = roblox.Vector3.new(to.X, 4.1, to.Z) },
		{ label = "an include list given", path = "collision.include", value = { roblox.Instance.new("Folder") } },
	}

	for _, change: Change in changes do
		local shared = Example.shared()
		Example.set(shared, change.path, change.value)

		if Config.hash(shared) == base then
			return false, `The hash ignored {change.label}`
		end
	end

	-- A zone renamed, the same capsule under another key
	local renamed = Example.shared()
	renamed.hitShapes.Stand.zones.skull = renamed.hitShapes.Stand.zones.head
	renamed.hitShapes.Stand.zones.head = nil

	if Config.hash(renamed) == base then
		return false, "The hash ignored a zone renamed"
	end

	-- Two keys trading their values is a change too
	local swapped = Example.shared()
	swapped.step.walk, swapped.step.sprint = swapped.step.sprint, swapped.step.walk

	if Config.hash(swapped) == base then
		return false, "The hash ignored two keys trading their values"
	end

	-- An include list's instances count by their full names
	local collisionFolder: any = roblox.Instance.new("Folder")
	collisionFolder.Name = "Collision"

	local hitboxFolder: any = roblox.Instance.new("Folder")
	hitboxFolder.Name = "Hitboxes"

	local first = Example.shared()
	first.collision = { include = { collisionFolder } }

	local second = Example.shared()
	second.collision = { include = { hitboxFolder } }

	if Config.hash(first) == Config.hash(second) then
		return false, "The hash ignored which instance an include list names"
	end

	return true, nil
end
