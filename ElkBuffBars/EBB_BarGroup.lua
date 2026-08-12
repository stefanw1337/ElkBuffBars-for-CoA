local ELKBUFFBARS, private = ...
local ElkBuffBars = private.addon
local L = LibStub("AceLocale-3.0"):GetLocale(ELKBUFFBARS)

local ipairs				= ipairs
local pairs					= pairs

local table_insert			= table.insert
local table_remove			= table.remove
local table_sort			= table.sort
local table_concat			= table.concat
local string_format		= string.format

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
	self:UpdateAnnounceButton()
	self:RefreshContainerVisibility()
	self:UpdateBarPositions()
end

-- small always-visible icon (unlike the anchor, which is normally hidden outside config mode)
-- pinned to the top-right corner of the bar group, so "announce missing group buffs" stays one
-- click away mid-raid without needing to open config mode or the options window. Only shown
-- while Show Missing is on for this bar group, since that's the whole feature this builds on.
function prototype:UpdateAnnounceButton()
	local show = self.layout.filter and self.layout.filter.showmissing
	if show then
		if not self.frames.announcebutton then
			local btn = CreateFrame("Button", nil, self.frames.container)
			btn:SetWidth(14)
			btn:SetHeight(14)
			btn:SetPoint("TOPRIGHT", self.frames.container, "TOPRIGHT", 14, 14)
			btn:SetFrameLevel(self.frames.container:GetFrameLevel() + 5)
			local tex = btn:CreateTexture(nil, "ARTWORK")
			tex:SetAllPoints(btn)
			tex:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
			tex:SetVertexColor(1, 0.82, 0, 1) -- gold, to stand apart from the config-mode gear icons
			btn.texture = tex
			btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			btn.bargroup = self
			btn:SetScript("OnClick", function(this) this.bargroup:AnnounceMissingGroupBuffs() end)
			btn:SetScript("OnEnter", function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L["ANNOUNCE_BUTTON_TOOLTIP"])
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
			self.frames.announcebutton = btn
		end
		self.frames.announcebutton:Show()
	elseif self.frames.announcebutton then
		self.frames.announcebutton:Hide()
	end
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

-- counts real (non-demo) entries currently in self.data, split into total and how many of
-- those are "missing" (Show Missing placeholders) rather than actually active
function prototype:GetRealDataCount()
	local total, missing = 0, 0
	for _, v in ipairs(self.data) do
		if v ~= DATA_DEMO then
			total = total + 1
			if v.missing then
				missing = missing + 1
			end
		end
	end
	return total, missing
end

-- shows/hides the anchor (honoring Hide Anchor When Empty) and refreshes its "(count)" text.
-- Deliberately does NOT call UpdateData/UpdateBars, so this is safe to call from UpdateBars()
-- itself every time the buff count changes, without recursing.
function prototype:RefreshAnchorVisibility()
	local frames = self.frames
	if not frames.anchor then return end
	local total, missing = self:GetRealDataCount()
	local show = (self.layout.anchorshown or self.layout.configmode) and not (self.layout.hideanchorwhenempty and total == 0)
	if show then
		frames.anchor:Show()
		if frames.anchortext then
			-- if any Show Missing placeholders are present, show "active/total" (e.g. 6/10)
			-- instead of just the total, so missing ones don't inflate the count
			local counttext = (missing > 0) and ((total - missing).."/"..total) or tostring(total)
			frames.anchortext:SetText(self.layout.anchortext.." ("..counttext..")")
		end
	else
		frames.anchor:Hide()
	end
end

-- hides/shows the WHOLE group (not just the anchor) per three independent opt-in toggles:
-- "Hide Group In Combat" (declutter mid-fight), "Hide Group When No Missing Bars" (only pop up
-- once Show Missing actually has something red to flag), and "Hide Group When All Bars Missing"
-- (hide if EVERY tracked name is absent -- e.g. a 10-slot Ascension world buff tracker with
-- none of them up isn't useful as a wall of red, so hide the whole thing rather than show it).
-- Any single reason is enough to hide; all applicable ones must say "show" for the group to
-- show -- so hidewhennomissing + hidewhenallmissing together means "only show when there's a
-- genuine mix of some active and some missing." Safe to call anytime -- doesn't touch data or
-- recurse into UpdateData.
function prototype:RefreshContainerVisibility()
	local layout = self.layout
	if not layout then return end

	if layout.hideincombat and InCombatLockdown() then
		self.frames.container:Hide()
		return
	end

	if layout.hidewhennomissing or layout.hidewhenallmissing then
		local total, missing = self:GetRealDataCount()
		if layout.hidewhennomissing and missing == 0 then
			self.frames.container:Hide()
			return
		end
		if layout.hidewhenallmissing and total > 0 and missing == total then
			self.frames.container:Hide()
			return
		end
	end

	self.frames.container:Show()
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

-- scans your current party/raid (excluding yourself) and returns a set of the localized
-- class names present, e.g. { ["Templar"] = true, ["Witch Hunter"] = true }. Works for
-- Ascension's custom classes too, since UnitClass() reports the custom name directly.
-- Empty (no group, or solo) when not grouped, which is what keeps Class Watch quiet while
-- soloing. Also registers every class seen into the account-wide known-classes list (so the
-- Class Watch checklist grows on its own -- you never have to type a class name anywhere).
local function GetGroupPresentClasses()
	local classes = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid"..i
			if not UnitIsUnit(unit, "player") then
				local localized = UnitClass(unit)
				if localized then
					classes[localized] = true
					ElkBuffBars:AddKnownClass(localized)
				end
			end
		end
	elseif IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do
			local localized = UnitClass("party"..i)
			if localized then
				classes[localized] = true
				ElkBuffBars:AddKnownClass(localized)
			end
		end
	end
	return classes
end

-- reads the checkbox-based Class Watch list (Filter tab): filter.classestracked is the set of
-- classes you've checked for this bar group, and filter.classbuffs[classname] holds the
-- buff(s) that class can give you. Only returns classes that are both checked AND actually
-- present in your group right now (per presentClasses); having ANY ONE of a class's checked
-- names active satisfies it for Show Missing purposes (e.g. two class buffs that can't both
-- be up at once).
local function GetClassWatchGroups(filter, presentClasses)
	local groups = {}
	if not filter.classestracked or not filter.classbuffs then return groups end
	for classname in pairs(filter.classestracked) do
		if presentClasses[classname] and filter.classbuffs[classname] then
			local members = {}
			for auratype, names in pairs(filter.classbuffs[classname]) do
				for name in pairs(names) do
					table_insert(members, { type = auratype, name = name })
				end
			end
			if #members > 0 then
				table_insert(groups, { classname = classname, members = members })
			end
		end
	end
	return groups
end

-- reads the checkbox-based "Self Buff Alternatives" (Filter > My Self Buffs > Self Buff
-- Alternatives): flattens each numbered set's checked names (across all types) into a single
-- alternative-set, plus that set's "How Many Needed" count (default 1), "Only In Spec"
-- restriction (nil = any spec), "Only Needed While Grouped" flag, and "Shared With Same-Class
-- Allies" flag. Having at least `count` distinct names active satisfies that whole set for
-- Show Missing purposes -- by default never gated by group presence, since these are self
-- buffs (though a name in the set can still be given to you by someone else -- the check only
-- cares whether the name is active, not who cast it, which is what makes a count > 1 useful
-- for "my own plus a different one from a groupmate"). Spec-restricted sets are skipped
-- entirely while you're in a different talent spec, and "Only Needed While Grouped" sets are
-- skipped entirely while solo (not gated to any specific class -- just grouped or not). The
-- "shared" flag doesn't skip the set -- it's read by UpdateData below, which additionally
-- checks party/raid members of your own class for each not-yet-active name before deciding
-- it's genuinely missing.
local function GetSelfBuffAltGroups(filter)
	local groups = {}
	if not filter.selfbuffaltgroups then return groups end
	-- keyed by class first now (see SetSelfBuffAltGroupFilter etc. in ElkBuffBars.lua) -- only
	-- ever read the current character's own class's slots, so a different class's alt-set
	-- selections sharing this same profile never show up as tracked/missing here.
	local myClass = (UnitClass("player"))
	local byclass = filter.selfbuffaltgroups[myClass]
	if not byclass then return groups end
	local activespec = GetActiveTalentGroup and GetActiveTalentGroup() or nil
	local grouped = IsInGroup() or IsInRaid()
	for _, byname in pairs(byclass) do
		if (not byname.spec or byname.spec == activespec) and (not byname.onlygrouped or grouped) then
			local members = {}
			for auratype, names in pairs(byname) do
				if auratype ~= "count" and auratype ~= "spec" and auratype ~= "onlygrouped" and auratype ~= "shared" then
					for name in pairs(names) do
						table_insert(members, { type = auratype, name = name })
					end
				end
			end
			if #members > 0 then
				table_insert(groups, { members = members, count = byname.count or 1, shared = byname.shared })
			end
		end
	end
	return groups
end

-- checks whether "name" (a BUFF or DEBUFF -- TENCH/TRACKING aren't meaningfully checkable on
-- other units) is currently active on any OTHER party/raid member who shares your own class.
-- Used by "Shared With Same-Class Allies" alt-set slots: lets an either-or set count as
-- covered when a different member of your class already has one of its flavors up, instead of
-- only ever checking yourself.
local function IsNameActiveOnClassAlly(auratype, name, myClass)
	if auratype ~= "BUFF" and auratype ~= "DEBUFF" then
		return false
	end
	local filterType = (auratype == "DEBUFF") and "HARMFUL" or "HELPFUL"
	local function unitHasIt(unit)
		if UnitClass(unit) ~= myClass then
			return false
		end
		local i = 1
		while true do
			local auraName = UnitAura(unit, i, filterType)
			if not auraName then
				return false
			end
			if auraName == name then
				return true
			end
			i = i + 1
		end
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = "raid"..i
			if not UnitIsUnit(unit, "player") and unitHasIt(unit) then
				return true
			end
		end
	elseif IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do
			if unitHasIt("party"..i) then
				return true
			end
		end
	end
	return false
end

-- checks whether "name" (a BUFF or DEBUFF) is currently active on the given unit, regardless
-- of who cast it or what class the unit is -- unlike IsNameActiveOnClassAlly above, this isn't
-- restricted to a particular class, since AnnounceMissingGroupBuffs below checks every raid/
-- party member against THEIR OWN class's buffs, not just allies who share your class.
local function UnitHasAuraName(unit, auratype, name)
	if auratype ~= "BUFF" and auratype ~= "DEBUFF" then
		return false
	end
	local filterType = (auratype == "DEBUFF") and "HARMFUL" or "HELPFUL"
	local i = 1
	while true do
		local auraName = UnitAura(unit, i, filterType)
		if not auraName then
			return false
		end
		if auraName == name then
			return true
		end
		i = i + 1
	end
end

-- every unit in your current raid/party (including yourself), with their class (localized
-- name, matching how buffclasses/classbuffs key everything else -- Ascension's custom classes
-- don't have a fixed English token) and, in a raid, their subgroup number (1-8; nil in a
-- regular party, which has no subgroup concept). Empty if you're not grouped at all.
local function GetGroupRoster()
	local roster = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup = GetRaidRosterInfo(i)
			local unit = "raid"..i
			local class = name and UnitClass(unit)
			if name and class then
				table_insert(roster, { unit = unit, name = name, class = class, subgroup = subgroup })
			end
		end
	elseif IsInGroup() then
		local pname, pclass = UnitName("player"), UnitClass("player")
		if pname and pclass then
			table_insert(roster, { unit = "player", name = pname, class = pclass })
		end
		for i = 1, GetNumGroupMembers() - 1 do
			local unit = "party"..i
			local name, class = UnitName(unit), UnitClass(unit)
			if name and class then
				table_insert(roster, { unit = unit, name = name, class = class })
			end
		end
	end
	return roster
end

-- looks up a display icon for a name that isn't currently active: prefers the icon
-- remembered from the last time it WAS active (persists across sessions), then falls back to
-- a name-based spell lookup, trying each candidate name in turn (useful for either-or groups)
local function FindMissingIcon(auratype, names)
	for _, name in ipairs(names) do
		local cached = ElkBuffBars.db.global.iconcache[auratype.."|"..name]
		if cached then return cached end
	end
	for _, name in ipairs(names) do
		local _, _, specificicon = GetSpellInfo(name)
		if specificicon then return specificicon end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- checks EVERY raid/party member (including yourself) against their OWN class's Group Watcher
-- checklist (this bar group's filter.classbuffs), and reports anyone missing one of their own
-- class's checked buffs to raid/party chat, one line per person, e.g. "Missing in group 3 from
-- Templar Bob: Gift of Zeal". This only knows about a class if you've checked at least one buff
-- for it under this bar group's Group Watcher tab (which happens automatically the moment you
-- check anything in My Self Buffs for that class -- see SetSelfBuffFilter in ElkBuffBars.lua).
function prototype:AnnounceMissingGroupBuffs()
	local filter = self.layout.filter
	local inRaid = IsInRaid()
	local inParty = not inRaid and IsInGroup()
	if not inRaid and not inParty then
		ElkBuffBars:Print(L["ANNOUNCE_NOT_GROUPED"])
		return
	end
	if not filter.classbuffs then
		ElkBuffBars:Print(L["ANNOUNCE_NOTHING_CONFIGURED"])
		return
	end

	local lines = {}
	for _, member in ipairs(GetGroupRoster()) do
		local classbuffs = filter.classbuffs[member.class]
		if classbuffs then
			local missingNames = {}
			for auratype, names in pairs(classbuffs) do
				for name in pairs(names) do
					if not UnitHasAuraName(member.unit, auratype, name) then
						table_insert(missingNames, name)
					end
				end
			end
			if #missingNames > 0 then
				table_sort(missingNames)
				local prefix = member.subgroup
					and string_format(L["ANNOUNCE_LINE_RAID"], member.subgroup, member.class, member.name)
					or string_format(L["ANNOUNCE_LINE_PARTY"], member.class, member.name)
				table_insert(lines, prefix..table_concat(missingNames, ", "))
			end
		end
	end

	if #lines == 0 then
		ElkBuffBars:Print(L["ANNOUNCE_ALL_GOOD"])
		return
	end

	-- batch multiple people's lines into messages under ~200 characters (chat has a hard cap
	-- around 255), and stagger sending them a fraction of a second apart so a big raid with
	-- lots of missing buffs doesn't trip the client's outgoing chat throttle.
	local channel = inRaid and "RAID" or "PARTY"
	local batches, current = {}, ""
	for _, line in ipairs(lines) do
		if current == "" then
			current = line
		elseif #current + 3 + #line <= 200 then
			current = current.." | "..line
		else
			table_insert(batches, current)
			current = line
		end
	end
	if current ~= "" then
		table_insert(batches, current)
	end
	for i, msg in ipairs(batches) do
		ElkBuffBars:ScheduleTimer(function() SendChatMessage(msg, channel) end, (i - 1) * 0.3)
	end
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
			-- remember this name's real icon (persists across sessions) for Show Missing to
			-- reuse later, since a placeholder for a buff that isn't active has no live icon
			if v.icon then
				ElkBuffBars.db.global.iconcache[(v.realtype or v.type or "").."|"..(v.realname or v.name or "")] = v.icon
			end
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

	-- Alert Unwanted: normally a Black List name is just silently excluded by CheckFilter.
	-- If this is on, scan the raw (pre-filter) scan data directly instead, so a blacklisted
	-- name that IS currently active gets shown anyway, tagged so it renders as a warning
	-- rather than being hidden.
	if layout.filter.alertblacklisted and layout.filter.names_exclude then
		local function scanForBlacklistAlert(list, auratype)
			if not list or not layout.filter.type[auratype] then return end
			local excluded = layout.filter.names_exclude[auratype]
			if not excluded then return end
			for _, v in pairs(list) do
				if excluded[v.realname] then
					local alertdt = CopyDataTable(v)
					alertdt.blacklisted = true
					table_insert(data, alertdt)
				end
			end
		end
		scanForBlacklistAlert(ElkBuffBars.buffdata[layout.target], "BUFF")
		scanForBlacklistAlert(ElkBuffBars.debuffdata[layout.target], "DEBUFF")
		if layout.target == "player" then
			scanForBlacklistAlert(ElkBuffBars.tenchdata, "TENCH")
			scanForBlacklistAlert(ElkBuffBars.trackingdata, "TRACKING")
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

	if sorting[self.layout.sorting] then
		table_sort(data, sorting[self.layout.sorting])
	end

	-- Show Missing: add a placeholder (red, full) bar for anything that's supposed to be
	-- tracked but isn't currently present, so it's obvious at a glance what's still missing
	-- (world buffs not yet picked up, a class buff nobody's cast, etc.) -- added after the
	-- normal sort (and sorted alphabetically among themselves) so these always land at the
	-- very end, no matter the group's sort mode. Three sources feed this list: My Self Buffs
	-- (buffs only you can give yourself -- always checked, group composition is irrelevant),
	-- Class Watch (Filter > Class Watch -- only checked while that class is actually present
	-- in your party/raid; ANY ONE of a checked class's buff names counts as satisfied), and
	-- individual White List names.
	if layout.filter.showmissing then
		local present = {}
		for _, v in ipairs(data) do
			present[(v.realtype or v.type or "").."|"..(v.realname or v.name or "")] = true
		end

		local missing = {}
		local handled = {} -- "TYPE|name" claimed by a Self Buff Alternatives set, Self Buffs,
		                    -- or Class Watch, so the individual White List check below skips it

		local myClass = (UnitClass("player"))
		local grouped = IsInGroup() or IsInRaid()
		for _, altgroup in ipairs(GetSelfBuffAltGroups(layout.filter)) do
			local activemembers, remaining = {}, {}
			local activeCount = 0
			for _, m in ipairs(altgroup.members) do
				if layout.filter.type[m.type] then
					table_insert(activemembers, m)
					handled[m.type.."|"..m.name] = true
					if present[m.type.."|"..m.name] then
						activeCount = activeCount + 1
					elseif altgroup.shared and grouped and IsNameActiveOnClassAlly(m.type, m.name, myClass) then
						-- another member of your own class already has this flavor up --
						-- counts toward the set same as if you had it yourself, and doesn't
						-- get listed as still-needed below
						activeCount = activeCount + 1
					else
						table_insert(remaining, m)
					end
				end
			end
			if activeCount < altgroup.count and #activemembers > 0 then
				-- only name the ones not yet active as candidates for the remaining need
				-- (falls back to all of them if, oddly, every checked name is somehow both
				-- active and still short of count -- shouldn't normally happen)
				local candidates = (#remaining > 0) and remaining or activemembers
				local labels, lookupnames = {}, {}
				for _, m in ipairs(candidates) do
					table_insert(labels, m.name)
					table_insert(lookupnames, m.name)
				end
				table_insert(missing, { auratype = candidates[1].type, name = table.concat(labels, " / "), lookupnames = lookupnames })
			end
		end

		-- keyed by class first now -- only ever consult the current character's own class's
		-- self buffs, so a different class's selections sharing this profile never show up as
		-- tracked/missing here (see SetSelfBuffFilter in ElkBuffBars.lua).
		local selfbuffsForClass = layout.filter.selfbuffs and layout.filter.selfbuffs[myClass]
		if selfbuffsForClass then
			for auratype, names in pairs(selfbuffsForClass) do
				if layout.filter.type[auratype] then
					for name in pairs(names) do
						if not handled[auratype.."|"..name] then
							handled[auratype.."|"..name] = true
							if not present[auratype.."|"..name] then
								table_insert(missing, { auratype = auratype, name = name, lookupnames = { name } })
							end
						end
					end
				end
			end
		end

		local presentClasses = GetGroupPresentClasses()
		for _, slotgroup in ipairs(GetClassWatchGroups(layout.filter, presentClasses)) do
			local satisfied = false
			local activemembers = {}
			for _, m in ipairs(slotgroup.members) do
				if layout.filter.type[m.type] then
					table_insert(activemembers, m)
					handled[m.type.."|"..m.name] = true
					if present[m.type.."|"..m.name] then
						satisfied = true
					end
				end
			end
			if not satisfied and #activemembers > 0 then
				local labels, lookupnames = {}, {}
				for _, m in ipairs(activemembers) do
					table_insert(labels, m.name)
					table_insert(lookupnames, m.name)
				end
				table_insert(missing, { auratype = activemembers[1].type, name = slotgroup.classname..": "..table.concat(labels, " / "), lookupnames = lookupnames })
			end
		end

		if layout.filter.names_include then
			for auratype, names in pairs(layout.filter.names_include) do
				if layout.filter.type[auratype] then
					local excluded = layout.filter.names_exclude and layout.filter.names_exclude[auratype]
					for name in pairs(names) do
						if not handled[auratype.."|"..name] and not present[auratype.."|"..name] and not (excluded and excluded[name]) then
							table_insert(missing, { auratype = auratype, name = name, lookupnames = { name } })
						end
					end
				end
			end
		end

		table_sort(missing, function(a, b) return a.name < b.name end)
		for _, entry in ipairs(missing) do
			local auratype, name = entry.auratype, entry.name
			table_insert(data, {
				id				= name,
				spellid			= nil,
				name			= (ElkBuffBars.db.profile.nameoverride[auratype] and ElkBuffBars.db.profile.nameoverride[auratype][name]) or name,
				realname		= name,
				rank			= nil,
				type			= auratype,
				realtype		= auratype,
				debufftype		= nil,
				expirytime		= nil,
				timemax			= 0,
				timeMod			= 0,
				untilcancelled	= true,
				charges			= 0,
				maxcharges		= nil,
				icon			= FindMissingIcon(auratype, entry.lookupnames),
				ismine			= true,
				casterName		= UNKNOWN,
				casterClass		= "",
				canStealOrPurge	= false,
				missing			= true,
			})
		end
	end

	if self.layout.configmode then
		table_insert(data, DATA_DEMO)
	end
	self:UpdateAnnounceButton()
	self:RefreshContainerVisibility()
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
		or (filter.names_include and filter.whitelistisfilter and not (filter.names_include[data.type] and filter.names_include[data.type][data.realname]))		-- show by name (unless White List is set to only feed Show Missing, not restrict display)
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
