--[[
    A module that requires itself while it loads, a cycle of one, which the
    require inside it refuses as a module still loading
--]]

--!strict
return require(script)
