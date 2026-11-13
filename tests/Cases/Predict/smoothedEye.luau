--[[
    A correction a stud long carries the drawn body and its eye over in the
    visual error offset, which shrinks each frame by the game's decay through
    Math.lerp, while one past the game's 2-stud snap draws at once on the
    corrected path
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

-- The published eye, which in the open, with no wall near and no lean, sits over the drawn feet's x and z
local function eyeAt(rig: any): vector
	local eye: vector = rig.Predict.eye()

	return eye
end

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	rig.spawn()
	rig.frames(4)

	local before: vector = eyeAt(rig)
	local server: any = rig.twin(2)
	server.position += vector.create(0, 0, 1)
	rig.Predict.receive(rig.owner(server, 2))

	-- The replayed path lies a stud along +Z, and the offset carries the eye over from where it was drawn
	local carried: vector = eyeAt(rig)
	if carried.x ~= before.x or carried.z ~= before.z then
		return false, `The correction moved the eye from {before} to {carried}, where the offset should hold it`
	end

	-- A frame of 0.4 ticks places the body 0.4 of the way along, and shrinks the offset at 15 a second over its time
	local Math: any = rig.Math
	local dt: number = rig.delta * 0.4
	local fraction: number = dt / rig.delta
	local third: any = rig.copy(server)
	rig.step(third, 3, 3)
	local fourth: any = rig.copy(third)
	rig.step(fourth, 4, 4)

	rig.frames(1, dt)

	-- A vector holds float32s, so the sum is a vector's, as the drawn body's is
	local shrunk: number = Math.lerp(-1, 0, 1 - math.exp(-15 * dt))
	local placed: number = Math.lerp(third.position.z, fourth.position.z, fraction)
	local want: number = (vector.create(0, 0, placed) + vector.create(0, 0, shrunk)).z
	local smoothed: vector = eyeAt(rig)
	if smoothed.z ~= want then
		return false, `After one frame the eye's z was {smoothed.z}, not {want} with the offset shrunk to {shrunk}`
	end

	-- 3 studs is past the snap, so the eye draws on the corrected path at once
	local far: any = Harness.new()
	far.spawn()
	far.frames(4)
	local leaped: any = far.twin(2)
	leaped.position += vector.create(0, 0, 3)
	far.Predict.receive(far.owner(leaped, 2))

	-- No time is owed, so the body draws at the tick before the newest, the corrected state after command 3
	local corrected: any = far.copy(leaped)
	far.step(corrected, 3, 3)
	local snapped: vector = eyeAt(far)
	if snapped.z ~= corrected.position.z then
		return false, `A 3-stud correction drew the eye at z {snapped.z}, not the corrected {corrected.position.z}`
	end

	return true, nil
end
