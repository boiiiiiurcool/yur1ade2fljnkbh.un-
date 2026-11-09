-- world.lua  (Y1 World tab)
-- ASCII only, conservative syntax.
-- Empty for now. ui.lua calls World.build(container, T, H, opts) and puts whatever you build here
-- into the World tab (opts is the World table from main.lua).
-- Return a table with an Unload function if you need cleanup.

local WorldPage = {}

function WorldPage.build(parent, T, H, opts)
	return {
		Unload = function() end,
	}
end

return WorldPage
