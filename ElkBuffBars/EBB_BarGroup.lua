local ELKBUFFBARS, private = ...
local ElkBuffBars = private.addon

local ipairs				= ipairs
local pairs					= pairs

local table_insert			= table.insert
local table_remove			= table.remove
local table_sort			= table.sort

local DATA_DEMO = {
	id				= -1,
	spellid			= -1,
	name			= "Blessing of Demonstration",
	realname		= "Blessing of Demonstration",
	rank			= 23,
	type			= "FAKE",
	realtype		= "FAKE",
	debufftype		= nil,
	expirytime		= 817,
	timemax			= 1200,
	untilcancelled	= nil,
	charges			= 5,
	maxcharges		= 5,
	icon			= [[Interface\Icons\INV_Misc_QuestionMark]],
	ismine			= true,
	casterName		= "Buffbot",
	casterClass		= "PRIEST",
}

local prototype = {}
local prototype_mt = {__index = prototype}

function ElkBuffBars:NewBarGroup()
	local group = setmetatable({}, prototype_mt)

	group.bars = {}
	group.data = {}
	group.frames = {}
	local container = CreateFrame("button", nil, UIParent)
	container:SetFrameStrata("BACKGROUND")
	container:SetMovable(true)
	container:SetClampedToScreen(true)
	group.frames.container = container

	return group
end

function prototype:Reset()
	self.frames.container:ClearAllPoints()
	self.frames.container:Hide()
	for k, v in pairs(self.bars) do
		ElkBuffBars:RecycleBar(v)
		self.bars[k] = nil
	end

	local data = self.data
	for k in pairs(data) do
		data[k] = nil
	end

	self.layout = nil
end

function prototype:GetContainer()
	return self.frames.container
end

function prototype:SetLayout(layout)
	if layout then
		self.layout = layout
	else
		layout = self.layout
		if not layout then
			return
		end
	end
	for _, bar in ipairs(self.bars) do
		bar:UpdateLayout(layout.bars)
	end
	if layout.bars.clickthrough then
		self.frames.container:EnableMouse(false)
	else
		self.frames.container:EnableMouse(true)
	end
	self.frames.container:SetAlpha(layout.alpha)
	self.frames.container:SetScale(layout.scale)
	self:UpdateAnchor()
	self:UpdateBarPositions()
end

function prototype:SetPosition()
	local layout = self.layout
	self.frames.container:ClearAllPoints()
	if layout.stickto then
		local target = ElkBuffBars.bargroups[layout.stickto]:GetContainer()
		if layout.stickmode == "horizontal" then
			-- attach beside the target group (my LEFT edge to their RIGHT edge, or vice versa),
			-- aligned top/middle/bottom via stickvalign, so growth of either group pushes the other sideways.
			local myside = layout.stickside == "RIGHT" and "RIGHT" or "LEFT"
			local otherside = myside == "LEFT" and "RIGHT" or "LEFT"
			local valign = layout.stickvalign or ""
			self.frames.container:SetPoint(valign..myside, target, valign..otherside, 0, 0)
		else
			self.frames.container:SetPoint((layout.growup and "BOTTOM" or "TOP")..(layout.stickside or ""), target, (layout.growup and "TOP" or "BOTTOM")..(layout.stickside or ""), 0, layout.growup and ElkBuffBars.db.profile.groupspacing or -ElkBuffBars.db.profile.groupspacing)
		end
	elseif layout.x and layout.y then
		self.frames.container:SetPoint(layout.growup and "BOTTOMLEFT" or "TOPLEFT", UIParent, "BOTTOMLEFT", layout.x, layout.y)
	else
		self.frames.container:SetPoint("CENTER", UIParent, "CENTER")
		self:ToggleConfigMode(true)
	end
end

local anchor_backdrop = {
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	tile = false, tileSize = 16, edgeSize = 16,
	insets = { left = 5, right =5, top = 5, bottom = 5 },
}
function prototype:ToggleConfigMode(enabled)
	if enabled == nil then
		enabled = not self.layout.configmode
	end
	if enabled then
		self.layout.configmode = true
		self:UpdateAnchor()
	else
		self.layout.configmode = false
		self:UpdateAnchor()
	end
end

function prototype:UpdateAnchor()
	local show = self.layout.anchorshown or self.layout.configmode
	if show then
		if not self.frames.anchor then
			self.frames.anchor = CreateFrame("Button", nil, self.frames.container, BackdropTemplateMixin and "BackdropTemplate")
			self.frames.anchor:SetBackdrop(anchor_backdrop)
			self.frames.anchor:SetHeight(25)
			self.frames.anchortext = self.frames.anchor:CreateFontString(nil, "OVERLAY")
			self.frames.anchortext:SetFontObject(GameFontNormalSmall)
			self.frames.anchortext:ClearAllPoints()
			self.frames.anchortext:SetTextColor(1, 1, 1, 1)
			self.frames.anchortext:SetPoint("CENTER", self.frames.anchor, "CENTER")
			self.frames.anchortext:SetJustifyH("CENTER")
			self.frames.anchortext:SetJustifyV("MIDDLE")

			self.frames.anchor.bargroup = self
			self.frames.anchor:SetScript("OnDragStart", function(this) this.bargroup:StartMoving() end )
			self.frames.anchor:SetScript("OnDragStop", function(this) this.bargroup:StopMoving() end )

			self.frames.anchor:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			self.frames.anchor:SetScript("OnClick", function(this, button) this.bargroup:OnClick(button) end )
		end
		if self.layout.configmode then
			self.frames.anchor:RegisterForDrag("LeftButton")
			if not self.frames.anchorgear_l then
				self.frames.anchorgear_l = self.frames.anchor:CreateTexture()
				self.frames.anchorgear_l:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
				self.frames.anchorgear_l:SetHeight(15)
				self.frames.anchorgear_l:SetWidth(15)
				self.frames.anchorgear_l:SetPoint("TOPLEFT", 5, -5)
			end
			if not self.frames.anchorgear_r then
				self.frames.anchorgear_r = self.frames.anchor:CreateTexture()
				self.frames.anchorgear_r:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
				self.frames.anchorgear_r:SetHeight(15)
				self.frames.anchorgear_r:SetWidth(15)
				self.frames.anchorgear_r:SetPoint("TOPRIGHT", -5, -5)
			end
			self.frames.anchorgear_l:Show()
			self.frames.anchorgear_r:Show()
		else
			self.frames.anchor:RegisterForDrag()
			if self.frames.anchorgear_l then
				self.frames.anchorgear_l:Hide()
			end
			if self.frames.anchorgear_r then
				self.frames.anchorgear_r:Hide()
			end
		end
		self.frames.anchor:SetWidth(self.layout.bars.width)
		self.frames.anchor:SetBackdropColor(self.layout.bars.barcolor[1], self.layout.bars.barcolor[2], self.layout.bars.barcolor[3], .5)
		self:RefreshAnchorVisibility()
	else
		if self.frames.anchor then
			self.frames.anchor:Hide()
		end
	end
	self:UpdateData()
end

-- counts real (non-demo) entries currently in self.data
function prototype:GetRealDataCount()
	local count = 0
	for _, v in ipairs(self.data) do
		if v ~= DATA_DEMO then
			count = count + 1
		end
	end
	return count
end

-- shows/hides the anchor (honoring Hide Anchor When Empty) and refreshes its "(count)" text.
-- Deliberately does NOT call UpdateData/UpdateBars, so this is safe to call from UpdateBars()
-- itself every time the buff count changes, without recursing.
function prototype:RefreshAnchorVisibility()
	local frames = self.frames
	if not frames.anchor then return end
	local count = self:GetRealDataCount()
	local show = (self.layout.anchorshown or self.layout.configmode) and not (self.layout.hideanchorwhenempty and count == 0)
	if show then
		frames.anchor:Show()
		if frames.anchortext then
			frames.anchortext:SetText(self.layout.anchortext.." ("..count..")")
		end
	else
		frames.anchor:Hide()
	end
end

function prototype:StartMoving()
	self.frames.container:StartMoving()
end

function prototype:StopMoving()
	self.frames.container:StopMovingOrSizing()
	self.frames.container:SetUserPlaced(false) -- don't save in frame cache
	if not ElkBuffBars:StickGroup(self) then
		self.layout.x = self.frames.container:GetLeft()
		self.layout.y = self.layout.growup and self.frames.container:GetBottom() or self.frames.container:GetTop()
		self.frames.container:ClearAllPoints()
		self.frames.container:SetPoint(self.layout.growup and "BOTTOMLEFT" or "TOPLEFT", UIParent, "BOTTOMLEFT", self.layout.x, self.layout.y)
	end
end

function prototype:OnClick(button)
	if button == "LeftButton" then
		if IsAltKeyDown() then
			self:ToggleConfigMode()
		end
	elseif button == "RightButton" then
		if (self.layout.configmode) then
			self:ShowMenu()
		end
	end
end

function prototype:ShowMenu()
	-- @Phanx: TODO: menu?
	--Dewdrop:Open(self.frames.anchor, "children", ElkBuffBars:GetGroupOptions(self.layout.id))
	ElkBuffBars:OpenGroupOptions(self.layout.id)
end

-- updates position of bars (+ anchor) inside the container; sets container height
function prototype:UpdateBarPositions()
	local lastframe = nil
	local height = 0
	if self.layout.anchorshown or self.layout.configmode then
		self:UpdateBarPosition(self.frames.anchor, lastframe)
		lastframe = self.frames.anchor
		height = height + 25
	end
	for _, bar in pairs(self.bars) do
		if height > 0 then height = height + self.layout.barspacing end
		self:UpdateBarPosition(bar:GetContainer(), lastframe)
		height = height + self.layout.bars.height
		lastframe = bar:GetContainer()
	end
	if height < 1 then height = 1 end -- add some height for empty groups in order to have them work as relative anchors
	self.frames.container:SetHeight(height)
	self.frames.container:SetWidth(self.layout.bars.width)
end

-- update the position of 'frame'; anchors it to 'relframe' if given
function prototype:UpdateBarPosition(frame, relframe)
	local growup = self.layout.growup
	frame:ClearAllPoints()
	if not relframe then
		frame:SetPoint(growup and "BOTTOM" or "TOP", self.frames.container, growup and "BOTTOM" or "TOP")
	else
		frame:SetPoint(growup and "BOTTOM" or "TOP", relframe, growup and "TOP" or "BOTTOM", 0, growup and self.layout.barspacing or -self.layout.barspacing)
	end
end

local sorting = {
	name = function(a, b)
			return a.name < b.name
		end,
	timeleft = function(a, b)
			if a.untilcancelled then
				if b.untilcancelled then
					return a.name < b.name
				else
					return true
				end
			elseif b.untilcancelled then
				return false
			end
			if a.expirytime < b.expirytime then
				return false
			elseif a.expirytime > b.expirytime then
				return true
			else
				return a.name < b.name
			end
		end,
	timemax = function(a, b)
			if a.untilcancelled then
				if b.untilcancelled then
					return a.name < b.name
				else
					return true
				end
			elseif b.untilcancelled then
				return false
			end
			if a.timemax < b.timemax then
				return false
			elseif a.timemax > b.timemax then
				return true
			else
				return a.name < b.name
			end
		end,
}

local GRACE_PERIOD = 0.3 -- seconds to keep showing a buff after it drops out of a scan, so a
                          -- very short or rapidly-refreshing buff doesn't visibly flicker its
                          -- bar away and back (the group shrinking then growing again)

local function DataKey(data)
	return (data.type or "").."|"..(data.realname or data.name or "").."|"..tostring(data.id or data.spellid or "")
end

local function CopyDataTable(v)
	local copy = {}
	for k, val in pairs(v) do
		copy[k] = val
	end
	return copy
end

-- creates data for which bars will be created
function prototype:UpdateData(updated)
	if updated and not updated[self.layout.target] then return end
	local layout = self.layout
	local data = self.data
	for k in pairs(data) do
		data[k] = nil
	end

	local now = GetTime()
	if not self.gracecache then
		self.gracecache = {}
	end
	local gracecache = self.gracecache
	local seen = {}

	local function collect(v)
		if self:CheckFilter(v) then
			table_insert(data, v)
			local key = DataKey(v)
			seen[key] = true
			gracecache[key] = { data = CopyDataTable(v), lastseen = now }
		end
	end

	for _, v in pairs(ElkBuffBars.buffdata[layout.target]) do
		collect(v)
	end
	for _, v in pairs(ElkBuffBars.debuffdata[layout.target]) do
		collect(v)
	end
	if layout.target == "player" then
		for _, v in pairs(ElkBuffBars.tenchdata) do
			collect(v)
		end
		for _, v in pairs(ElkBuffBars.trackingdata) do
			collect(v)
		end
	end

	-- anything that just vanished from the scan gets a brief grace period showing its last
	-- known state, instead of its bar instantly disappearing (and likely reappearing next scan)
	for key, held in pairs(gracecache) do
		if not seen[key] then
			if now - held.lastseen > GRACE_PERIOD then
				gracecache[key] = nil
			else
				table_insert(data, held.data)
			end
		end
	end

	if self.layout.configmode then
		table_insert(data, DATA_DEMO)
	end
	if sorting[self.layout.sorting] then
		table_sort(data, sorting[self.layout.sorting])
	end
	self:UpdateBars()
end


-- creates bars from data
function prototype:UpdateBars()
	local bars = self.bars

	for i = 1, #self.data do
		if not bars[i] then
			bars[i] = ElkBuffBars:GetBar()
			bars[i]:UpdateLayout(self.layout.bars)
			bars[i]:SetParent(self)
		end
		bars[i]:UpdateData(self.data[i])
	end
	for i = #bars, #self.data + 1, -1 do
		ElkBuffBars:RecycleBar(bars[i])
		bars[i] = nil
	end
	self:UpdateBarPositions()
	for _, bar in pairs(bars) do
		bar:GetContainer():Show()
	end
	self:RefreshAnchorVisibility()
end

-- orders the bars to update the texts shown
function prototype:UpdateText()
	for _, bar in ipairs(self.bars) do
		bar:UpdateText()
	end
end

-- orders the bars to update the time shown
function prototype:UpdateTimeleft()
	for _, bar in ipairs(self.bars) do
		bar:UpdateTimeleft()
	end
end

-- checks for various filter settings
function prototype:CheckFilter(data)
	if not self.layout then
		return false
	end

	local filter = self.layout.filter

	if	   (not filter.type[data.type])																								-- type
		or (filter.selfcast and ((filter.selfcast == "blacklist" and data.ismine) or (filter.selfcast == "whitelist" and not data.ismine)))
		or (not data.untilcancelled and filter.timemax_min and data.timemax < filter.timemax_min)									-- min timemax
		or (not data.untilcancelled and filter.timemax_max and data.timemax > filter.timemax_max)									-- max timemax
		or (filter.untilcancelled and ((filter.untilcancelled == "only" and not data.untilcancelled) or (filter.untilcancelled == "hide" and data.untilcancelled)))
		or (filter.names_include and not (filter.names_include[data.type] and filter.names_include[data.type][data.realname]))		-- show by name
		or (filter.names_exclude and filter.names_exclude[data.type] and filter.names_exclude[data.type][data.realname])			-- hide by name
		or (filter.charges_min and data.charges < filter.charges_min)																-- min charges
		or (filter.charges_max and data.charges > filter.charges_max)																-- max charges
		then return false end

	return true
end

function prototype:RecycleSABs()
	if not InCombatLockdown() then
		for _, v in pairs(self.bars) do
			v:RecycleSAB()
		end
	end
end
