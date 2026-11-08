--[[
    The test elevator's numbers, which both realms read: where its deck
    rests, how far, fast and long it rides once called, where its call
    button sits, how far a press reaches and where a player presses from
--]]

--!strict
return {
	-- The deck's center at rest, west of the plaza with its bottom on the Asphalt at y 0, its whole ride inside the
	-- 14 x 28 x 14 box around (3805, 15.5, -45) that no city block part reaches into
	rest = Vector3.new(3805, 0.25, -45),
	deck = Vector3.new(8, 0.5, 8), -- Studs; its top 0.5 over the ground, under step.stepHeight, so a walk steps on
	top = 16, -- Studs it rises above its rest, a rider's head 21.5 over the ground there
	speed = 4, -- Studs/s it rises and falls at
	wait = 3, -- Seconds it holds at the top before coming back down

	-- The call button east of the deck, about eye height over the ground, which the press's ray meets
	button = CFrame.new(3810.5, 4, -45),
	buttonSize = Vector3.new(0.4, 1, 1),
	reach = 6, -- Studs along the look from the eye a press's ray reaches

	-- Where a player stands to press it with the look a fresh spawn gives, level along -Z: the button's face 3 studs
	-- ahead at eye height, the hull 0.11 studs clear of the deck's ride, lifted over the Asphalt as each spawn is
	spot = Vector3.new(3810.5, 0.5, -41.5),
}
