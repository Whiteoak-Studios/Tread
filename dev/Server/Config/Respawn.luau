--[[
    The respawn check's settings: how long a respawned body settles before
    its reports are counted, how long they are counted for, and how far
    from its spawn point it may stand at the end
--]]

--!strict
return {
	settle = 2, -- Seconds after the respawn, for the new body's first OwnerState to reach its client and commands to flow
	window = 10, -- Seconds the respawned player's reports are counted over
	distance = 2, -- Studs the body's feet may stand from its spawn point, which sits the spawn lift above the floor
}
