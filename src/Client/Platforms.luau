--[[
    The client's copies of the moving platforms: each registered on the
    client's world, its model moved every frame to where its path puts it
    at the tick the owner's body is drawn at, which remote riders stand on
--]]

--!strict
local Engine = require(script.Parent.Parent.Step.Engine)
local Platforms = require(script.Parent.Parent.Step.Platforms)
local State = require(script.Parent.Parent.Step.State)

type Platform = State.Platform
type World = State.World

-- One platform's copy: its model and the turn it keeps, and where the last frame put it
type Copy = {
	model: Model?,
	rotation: CFrame,
	position: vector?,
}

local ClientPlatforms = {}

-- Each registered platform's copy, by id
local Copies: { [number]: Copy } = {}

--[[
    Registers a platform on the client's world as the server registers it,
    keeping its model, if it has one, to move each frame, and gives back
    the closure that removes both, harmless twice. Refuses what the step's
    registration refuses, and a model part with CanCollide on, which the
    client's own casts would meet where the server's never do
--]]

function ClientPlatforms.add(world: World, platform: Platform): () -> ()
	if type(platform) ~= "table" then
		error(`A platform must be a table, and got a {typeof(platform)}`)
	end

	local id: number = platform.id
	local model: Model? = platform.model
	local rotation: CFrame = CFrame.identity

	if model ~= nil then
		if typeof(model) ~= "Instance" or not model:IsA("Model") then
			error(`Platform {id}'s model must be a Model, and got a {typeof(model)}`)
		end

		for _, descendant: Instance in model:GetDescendants() do
			if descendant:IsA("BasePart") and (descendant :: BasePart).CanCollide then
				error(`Platform {id}'s model part {descendant:GetFullName()} must have CanCollide off`)
			end
		end

		rotation = model:GetPivot().Rotation
	end

	local remove: () -> () = Platforms.add(world, platform)
	local copy: Copy = { model = model, rotation = rotation, position = nil }
	Copies[id] = copy

	return function ()
		remove()

		if Copies[id] == copy then
			Copies[id] = nil
		end
	end
end

--[[
    Places every platform's copy at an unwrapped tick with its fraction,
    the one the owner's body is drawn at, each model's pivot moved there
    with its turn kept, and only when that place changed

    @ at | the drawn tick, unwrapped, between two whole ticks or on one
--]]

function ClientPlatforms.frame(world: World, at: number)
	for id: number, copy: Copy in Copies do
		local position: vector? = Platforms.at(world, id, at)

		if position and position ~= copy.position then
			copy.position = position

			local model: Model? = copy.model
			if model then
				model:PivotTo(copy.rotation + Engine.toVector3(position))
			end
		end
	end
end

--[[
    Where the last frame placed a platform's copy, nil for an id no
    platform holds or before the first frame placed it
--]]

function ClientPlatforms.position(id: number): vector?
	local copy: Copy? = Copies[id]
	if not copy then
		return nil
	end

	return copy.position
end

return ClientPlatforms
