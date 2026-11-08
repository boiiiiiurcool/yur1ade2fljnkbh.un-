-- movement.lua  (Y1 Misc tab > Movement page)
-- ASCII only, conservative syntax.
-- Empty for now. misc.lua calls Movement.build(container, T, H, ctx) and puts whatever
-- you build here into the Movement page. Return a table with an Unload function if you need cleanup.

local MovementPage = {}

function MovementPage.build(parent, T, H, ctx)
	return {
		Unload = function() end,
	}
end

return MovementPage
