--[[
    A built copy's model is named FirstPersonCopy and a release gives it its
    own name back, while the world rig keeps its name, a build with no copy
    names nothing, and the next body's copy is named under its own name
--]]

--!strict
local Environment = require("../../Environment")
local Owner = require("../../Fixtures/Rigs/Owner")

local FIRST_PERSON: string = "src/Client/Rigs/FirstPerson.luau"
local COPY_NAME: string = "FirstPersonCopy"
local WORLD_NAME: string = "WorldRig"
local POOLED_NAME: string = "PooledRig" -- The copy's own name, as the pool gave it out
local NEXT_NAME: string = "NextPooledRig" -- The next body's copy, a different pooled rig

return function (): (boolean, string | nil)
	local FirstPerson = Environment.load(FIRST_PERSON)
	local world: Model, copy: Owner.Copy = Owner.rigs()
	world.Name = WORLD_NAME
	copy.rig.Name = POOLED_NAME

	local view = FirstPerson.new()
	view:build(world, copy)

	if copy.rig.Name ~= COPY_NAME then
		return false, `A built copy is named {copy.rig.Name}, not {COPY_NAME}`
	elseif world.Name ~= WORLD_NAME then
		return false, `Building the copy renamed the world rig {world.Name}`
	end

	-- A refresh and the settings leave the names alone
	view:refresh()
	view:show("copy", false)
	view:show("rig", true)
	if copy.rig.Name ~= COPY_NAME or world.Name ~= WORLD_NAME then
		return false, `A refresh or a setting renamed the rigs {world.Name} and {copy.rig.Name}`
	end

	view:release()
	if copy.rig.Name ~= POOLED_NAME then
		return false, `A released copy is named {copy.rig.Name}, not its own {POOLED_NAME}`
	elseif world.Name ~= WORLD_NAME then
		return false, `The release renamed the world rig {world.Name}`
	end

	-- A body whose copy couldn't be dressed: no name changes, through its build and its release
	local lone: Model = Owner.rigs()
	lone.Name = WORLD_NAME
	view:build(lone, nil)
	if lone.Name ~= WORLD_NAME or copy.rig.Name ~= POOLED_NAME then
		return false, `A build with no copy renamed a rig: {lone.Name} and {copy.rig.Name}`
	end

	view:release()
	if lone.Name ~= WORLD_NAME or copy.rig.Name ~= POOLED_NAME then
		return false, `A release with no copy renamed a rig: {lone.Name} and {copy.rig.Name}`
	end

	-- The next body's copy is named too, and gets its own name back, not the last copy's
	local nextWorld: Model, nextCopy: Owner.Copy = Owner.rigs()
	nextWorld.Name = WORLD_NAME
	nextCopy.rig.Name = NEXT_NAME
	view:build(nextWorld, nextCopy)
	if nextCopy.rig.Name ~= COPY_NAME or nextWorld.Name ~= WORLD_NAME then
		return false, `The next build named its rigs {nextWorld.Name} and {nextCopy.rig.Name}`
	elseif copy.rig.Name ~= POOLED_NAME then
		return false, `The next build renamed the last copy {copy.rig.Name}`
	end

	view:release()
	if nextCopy.rig.Name ~= NEXT_NAME then
		return false, `The next copy is named {nextCopy.rig.Name} after its release, not its own {NEXT_NAME}`
	elseif nextWorld.Name ~= WORLD_NAME then
		return false, `The next release renamed the world rig {nextWorld.Name}`
	end

	return true, nil
end
