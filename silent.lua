-- silent.lua  (Y1 Combat tab: the Silent page content, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- This module is empty on purpose for now. aimbot.lua loads it (through main.lua, which passes it in
-- as opts.SilentModule) and builds it into the Silent page of the Combat tab:
--
--   SilentPage.build(container, themeTable, helperTable, ctx)
--
--   container  a full size, transparent frame on the Silent page: put your controls in it
--   themeTable the same theme table the other modules get (colours, tween infos)
--   helperTable the same helpers (new, corner, stroke, pad, label, hoverable)
--   ctx        { Settings = the aimbot settings table,
--                Targeting = { refPoint, validTarget, acquire, bestPart, aimPosition, isVisible, originPos } }
--
-- build may return a table with an Unload function. It is called when the Y1 window is unloaded.

local SilentPage = {}

function SilentPage.build(container, T, H, ctx)
	-- nothing here yet

	return {
		Unload = function()
		end,
	}
end

return SilentPage
