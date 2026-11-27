--[[
    G9's spectate numbers: how far into the window the recording taps
    connect, a spectating moderator's two lines, the withheld bytes' rough
    size beside them, and what Volt adds in front of each withheld block
--]]

--!strict
return {
	taps = 0.5, -- The share of the window run before the taps connect, so the relay runs with them off, then on

	-- KB/s, each a second
	copy = 98, -- A moderator's copy of its target and its feed together, the target's hard budget and the feed's 2
	feed = 2, -- What a moderator's copy and feed may pass its target's own bytes by
	withheld = 71.5, -- About every other character's records at 30 Hz, which sent and withheld together can't pass

	framing = 3, -- Bytes in front of each Withheld block a moderator is sent, Volt's message id and the block's u16 length
}
