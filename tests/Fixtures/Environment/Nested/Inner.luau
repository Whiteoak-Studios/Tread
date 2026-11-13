--[[
    A file one folder down, which climbs one Parent more than its folder's
    init.luau to reach the Counter beside that folder
--]]

--!strict
return require(script.Parent.Parent.Counter)
