-- visuals.lua  (Y1 Visuals tab, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Visuals tab INTO win.VisualsPage (ui.lua loads it through opts.VisualsModule and passes
-- opts.Visuals in as the 4th argument). It is called inside a pcall, so a broken module cannot break
-- the window.
--
-- Build signature: Visuals.build(container, T, H, opts) -> { Root = ..., Unload = fn }
-- This is the empty starting page: put the cards / controls inside `root`.

local VisualsPage = {}

function VisualsPage.build(parent, T, H, opts)
	opts = opts or {}

	local new, label = H.new, H.label
	local running = true
	local conns = {}

	local root = new("Frame", {
		Name = "VisualsRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	label(root, "VISUALS", UDim2.fromOffset(4, 6), UDim2.new(1, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	local function unload()
		if not running then
			return
		end
		running = false
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
	end

	conns[#conns + 1] = root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(game) then
			unload()
		end
	end)

	return { Root = root, Unload = unload }
end

return VisualsPage
