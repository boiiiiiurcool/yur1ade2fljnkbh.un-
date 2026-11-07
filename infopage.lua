-- infopage.lua  (Y1 Info tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Info tab INTO a frame (the Info page of ui.lua). It shows an ID card with a
-- placeholder person and placeholder text (grey bars). Nothing here is a real person or real text.
--
--   local InfoPage = <this file>
--   InfoPage.build(parentFrame, themeTable, helperTable, {})

local InfoPage = {}

function InfoPage.build(parent, T, H, opts)
	opts = opts or {}
	local new, corner, stroke = H.new, H.corner, H.stroke

	local root = new("Frame", {
		Name = "InfoRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	-- the ID card, centred in the page (it keeps its size when the window grows)
	local CARD_W = 380
	local CARD_H = 224
	local card = new("Frame", {
		Name = "IdCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -6),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, root)
	corner(card, 16)
	stroke(card, T.BORDER, 1, 0)

	-- soft light from the top left corner
	local sheen = new("Frame", {
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 1,
	}, card)
	corner(sheen, 16)
	new("UIGradient", {
		Rotation = 35,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.94),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sheen)

	local function bar(x, y, w, h, color, r)
		local f = new("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, card)
		corner(f, r or math.floor(h / 2))
		return f
	end

	-- top row: small chip + title bar (placeholders)
	bar(22, 20, 22, 16, T.CLUSTER_BG, 5)
	bar(54, 24, 96, 8, T.CLUSTER_BG)
	bar(CARD_W - 22 - 40, 24, 40, 8, T.CLUSTER_BG)

	-- photo slot with a placeholder person (head + shoulders)
	local photo = new("Frame", {
		Name = "Photo",
		Position = UDim2.fromOffset(22, 56),
		Size = UDim2.fromOffset(104, 128),
		BackgroundColor3 = T.CARD_BG,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
	}, card)
	corner(photo, 12)

	local head = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = T.MATCH_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, photo)
	corner(head, 100)

	local shoulders = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(78, 70),
		BackgroundColor3 = T.MATCH_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, photo)
	corner(shoulders, 34)

	-- text lines on the right (placeholder bars)
	local X = 146
	bar(X, 60, 150, 14, T.MATCH_BG)
	bar(X, 84, 90, 8, T.CLUSTER_BG)

	bar(X, 112, 40, 6, T.CLUSTER_BG)
	bar(X, 124, 200, 8, T.CARD_BG)
	bar(X, 146, 40, 6, T.CLUSTER_BG)
	bar(X, 158, 150, 8, T.CARD_BG)

	-- bottom: barcode-like strip (placeholder)
	local widths = { 3, 1, 2, 1, 3, 2, 1, 1, 3, 2, 1, 3, 1, 2, 2, 1, 3, 1, 2, 1, 3, 2, 1, 2 }
	local bx = X
	for i = 1, #widths do
		bar(bx, 184, widths[i], 22, T.CLUSTER_BG, 0)
		bx = bx + widths[i] + 3
	end

	return { Root = root, Card = card }
end

return InfoPage 
