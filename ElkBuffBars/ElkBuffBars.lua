local ELKBUFFBARS, private = ...

------------------------------------------------------------------------
-- Libraries:

local ACCommand = LibStub("AceConfigCmd-3.0")
local ACDialog  = LibStub("AceConfigDialog-3.0")
local LDBIcon   = LibStub("LibDBIcon-1.0")
local LibQTip   = LibStub("LibQTip-1.0")
local LSM       = LibStub("LibSharedMedia-3.0")

local LSM_font      = LSM:HashTable("font")
local LSM_statusbar = LSM:HashTable("statusbar")

------------------------------------------------------------------------
-- Upvalues:

local ipairs            = ipairs
local next              = next
local pairs             = pairs
local select            = select
local tonumber          = tonumber
local tostring          = tostring
local type              = type
local unpack            = unpack

local math_abs          = math.abs
local math_min          = math.min

local string_find       = string.find
local string_gmatch     = string.gmatch
local string_gsub       = string.gsub
local string_match      = string.match
local string_trim       = string.trim
local string_utf8sub    = string.utf8sub

local table_concat      = table.concat
local table_insert      = table.insert
local table_remove      = table.remove
local table_sort        = table.sort
local table_wipe        = table.wipe

local GetAddOnMetadata          = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata -- namespaced since 10.1.0
local GetInventoryItemLink      = GetInventoryItemLink
local GetInventoryItemTexture   = GetInventoryItemTexture
local GetInventorySlotInfo      = GetInventorySlotInfo
local GetItemInfo               = GetItemInfo
local GetWeaponEnchantInfo      = GetWeaponEnchantInfo

local UnitAura_legacy = function(unitToken, index, filter)
    local auraData = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter);
    if not auraData then
        return nil;
    end

    return AuraUtil.UnpackAuraData(auraData);
end
local UnitAura                  = C_UnitAuras and UnitAura_legacy or UnitAura -- struct since 10.2.5

local isTrackingDisabled = (C_GameModeManager and C_GameModeManager.IsFeatureEnabled and not C_GameModeManager.IsFeatureEnabled(Enum.GameModeFeatureSetting.InGameTracking))
                        or (C_GameRules and C_GameRules.IsGameRuleActive and C_GameRules.IsGameRuleActive(Enum.GameRule.IngameTrackingDisabled))

------------------------------------------------------------------------
-- Localization:

local L = LibStub("AceLocale-3.0"):GetLocale(ELKBUFFBARS)

------------------------------------------------------------------------
-- Addon:

local ElkBuffBars = LibStub("AceAddon-3.0"):NewAddon(ELKBUFFBARS, "AceBucket-3.0", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
_G.ElkBuffBars = ElkBuffBars
private.addon = ElkBuffBars
-- @Phanx: TODO: is AceConsole needed?

-- ElkBuffBars.debugFrame = ChatFrame4
-- ElkBuffBars:SetDebugging(true)

function ElkBuffBars:AddDefaultBargroups()
    table_insert(self.db.profile.bargroups, {
        bars = {
            barcolor = {0.3, 0.5, 1, 0.8}, -- <color set>
            barbgcolor = {0, 0.5, 1, 0.3}, -- <color set>
        },
        filter = {
            type = {
                BUFF = true,
            }
        },
        configmode = true,    -- true, false
        anchortext = "BUFFS", -- <string>
        anchorshown = false,  -- true, false
    })
    table_insert(self.db.profile.bargroups, {
        bars = {
            barcolor = {1, 0, 0, 0.8},   -- <color set>
            barbgcolor = {1, 0, 0, 0.3}, -- <color set>
        },
        filter = {
            type = {
                DEBUFF = true,
            }
        },
        configmode = false,     -- true, false
        anchortext = "DEBUFFS", -- <string>
        anchorshown = false,    -- true, false
        stickto = 1,            -- bargroup id
        stickside = "",         -- "LEFT", "RIGHT", ""
    })
    table_insert(self.db.profile.bargroups, {
        bars = {
            barcolor = {0.5, 0, 0.5, 0.8},   -- <color set>
            barbgcolor = {0.5, 0, 0.5, 0.3}, -- <color set>
        },
        filter = {
            type = {
                TENCH = true,
            }
        },
        configmode = false,   -- true, false
        anchortext = "TENCH", -- <string>
        anchorshown = false,  -- true, false
        stickto = 2,          -- bargroup id
        stickside = "",       -- "LEFT", "RIGHT", ""
    })
end

local STICKTO_AREA = 15 -- was 25; repeatedly reported as snapping too eagerly

-- Ascension (and other Classic/Wrath-based clients) don't define LE_EXPANSION_LEVEL_CURRENT
-- or the other LE_EXPANSION_* constants introduced by later retail clients, which caused
-- "attempt to compare nil with number" here and in the two spots below. Default to Wrath of
-- the Lich King (2) to match this addon's Interface: 30300 target so the feature checks
-- behave the same as they would on a real 3.3.5 client.
local CURRENT_EXPANSION_LEVEL = LE_EXPANSION_LEVEL_CURRENT or 2

-- Blizzard's UnitAura() used to return a "rank" string as its 2nd value (name, rank, icon,
-- count, ...); that field was dropped everywhere (retail and modern Classic clients alike)
-- years ago, and this addon was written assuming the newer, rank-less signature. Ascension's
-- client is based on the original pre-refactor 3.3.5 client, so it still returns "rank",
-- which silently shifted every field after it by one (count ended up holding the icon path,
-- etc.) -- causing "attempt to compare number with string" and buffs never actually showing.
local UNITAURA_HAS_RANK = WOW_PROJECT_ID == nil

local TENCH_INVENTORYSLOT = {
    [1] = GetInventorySlotInfo("MainHandSlot"),
    [2] = GetInventorySlotInfo("SecondaryHandSlot"),
}
if CURRENT_EXPANSION_LEVEL < (LE_EXPANSION_MISTS_OF_PANDARIA or 4) then -- @todo remove hardcoded value once in Classic
    -- RangedSlot removed in MoP
    TENCH_INVENTORYSLOT[3] = GetInventorySlotInfo("RangedSlot")
end

local scan_happened = {}

local AO_buffsettings
local AO_groupsettings

do
    local jointable = {}
    ElkBuffBars.ShortName = setmetatable({}, { __index = function(self, key)
        local name = key
        name = string_gsub(name, "%b()", "")
        name = string_gsub(name, "([%-%:%?%!])", " %1 ")
        for word in string_gmatch(name, "([^ ]+)") do
            jointable[#jointable + 1] = string_utf8sub(word, 1, 1)
        end
        local shortname = table_concat(jointable)
        table_wipe(jointable)
        self[key] = shortname
        return shortname
    end })
end

------------------------------------------------------------------------
-- Broker icon

local function do_OnEnter(frame)
    local tooltip = LibQTip:Acquire(ELKBUFFBARS)
    tooltip:SmartAnchorTo(frame)
    tooltip:SetAutoHideDelay(0.1, frame)
    tooltip:EnableMouse(true)
    ElkBuffBars:UpdateTooltip()
    tooltip:Show()
end

local function do_OnLeave()
    -- empty dummy
end

local function do_OnClick(frame, button)
    if button == "RightButton" then
        ElkBuffBars:ToggleOptionsWindow()
    else
        if not ElkBuffBars.bargroups[1] then return end -- @Phanx: probably unnecessary but better safe than sorry
        local enable = not ElkBuffBars.bargroups[1].layout.configmode
        for _, bg in ipairs(ElkBuffBars.bargroups) do
            bg:ToggleConfigMode(enable)
        end
        ElkBuffBars:UpdateTooltip()
    end
end

local function tooltip_line_OnMouseUp(frame, groupIndex, button)
    ElkBuffBars.bargroups[groupIndex]:ToggleConfigMode()
    ElkBuffBars:UpdateTooltip()
end

function ElkBuffBars:UpdateTooltip()
    if not LibQTip:IsAcquired(ELKBUFFBARS) then
        return
    end
    local tooltip = LibQTip:Acquire(ELKBUFFBARS)
    tooltip:Clear()
    tooltip:SetColumnLayout(2,"LEFT", "RIGHT")

    local line = tooltip:AddHeader()
    tooltip:SetCell(line, 1, "|cfffed100Elk|cffffffffBuffBars", nil, "CENTER", 2)
    line = tooltip:AddLine()
    tooltip:SetCell(line, 1, L["TOOLTIP_BARGROUP"])
    tooltip:SetCell(line, 2, L["TOOLTIP_TYPE"])
    line = tooltip:AddSeparator()

    for i, group in ipairs(ElkBuffBars.bargroups) do
        line = tooltip:AddLine()
        tooltip:SetCell(line, 1, format("%s%d. %s", group.layout.configmode and "|cfffed100" or "|cffffffff", i, group.layout.anchortext or UNKNOWN))
        tooltip:SetCell(line, 2, group.layout.target)
        tooltip:SetLineScript(line, "OnMouseUp", tooltip_line_OnMouseUp, i)
    end

    line = tooltip:AddSeparator()
    line = tooltip:AddLine()
    tooltip:SetCell(line, 1, "|cfffed100"..L["TOOLTIP_CLICK_CONFIGMODE"], nil, nil, 2)
    line = tooltip:AddLine()
    tooltip:SetCell(line, 1, "|cfffed100"..L["TOOLTIP_RIGHTCLICK_OPTIONS"], nil, nil, 2)

    tooltip:UpdateScrolling()
end

-- -----

function ElkBuffBars:OnInitialize()
    self.dataObject = LibStub("LibDataBroker-1.1"):NewDataObject(ELKBUFFBARS, {
        type = "launcher",
        icon = "Interface\\AddOns\\"..ELKBUFFBARS.."\\icon", -- icon by Jakobud @ wowace forums
        label = GetAddOnMetadata(ELKBUFFBARS, "Title"),
        OnEnter = do_OnEnter,
        OnLeave = do_OnLeave,
        OnClick = do_OnClick,
    })

    self.db = LibStub("AceDB-3.0"):New("ElkBuffBarsDB", {
        profile = {
            bargroups = {},
            groupspacing = 10,
            hidebuffframe = true,
            hidetenchframe = true,
            hidetrackingframe = false,
            hidevanitybuffs = false,
            nameoverride = {
                BUFF = {},
                DEBUFF = {},
                TENCH = {},
                TRACKING = {},
            },
            typeoverride = {
                BUFF = {},
                DEBUFF = {},
                TENCH = {},
                TRACKING = {},
            },
            minimap = {}, -- for LibDBIcon-1.0
        },
        global = {
            maxtimes = {
                BUFF = {},
                DEBUFF = {},
                TENCH = {},
            },
            maxcharges = {
                BUFF = {},
                DEBUFF = {},
                TENCH = {},
            },
            iconcache = {},
            knownclasses = {}, -- every real/custom class name ever seen (your own alts, plus
                                -- anyone you've grouped with) -- account-wide, feeds the Class
                                -- Watch checklist so class names are always picked, never typed
            buffclasses = { -- name -> {class = true, ...}, per auratype -- account-wide, built
                BUFF = {},    -- automatically as buffs are observed on units of a known class.
                DEBUFF = {},  -- Used to narrow "My Self Buffs"/Alt Sets/Class Watch checklists
                TENCH = {},   -- down to buffs actually relevant to a given class, instead of
                TRACKING = {}, -- showing every buff ever seen on any alt or groupmate.
            },
            buffspellids = { -- name -> spellID, per auratype -- account-wide, learned the same
                BUFF = {},    -- way as buffclasses. Used to show the buff's real tooltip (icon,
                DEBUFF = {},  -- description, everything) on mouseover in the filter checklists,
                TENCH = {},   -- via GameTooltip's native "spell:<id>" hyperlink support.
                TRACKING = {},
            },
        },
    }, true) -- `true` here is AceDB-3.0's built-in "one profile per character" flag -- any
             -- character that has NEVER logged in with this addon before automatically gets
             -- its own profile, keyed to its name. Omitting this argument (as this file
             -- previously did) makes every such character share the one literal profile
             -- named "Default" instead -- that was the actual cause of buffs/filters
             -- bleeding across characters (Witch Hunter -> Primalist -> Starcaller, etc.):
             -- the earlier comment here had AceDB-3.0's own documented behavior backwards.
             -- Characters that already got stuck on "Default" before this fix (anything
             -- you've already logged into) will stay on it until you manually give them
             -- their own profile via the Profiles tab -- this fix only protects brand-new
             -- characters going forward.

    -- seed the Class Watch checklist from anything already known from past sessions, then
    -- register this character's own class immediately (so at minimum, every alt you log into
    -- becomes pickable right away, even before you've grouped with anyone) -- called as
    -- self: methods (resolved at runtime) since they're defined further down this same file
    self:SeedKnownClasses()
    self:AddKnownClass((UnitClass("player")))

    -- Clear out old data
    local build = select(2, GetBuildInfo())
    if true or not self.db.global.build or self.db.global.build ~= build then
        self.db.global.build = build
        for _, t in pairs(self.db.global.maxtimes) do table_wipe(t) end
        for _, t in pairs(self.db.global.maxcharges) do table_wipe(t) end
    end

    -- Register for profile related callbacks
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileEnable")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileEnable")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileEnable")
    self.db.RegisterCallback(self, "OnProfileShutdown", "OnProfileDisable")

    -- Generate options table
    self.options = self:GetOptions()
    AO_buffsettings = self.options.args.buffsettings
    AO_groupsettings = self.options.args.groupsettings.args

    -- Add profile options
    self.options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    self.options.args.profile.order = -1 -- show it last

        -- Add dual spec support
    local LibDualSpec = LibStub("LibDualSpec-1.0", true)
    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, ELKBUFFBARS)
        LibDualSpec:EnhanceOptions(self.options.args.profile, self.db)
    end

    -- Register with AceConfig
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(ELKBUFFBARS, self.options)

    -- Register with LibDBIcon
    LDBIcon:Register(ELKBUFFBARS, self.dataObject, self.db.profile.minimap)

    -- Register a slash command
    self:RegisterChatCommand("ebb", function(input)
        if not input or string_trim(input) == "" or strlower(string_trim(input)) == "config" then
            self:ToggleOptionsWindow()
        else
            ACCommand.HandleCommand(self, "ebb", ELKBUFFBARS, input)
        end
    end)
end

-- re-checks visibility on every bar group that has "Hide Unless Something's About To Expire"
-- turned on. Only these groups need it -- everyone else's visibility is already fully driven
-- by aura/combat events, no polling required. See UpdateSoonToExpireTimer below for what
-- starts and stops this.
-- re-applies SetPosition() to every group that's stuck to another group. Called whenever any
-- group's shown/hidden state actually flips (see RefreshContainerVisibility in
-- EBB_BarGroup.lua), so a group stuck to whatever just changed re-anchors to the nearest now-
-- visible ancestor. This just re-runs SetPosition on every stuck group rather than working out
-- exactly which ones are downstream of the group that changed -- SetPosition is cheap (a
-- handful of SetPoint calls) and GetStickTarget already re-walks each group's own chain fresh,
-- so there's no need for that bookkeeping.
function ElkBuffBars:RefreshStuckPositions()
    for _, bg in pairs(self.bargroups) do
        if bg.layout.stickto then
            bg:SetPosition()
        end
    end
end

function ElkBuffBars:RefreshSoonToExpireGroups()
    for _, bg in pairs(self.bargroups) do
        if bg.layout.hideunlesssoon then
            bg:RefreshContainerVisibility()
        end
    end
end

-- starts a lightweight once-a-second timer for RefreshSoonToExpireGroups above if ANY bar
-- group currently has "Hide Unless Something's About To Expire" enabled, and stops it again if
-- none do -- so groups not using the option pay zero ongoing cost (same reasoning as the old
-- always-on self.timer_UpdateGroups this replaces, which polled every group every half-second
-- whether it needed to or not). Call this whenever hideunlesssoon is toggled, and once at
-- startup to pick up whatever was already saved from a previous session.
function ElkBuffBars:UpdateSoonToExpireTimer()
    local needed = false
    for _, bg in pairs(self.bargroups) do
        if bg.layout.hideunlesssoon then
            needed = true
            break
        end
    end
    if needed and not self.timer_SoonToExpire then
        self.timer_SoonToExpire = self:ScheduleRepeatingTimer("RefreshSoonToExpireGroups", 1)
    elseif not needed and self.timer_SoonToExpire then
        self:CancelTimer(self.timer_SoonToExpire)
        self.timer_SoonToExpire = nil
    end
end

function ElkBuffBars:OnEnable()
    self:OnProfileEnable()

    -- register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
--~ 	if not InCombatLockdown() then
--~ 		self:PLAYER_REGEN_ENABLED()
--~ 	end

    self.bucket_PLAYER_TARGET_CHANGED = self:RegisterBucketEvent("PLAYER_TARGET_CHANGED", .1)
    self.bucket_UNIT_PET = self:RegisterBucketEvent("UNIT_PET", .1)
    self.bucket_UNIT_AURA = self:RegisterBucketEvent("UNIT_AURA", .1)

    if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        self:RegisterEvent("WEAPON_ENCHANT_CHANGED");
        self:RegisterEvent("WEAPON_SLOT_CHANGED");
    else
        self:RegisterEvent("UNIT_INVENTORY_CHANGED")
    end

    if CURRENT_EXPANSION_LEVEL >= (LE_EXPANSION_BURNING_CRUSADE or 1) then
        self.bucket_PLAYER_FOCUS_CHANGED = self:RegisterBucketEvent("PLAYER_FOCUS_CHANGED", .1) or nil

        self:RegisterEvent("UNIT_ENTERED_VEHICLE")
        self:RegisterEvent("UNIT_EXITED_VEHICLE")

        -- events for visibility during pet battles
        self:RegisterEvent("PET_BATTLE_OPENING_START")
        self:RegisterEvent("PET_BATTLE_CLOSE")
    end

    self:UpdateSoonToExpireTimer()

    LSM.RegisterCallback(self, "LibSharedMedia_Registered", "LibSharedMedia_Update")
    LSM.RegisterCallback(self, "LibSharedMedia_SetGlobal", "LibSharedMedia_Update")
    --
    self:ScanData_UnitAura("player", "BUFF")
    self:ScanData_UnitAura("player", "DEBUFF")
    self:ScanData_TENCH_Launcher()
    self:ScanData_TRACKING()

    -- hide Blizzard frames
    self:PLAYER_ENTERING_WORLD()
end

function ElkBuffBars:PLAYER_REGEN_DISABLED()
    for k, v in pairs(self.bargroups) do
        -- remove SecureActionButtons as they can't be moved with the frames in combat
        v:RecycleSABs()
        -- honor "Hide Group In Combat"
        v:RefreshContainerVisibility()
    end
end

function ElkBuffBars:PLAYER_REGEN_ENABLED()
    for k, v in pairs(self.bargroups) do
        -- update bars to recreate the SecureActionButtons
        v:UpdateBars()
        -- un-hide anything that was only hidden for "Hide Group In Combat"
        v:RefreshContainerVisibility()
    end
end

function ElkBuffBars:PET_BATTLE_OPENING_START()
    for k, v in pairs(self.bargroups) do
        v:GetContainer():Hide()
    end
    self:RefreshStuckPositions()
end

function ElkBuffBars:PET_BATTLE_CLOSE()
    for k, v in pairs(self.bargroups) do
        v:GetContainer():Show()
    end
    self:RefreshStuckPositions()
end

function ElkBuffBars:OnDisable()
    self:OnProfileDisable()
    self:ClearAllData()
end

function ElkBuffBars:OnProfileEnable()
    -- update minimap icon
    LDBIcon:Refresh(ELKBUFFBARS, self.db.profile.minimap)
    -- add default bargroups
    if #self.db.profile.bargroups == 0 then
        self:AddDefaultBargroups()
    end
    -- check bargroups
    self:CheckLayouts()

    -- one-time migration: Time Fraction (tenths-of-a-second countdown text) used to default
    -- to on, which looks flickery on short buffs. Flip this profile's existing groups to match
    -- the new off-by-default just once, so re-enabling it per group afterward sticks.
    if not self.db.profile.migrated_timefraction_default then
        for _, bg in ipairs(self.db.profile.bargroups) do
            if bg.bars then
                bg.bars.timeFraction = false
            end
        end
        self.db.profile.migrated_timefraction_default = true
    end

    -- one-time migration: turn off Config Mode / Show Anchor for all existing groups, so
    -- the drag-anchor borders/gear icons aren't left showing once initial setup is done
    if not self.db.profile.migrated_configmode_default then
        for _, bg in ipairs(self.db.profile.bargroups) do
            bg.configmode = false
            bg.anchorshown = false
        end
        self.db.profile.migrated_configmode_default = true
    end

    -- one-time migration: "My Self Buffs" and "Self Buff Alternatives" used to be stored flat
    -- (shared by every class using this profile), which is exactly what let one alt's self
    -- buffs show up as "missing" on a completely different class sharing the same profile.
    -- Re-key existing data by class, using whatever db.global.buffclasses has already learned
    -- about each name: routed to that one class if the tag is unambiguous. If it's ambiguous
    -- (tagged to 2+ classes) or not tagged at all, we genuinely don't know who it belongs to --
    -- rather than guessing by duplicating it onto every class (which just moves the bleed
    -- instead of fixing it -- you'd have to manually un-check it from every OTHER class one by
    -- one), it's dropped and left for you to re-check on whichever class(es) it actually
    -- applies to. Self Watcher is meant to be strictly per-class; Group Watcher's class list is
    -- deliberately the opposite (always shows every class, since that's what it's for).
    if not self.db.profile.migrated_perclass_selfbuffs then
        local buffclasses = self.db.global.buffclasses
        local function soleOwnerClass(auratype, name)
            local classes = buffclasses[auratype] and buffclasses[auratype][name]
            if not classes then return nil end
            local only, n = nil, 0
            for c in pairs(classes) do n = n + 1; only = c end
            return (n == 1) and only or nil
        end
        for _, bg in ipairs(self.db.profile.bargroups) do
            local filter = bg.filter
            if filter then
                if filter.selfbuffs then
                    local old = filter.selfbuffs
                    -- old format's top-level keys are auratype strings (BUFF/DEBUFF/TENCH/
                    -- TRACKING); new format's top-level keys are class names. Only migrate if
                    -- we can see it's still the old shape.
                    if old.BUFF or old.DEBUFF or old.TENCH or old.TRACKING then
                        local migrated = {}
                        for auratype, names in pairs(old) do
                            for name in pairs(names) do
                                local class = soleOwnerClass(auratype, name)
                                if class then
                                    migrated[class] = migrated[class] or {}
                                    migrated[class][auratype] = migrated[class][auratype] or {}
                                    migrated[class][auratype][name] = true
                                end
                            end
                        end
                        filter.selfbuffs = migrated
                    end
                end
                if filter.selfbuffaltgroups then
                    local old = filter.selfbuffaltgroups
                    -- old format's top-level keys are numeric slot indexes (1-4); new format's
                    -- top-level keys are class names.
                    local isOldFormat = false
                    for k in pairs(old) do
                        isOldFormat = (type(k) == "number")
                        break
                    end
                    if isOldFormat then
                        local migrated = {}
                        for groupindex, slot in pairs(old) do
                            -- a whole slot only migrates if every name checked in it agrees on
                            -- the same single owning class -- a mixed slot can't be assigned
                            -- anywhere sensible, so it's dropped rather than guessed at.
                            local agreedClass, conflict = nil, false
                            for auratype, names in pairs(slot) do
                                if auratype ~= "count" and auratype ~= "spec" and auratype ~= "onlygrouped" and auratype ~= "shared" then
                                    for name in pairs(names) do
                                        local class = soleOwnerClass(auratype, name)
                                        if not class or (agreedClass and agreedClass ~= class) then
                                            conflict = true
                                        else
                                            agreedClass = class
                                        end
                                    end
                                end
                            end
                            if agreedClass and not conflict then
                                migrated[agreedClass] = migrated[agreedClass] or {}
                                migrated[agreedClass][groupindex] = slot
                            end
                        end
                        filter.selfbuffaltgroups = migrated
                    end
                end
            end
        end
        self.db.profile.migrated_perclass_selfbuffs = true
    end

    -- one-time cleanup: an earlier version of the migration above (before this fix) duplicated
    -- ambiguous/untagged self-buff selections onto EVERY known class instead of dropping them,
    -- which is exactly what let things like Witch Hunter's own Edicts -- and universal buffs
    -- like Honor -- show up pre-checked on totally unrelated classes (e.g. a Tinkerer). Going
    -- forward, a name can only ever land under more than one class's bucket as leftover residue
    -- from that old duplication (each checkbox click now only ever writes to your own class),
    -- so: if a name is checked under more than one class, keep it only where db.global.
    -- buffclasses confidently says it belongs, or drop it from all of them if that's still
    -- ambiguous/unknown -- never leave it duplicated.
    if not self.db.profile.migrated_perclass_selfbuffs_v2 then
        local buffclasses = self.db.global.buffclasses
        local function soleOwnerClass(auratype, name)
            local classes = buffclasses[auratype] and buffclasses[auratype][name]
            if not classes then return nil end
            local only, n = nil, 0
            for c in pairs(classes) do n = n + 1; only = c end
            return (n == 1) and only or nil
        end
        for _, bg in ipairs(self.db.profile.bargroups) do
            local filter = bg.filter
            if filter and filter.selfbuffs then
                -- find every (auratype, name) present under 2+ classes
                local presence = {} -- "auratype|name" -> { class1 = true, class2 = true, ... }
                for class, data in pairs(filter.selfbuffs) do
                    for auratype, names in pairs(data) do
                        for name in pairs(names) do
                            local key = auratype.."|"..name
                            presence[key] = presence[key] or {}
                            presence[key][class] = true
                        end
                    end
                end
                for key, classesPresent in pairs(presence) do
                    local n = 0
                    for _ in pairs(classesPresent) do n = n + 1 end
                    if n > 1 then
                        local auratype, name = string_match(key, "^(.-)|(.*)$")
                        local keep = soleOwnerClass(auratype, name)
                        for class in pairs(classesPresent) do
                            if class ~= keep then
                                filter.selfbuffs[class][auratype][name] = nil
                            end
                        end
                    end
                end
            end
            if filter and filter.selfbuffaltgroups then
                -- same idea, but a whole slot (matched by groupindex) either agrees with one
                -- class or gets dropped from every class it's duplicated under
                local presence = {} -- groupindex -> { class1 = true, class2 = true, ... }
                for class, slots in pairs(filter.selfbuffaltgroups) do
                    for groupindex in pairs(slots) do
                        presence[groupindex] = presence[groupindex] or {}
                        presence[groupindex][class] = true
                    end
                end
                for groupindex, classesPresent in pairs(presence) do
                    local n = 0
                    for _ in pairs(classesPresent) do n = n + 1 end
                    if n > 1 then
                        for class in pairs(classesPresent) do
                            filter.selfbuffaltgroups[class][groupindex] = nil
                        end
                    end
                end
            end
        end
        self.db.profile.migrated_perclass_selfbuffs_v2 = true
    end

    -- update known names
    self:UpdateKnownNames()
    -- create bargroups based on stored settings
    self:CreateBarGroups()
end

function ElkBuffBars:OnProfileDisable()
    -- recycle all bargroups
    self:RemoveBarGroups()
end

-- Export/Import: dump the current profile to a plain Lua table literal string (no
-- compression/library dependency needed, it's just meant for backing up or moving settings
-- between characters/computers) and read one back in.
local function SerializeValue(v, buffer)
    local t = type(v)
    if t == "string" then
        buffer[#buffer + 1] = string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        buffer[#buffer + 1] = tostring(v)
    elseif t == "table" then
        buffer[#buffer + 1] = "{"
        for k, val in pairs(v) do
            buffer[#buffer + 1] = "["
            SerializeValue(k, buffer)
            buffer[#buffer + 1] = "]="
            SerializeValue(val, buffer)
            buffer[#buffer + 1] = ","
        end
        buffer[#buffer + 1] = "}"
    else
        -- functions/userdata/threads shouldn't appear in saved settings; fall back to nil
        -- rather than erroring so one bad value doesn't break the whole export
        buffer[#buffer + 1] = "nil"
    end
end

local function SerializeTable(tbl)
    local buffer = {}
    SerializeValue(tbl, buffer)
    return table.concat(buffer)
end

local function DeserializeString(str)
    local chunk, err = loadstring("return " .. str)
    if not chunk then
        return nil, err or "couldn't parse that string"
    end
    -- strip access to globals so a pasted-in string can't reach outside its own data
    setfenv(chunk, {})
    local ok, result = pcall(chunk)
    if not ok then
        return nil, result
    end
    if type(result) ~= "table" then
        return nil, "that doesn't look like a valid export string"
    end
    return result
end

function ElkBuffBars:ExportProfile()
    return SerializeTable(self.db.profile)
end

function ElkBuffBars:ImportProfile(str)
    if not str or string_trim(str) == "" then
        return
    end
    local imported, err = DeserializeString(str)
    if not imported then
        self:Print("Import failed: " .. tostring(err))
        return
    end

    -- wipe the current profile first, so keys that no longer exist in the imported
    -- data (e.g. an older export) don't linger behind mixed in with the new settings
    for k in pairs(self.db.profile) do
        self.db.profile[k] = nil
    end
    for k, v in pairs(imported) do
        self.db.profile[k] = v
    end

    self:OnProfileEnable()
    self:Print("Settings imported.")
end

-- Layout-only / Buffs-only export/import: each bar group's config is one table with a
-- "filter" sub-table (self buffs, alt sets, class watch, white/black list -- everything
-- buff-selection related) sitting alongside everything else (bars, position, colors, spacing,
-- anchor text -- the visual "layout"). This splits the two apart, so you can copy your visual
-- setup to a brand new profile (via Copy From, or a Layout export/import) without also
-- dragging along whatever buffs happened to be checked on whichever character last touched
-- that profile. Expected workflow for a clean new character: create+switch to a new profile,
-- Import Layout (recreates the same bar groups, empty buff selections), then check off that
-- character's own self buffs from scratch -- or Import Buffs too, if you saved an export from
-- a same-class alt and want its buff picks as a starting point.
function ElkBuffBars:ExportLayout()
    local snapshot = {}
    for k, v in pairs(self.db.profile) do
        if k == "bargroups" then
            local groups = {}
            for i, bg in ipairs(v) do
                local copy = {}
                for bk, bv in pairs(bg) do
                    if bk ~= "filter" then
                        copy[bk] = bv
                    end
                end
                groups[i] = copy
            end
            snapshot.bargroups = groups
        else
            snapshot[k] = v
        end
    end
    return SerializeTable(snapshot)
end

function ElkBuffBars:ExportBuffs()
    local snapshot = { bargroups = {} }
    for i, bg in ipairs(self.db.profile.bargroups) do
        snapshot.bargroups[i] = { filter = bg.filter }
    end
    return SerializeTable(snapshot)
end

function ElkBuffBars:ImportLayout(str)
    if not str or string_trim(str) == "" then
        return
    end
    local imported, err = DeserializeString(str)
    if not imported then
        self:Print("Import failed: " .. tostring(err))
        return
    end

    -- hang onto whatever buff selections already exist (by bar group position), so importing
    -- a layout never touches your current buff selections
    local oldFilters = {}
    if self.db.profile.bargroups then
        for i, bg in ipairs(self.db.profile.bargroups) do
            oldFilters[i] = bg.filter
        end
    end

    for k in pairs(self.db.profile) do
        self.db.profile[k] = nil
    end
    for k, v in pairs(imported) do
        self.db.profile[k] = v
    end

    self.db.profile.bargroups = self.db.profile.bargroups or {}
    for i, bg in ipairs(self.db.profile.bargroups) do
        bg.filter = oldFilters[i] or { type = { BUFF = true } }
    end

    self:OnProfileEnable()
    self:Print("Layout imported. Buff selections were left untouched.")
end

function ElkBuffBars:ImportBuffs(str)
    if not str or string_trim(str) == "" then
        return
    end
    local imported, err = DeserializeString(str)
    if not imported then
        self:Print("Import failed: " .. tostring(err))
        return
    end
    if not imported.bargroups or not self.db.profile.bargroups or #self.db.profile.bargroups == 0 then
        self:Print("Import failed: no bar groups to import buffs into -- import (or set up) a layout first.")
        return
    end

    local matched = 0
    for i, bg in ipairs(imported.bargroups) do
        if self.db.profile.bargroups[i] and bg.filter then
            self.db.profile.bargroups[i].filter = bg.filter
            matched = matched + 1
        end
    end

    self:OnProfileEnable()
    self:Print("Buff selections imported into "..matched.." bar group(s).")
end

-- refresh layouts when new media is set
function ElkBuffBars:LibSharedMedia_Update(callback, mediatype, handle)
    if mediatype == "font" or mediatype == "statusbar" then
        for k, v in pairs(self.bargroups) do
            v:SetLayout()
        end
    end
end

function ElkBuffBars:PLAYER_ENTERING_WORLD()
    self:HandleFrame_Blizzard_BuffFrame(self.db.profile.hidebuffframe)
    self:HandleFrame_Blizzard_TemporaryEnchantFrame(self.db.profile.hidetenchframe)
    self:HandleFrame_Blizzard_MiniMapTracking(self.db.profile.hidetrackingframe)
    self:HandleFrame_Blizzard_VanityBuffs(self.db.profile.hidevanitybuffs)
    self:DoFullUpdate()
end

local hidden_blizzard_frames = {}

function ElkBuffBars:HandleFrame_Blizzard_BuffFrame(hide)
    if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        if hide then
            -- BuffFrame:UnregisterEvent("WEAPON_ENCHANT_CHANGED");
            -- BuffFrame:UnregisterEvent("WEAPON_SLOT_CHANGED");
            -- BuffFrame:UnregisterEvent("UNIT_AURA")
            BuffFrame:Hide()
            hidden_blizzard_frames["BuffFrame"] = true
        elseif hidden_blizzard_frames["BuffFrame"] then
            -- BuffFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED");
            -- BuffFrame:RegisterEvent("WEAPON_SLOT_CHANGED");
            -- BuffFrame:RegisterEvent("UNIT_AURA")
            BuffFrame:Show()
            BuffFrame:Update()
            hidden_blizzard_frames["BuffFrame"] = nil
        end
        if hide then
            -- DebuffFrame:UnregisterEvent("UNIT_AURA")
            DebuffFrame:Hide()
            hidden_blizzard_frames["DebuffFrame"] = true
        elseif hidden_blizzard_frames["DebuffFrame"] then
            -- DebuffFrame:RegisterEvent("UNIT_AURA")
            DebuffFrame:Show()
            DebuffFrame:Update()
            hidden_blizzard_frames["DebuffFrame"] = nil
        end
    else
        if hide then
            BuffFrame:UnregisterEvent("UNIT_AURA")
            BuffFrame:Hide()
            hidden_blizzard_frames["BuffFrame"] = true
        elseif hidden_blizzard_frames["BuffFrame"] then
            BuffFrame:RegisterEvent("UNIT_AURA")
            BuffFrame:Show()
            BuffFrame_Update()
            hidden_blizzard_frames["BuffFrame"] = nil
        end
    end
end

function ElkBuffBars:HandleFrame_Blizzard_TemporaryEnchantFrame(hide)
    if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        return
    end
    if hide then
        TemporaryEnchantFrame:Hide()
        hidden_blizzard_frames["TemporaryEnchantFrame"] = true
    elseif hidden_blizzard_frames["TemporaryEnchantFrame"] then
        TemporaryEnchantFrame:Show()
        hidden_blizzard_frames["TemporaryEnchantFrame"] = nil
    end
end

-- "VanityBuffs" is Ascension's own frame for its long-duration/vanity buffs (Bonus XP,
-- Keeper's Scrolls, Well Rested, etc.) -- it's separate from Blizzard's BuffFrame, so hiding
-- BuffFrame alone doesn't touch it. Not a Blizzard/retail global, so it's guarded with a
-- nil-check rather than the WOW_PROJECT_ID checks used for the other Handle* functions.
local vanityBuffsHooked = false
function ElkBuffBars:HandleFrame_Blizzard_VanityBuffs(hide)
    if not VanityBuffs then return end
    if not vanityBuffsHooked then
        vanityBuffsHooked = true
        -- Ascension's own code shows this frame again on its own (e.g. whenever its buffs
        -- update), which silently undid a one-time :Hide() call every login. Hook :Show()
        -- itself so it gets forced back shut immediately, for as long as the setting is on.
        hooksecurefunc(VanityBuffs, "Show", function()
            if ElkBuffBars.db.profile.hidevanitybuffs then
                VanityBuffs:Hide()
            end
        end)
    end
    if hide then
        VanityBuffs:Hide()
        hidden_blizzard_frames["VanityBuffs"] = true
    elseif hidden_blizzard_frames["VanityBuffs"] then
        VanityBuffs:Show()
        hidden_blizzard_frames["VanityBuffs"] = nil
    end
end

if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
    function ElkBuffBars:HandleFrame_Blizzard_MiniMapTracking(hide)
        if hide then
            MiniMapTracking:UnregisterEvent("MINIMAP_UPDATE_TRACKING")
            MiniMapTracking:Hide()
            hidden_blizzard_frames["MiniMapTracking"] = true
        elseif hidden_blizzard_frames["MiniMapTracking"] then
            MiniMapTracking:RegisterEvent("MINIMAP_UPDATE_TRACKING")
            local icon = GetTrackingTexture();
            if icon then
                MiniMapTrackingIcon:SetTexture(icon);
                MiniMapTracking:Show();
            end
            hidden_blizzard_frames["MiniMapTracking"] = nil
        end
    end
elseif WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
    function ElkBuffBars:HandleFrame_Blizzard_MiniMapTracking(hide)
        if hide then
            MiniMapTracking:Hide()
            hidden_blizzard_frames["MiniMapTracking"] = true
        elseif hidden_blizzard_frames["MiniMapTracking"] then
            MiniMapTracking:Show()
            hidden_blizzard_frames["MiniMapTracking"] = nil
        end
    end
elseif WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC then
    function ElkBuffBars:HandleFrame_Blizzard_MiniMapTracking(hide)
        if hide then
    --~ 		MiniMapTracking:UnregisterEvent("MINIMAP_UPDATE_TRACKING")
            MiniMapTracking:Hide()
            MiniMapTrackingButton:Hide()
            hidden_blizzard_frames["MiniMapTracking"] = true
        elseif hidden_blizzard_frames["MiniMapTracking"] then
    --~ 		MiniMapTracking:RegisterEvent("MINIMAP_UPDATE_TRACKING")
            MiniMapTracking:Show()
            MiniMapTrackingButton:Show()
    --~ 		MiniMapTracking_Update()
            hidden_blizzard_frames["MiniMapTracking"] = nil
        end
    end
else
    function ElkBuffBars:HandleFrame_Blizzard_MiniMapTracking(hide)
        -- hiding the button currently prevents showing the selection menu as menues for invisible buttons are closed via onUpdate
        return
--        if isTrackingDisabled then
--            return
--        end
--        if hide then
--            MinimapCluster.Tracking:Hide()
--            hidden_blizzard_frames["MiniMapTracking"] = true
--        elseif hidden_blizzard_frames["MiniMapTracking"] then
--            MinimapCluster.Tracking:Show()
--            hidden_blizzard_frames["MiniMapTracking"] = nil
--        end
    end
end

------------------------------------------------------------------------
-- Cache bars

local barcache = {}

function ElkBuffBars:GetBar()
    if #barcache > 0 then
        return table_remove(barcache, #barcache)
    else
        return self:NewBar() -- see EBB_Bar.lua
    end
end

function ElkBuffBars:RecycleBar(bar)
    bar:Reset()
    table_insert(barcache, bar)
end

------------------------------------------------------------------------
-- Cache bar groups

local bargroupcache = {}

function ElkBuffBars:GetBarGroup()
    if #bargroupcache > 0 then
        return table_remove(bargroupcache, #bargroupcache)
    else
        return self:NewBarGroup() -- see EBB_BarGroup.lua
    end
end

function ElkBuffBars:RecycleBarGroup(bargroup)
    bargroup:Reset()
    table_insert(bargroupcache, bargroup)
end

------------------------------------------------------------------------
-- Cache datatables

local datatablecache = {}

local function GetDataTable()
    if #datatablecache > 0 then
        return table_remove(datatablecache, #datatablecache)
    else
        return {}
    end
end

local function RecycleDataTable(dt)
    table_insert(datatablecache, dt)
end

------------------------------------------------------------------------
-- Cache SecureActionButton

local cache_SAB = {}

local SAB_OnLeftClick = function(self, unit, button) local bar = self:GetAttribute("_bar"); bar.OnClick(bar, button) end
local SAB_OnRightClickTracking = function(self, unit, button)
    if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
        CancelTrackingBuff()
    end
end
local SAB_OnEnter = function(self) local bar = self:GetAttribute("_bar"); bar.OnEnter(bar) end
local SAB_OnLeave = function(self) local bar = self:GetAttribute("_bar"); bar.OnLeave(bar) end

function ElkBuffBars:GetSAB()
    if #cache_SAB > 0 then
        return table_remove(cache_SAB, #cache_SAB)
    else
        local button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
            -- we need either up or down based on CVar ActionButtonUseKeyDown
            button:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
        else
            button:RegisterForClicks("LeftButtonDown", "RightButtonDown")
        end
        button:SetAttribute("unit", nil)
        button:SetAttribute("*type1", "OnLeftClick")
        button:SetAttribute("_OnLeftClick", SAB_OnLeftClick)
        button:SetAttribute("*type2", "cancelaura")
        button:SetAttribute("_OnRightClickTracking", SAB_OnRightClickTracking)
        button:SetAttribute("*index2", nil)
--~ 		button:SetAttribute("*spell2", nil)
        button:SetAttribute("*target-slot2", nil)
        button:SetScript("OnEnter", SAB_OnEnter)
        button:SetScript("OnLeave", SAB_OnLeave)
        return button
    end
end

function ElkBuffBars:RecycleSAB(button)
    button:ClearAllPoints()
    button:Hide()
    table_insert(cache_SAB, button)
end

------------------------------------------------------------------------
-- Keep track of known buff, debuff, and temp enchant names

ElkBuffBars.knownnames = {
    BUFF = {},
    DEBUFF = {},
    TENCH = {},
    TRACKING = {},
}

local knownnames_validate = {
    BUFF = {},
    DEBUFF = {},
    TENCH = {},
    TRACKING = {},
}

-- live, per-tab search-box filtering for the BUFF/DEBUFF/TENCH/TRACKING checklists (White
-- List, Black List, My Self Buffs, Self Buff Alternatives, Class Watch) -- not persisted,
-- just an in-session UI convenience so a long list of known names can be narrowed down.
-- searchkey is a caller-chosen unique string identifying which tab's search box this is.
local searchterms = {}


-- builds a reusable "search box" input entry for a given searchkey; place it in any tab that
-- has BUFF/DEBUFF/TENCH/TRACKING checklists built by BuildNameChecklist below, and it narrows
-- all of them down together as you type. NOTE: in this AceConfig-3.0's sort, NEGATIVE order
-- values sort to the very END of the list, not the front (the opposite of what you'd expect) --
-- so order 0 here is deliberately the lowest NON-negative value, keeping it ahead of
-- spec/count/onlygrouped (0.1/0.2/0.3) and the BUFF/DEBUFF/TENCH/TRACKING sections (1-4).
local function BuildSearchBoxOption(searchkey)
    return {
        order = 0,
        type = "input",
        width = "full",
        name = L["OPTIONS_GROUP_FILTER_SEARCH_NAME"],
        desc = L["OPTIONS_GROUP_FILTER_SEARCH_DESC"],
        get = function(info) return searchterms[searchkey] or "" end,
        set = function(info, v)
            searchterms[searchkey] = v
            LibStub("AceConfigRegistry-3.0"):NotifyChange(ELKBUFFBARS)
        end,
    }
end

------------------------------------------------------------------------
-- Turns a BUFF/DEBUFF/TENCH/TRACKING name list into individual checkboxes (one per buff)
-- instead of one compact multiselect grid -- this is what lets each entry carry its own real
-- mouseover tooltip (WoW's own "spell:<id>" hyperlink, same as hovering a spell link in chat)
-- instead of one shared description for the whole list. Visibility (search term + class
-- restriction) is re-checked live via "hidden", and new entries get dropped in on the fly as
-- new buffs are learned -- see the toggleRegistry loop at the end of AddKnownName above.

-- auratype -> list of { args = <table>, searchkey, classRestrict, get = fn(name), set =
-- fn(name, value) } for every checklist section built so far, so a newly-learned buff (or a
-- name that just picked up a spellid, for the tooltip) can be patched into all of them live,
-- without requiring a UI reload
local toggleRegistry = { BUFF = {}, DEBUFF = {}, TENCH = {}, TRACKING = {} }
local nextDynamicOrder = 10000 -- new mid-session discoveries just get tacked on the end

local function NameToggleHidden(auratype, name, searchkey, classRestrict)
    if classRestrict then
        local buffclasses = ElkBuffBars.db.global.buffclasses[auratype]
        local classes = buffclasses and buffclasses[name]
        if classes and not classes[classRestrict] then
            return true
        end
    end
    local term = searchterms[searchkey]
    if term and term ~= "" and not string_find(strlower(name), strlower(term), 1, true) then
        return true
    end
    return false
end

-- pulls a buff's real tooltip text (whatever WoW itself would show) by briefly pointing a
-- hidden scanning tooltip at its spellID and reading the lines back out as plain text. Used
-- instead of AceConfig's "tooltipHyperlink" field -- that field isn't recognized by every
-- copy of AceConfigRegistry-3.0 that might be active account-wide (LibStub only keeps one
-- shared copy of each library across ALL addons, and an older copy from another addon can
-- "win" over the one bundled here), and an unrecognized field hard-crashes the whole options
-- window instead of degrading gracefully. Plain "desc" text is safe everywhere.
local scanTooltip = CreateFrame("GameTooltip", "ElkBuffBarsScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
local spellDescCache = {}

local function GetSpellDescription(spellid)
    local cached = spellDescCache[spellid]
    if cached ~= nil then
        return cached or nil
    end
    scanTooltip:ClearLines()
    scanTooltip:SetSpellByID(spellid)
    local lines = {}
    for i = 2, scanTooltip:NumLines() do
        local fs = _G["ElkBuffBarsScanTooltipTextLeft"..i]
        local text = fs and fs:GetText()
        if text and text ~= "" then
            table_insert(lines, text)
        end
    end
    local desc = (#lines > 0) and table.concat(lines, "\n") or false
    spellDescCache[spellid] = desc -- cache misses too (as false), so we don't rescan every hover
    return desc or nil
end

local function BuildNameToggle(auratype, name, searchkey, classRestrict, getFn, setFn, order)
    local spellid = ElkBuffBars.db.global.buffspellids[auratype][name]
    return {
        order = order,
        type = "toggle",
        width = "double",
        name = name,
        desc = spellid and function() return GetSpellDescription(spellid) end or nil,
        hidden = function() return NameToggleHidden(auratype, name, searchkey, classRestrict) end,
        get = function() return getFn(name) end,
        set = function(info, value) setFn(name, value) end,
    }
end

-- builds the toggle-per-name args for one auratype section (e.g. the "Buff" group inside "My
-- Self Buffs"), wrapped in its own inline group so it still reads as a labeled section same as
-- before. classRestrict (optional): only show names never seen on any class, or seen on this
-- one specifically (see NameToggleHidden above for the exact rule).
local function BuildNameChecklist(auratype, searchkey, classRestrict, getFn, setFn, order, sectionName)
    local args = {}
    for i, name in ipairs(knownnames_validate[auratype]) do
        args[name] = BuildNameToggle(auratype, name, searchkey, classRestrict, getFn, setFn, i)
    end
    table_insert(toggleRegistry[auratype], {
        args = args, searchkey = searchkey, classRestrict = classRestrict, get = getFn, set = setFn,
    })
    return {
        order = order,
        type = "group",
        inline = true,
        name = sectionName,
        args = args,
    }
end

-- every real/custom class name ever seen (this session's seed comes from
-- db.global.knownclasses in OnInitialize; grows automatically as new classes are
-- encountered, either your own alts logging in or party/raid members during scans)
local knownclasses_validate = {}

-- every Ascension class known to exist, hardcoded so Group Watcher always offers the full
-- roster from the very first login -- not just whichever classes you happen to have already
-- played or grouped with. Anything actually encountered that ISN'T in this list (a class added
-- to the server after this list was written) still gets picked up automatically via
-- AddKnownClass, same as before -- this list is a floor, not a ceiling.
local ASCENSION_CLASSES = {
    "Barbarian", "Bloodmage", "Chronomancer", "Cultist", "Felsworn", "Guardian",
    "Knight of Xoroth", "Necromancer", "Primalist", "Pyromancer", "Ranger", "Reaper",
    "Runemaster", "Starcaller", "Stormbringer", "Sun Cleric", "Templar", "Tinker",
    "Venomancer", "Witch Doctor", "Witch Hunter",
}

-- rebuilds the (fresh-this-session, empty) local knownclasses_validate array from the
-- persisted, account-wide db.global.knownclasses set PLUS the full hardcoded roster above --
-- called once from OnInitialize
function ElkBuffBars:SeedKnownClasses()
    local seen = {}
    for _, name in ipairs(ASCENSION_CLASSES) do
        if not seen[name] then
            seen[name] = true
            table_insert(knownclasses_validate, name)
        end
        self.db.global.knownclasses[name] = true
    end
    for name in pairs(self.db.global.knownclasses) do
        if not seen[name] then
            seen[name] = true
            table_insert(knownclasses_validate, name)
        end
    end
    table_sort(knownclasses_validate)
end

function ElkBuffBars:AddKnownClass(name)
    if not name or name == "" then
        return
    end
    if string_find(name, "[%c\127]") then
        -- name contained control characters; would break AceConfig
        return
    end
    if not self.db.global.knownclasses[name] then
        self.db.global.knownclasses[name] = true
        table_insert(knownclasses_validate, name)
        table_sort(knownclasses_validate)
    end
end

function ElkBuffBars:AddKnownName(auratype, name, class, spellid)
    if string_find(name, "[%c\127]") then
        -- name contained control characters; would break AceConfig
        return
    end
    if class and class ~= "" then
        local bc = self.db.global.buffclasses[auratype]
        bc[name] = bc[name] or {}
        bc[name][class] = true
    end
    if spellid then
        self.db.global.buffspellids[auratype][name] = spellid
    end
    local isNew = self.knownnames[auratype] and not self.knownnames[auratype][name]
    if isNew then
        self.knownnames[auratype][name] = true
        AO_buffsettings.args[auratype].args[name] = self:GetNameOptions(auratype, name)
        table_insert(knownnames_validate[auratype], name)
        table_sort(knownnames_validate[auratype])
    end
    -- drop a new toggle into every already-built "My Self Buffs"/Alt Set/Class Watch/
    -- White-Black-List checklist that covers this auratype, so a buff discovered mid-session
    -- shows up as a selectable option immediately, without needing a UI reload. Also used to
    -- pick up a newly-learned spellid (for the mouseover tooltip) on a name that was already
    -- known but didn't have one yet.
    for _, reg in ipairs(toggleRegistry[auratype]) do
        if isNew or reg.args[name] == nil or (spellid and not reg.args[name].desc) then
            nextDynamicOrder = nextDynamicOrder + 1
            reg.args[name] = BuildNameToggle(auratype, name, reg.searchkey, reg.classRestrict, reg.get, reg.set, reg.args[name] and reg.args[name].order or nextDynamicOrder)
        end
    end
end

function ElkBuffBars:UpdateKnownNames()
    for auratype, data in pairs(self.db.profile.nameoverride) do
        for name in pairs(data) do
            self:AddKnownName(auratype, name)
        end
    end
    for auratype, data in pairs(self.db.profile.typeoverride) do
        for name in pairs(data) do
            self:AddKnownName(auratype, name)
        end
    end
    for id, bg in pairs(self.db.profile.bargroups) do
        if bg.filter.names_include then
            for auratype, data in pairs(bg.filter.names_include) do
                for name in pairs(data) do
                    self:AddKnownName(auratype, name)
                end
            end
        end
        if bg.filter.names_exclude then
            for auratype, data in pairs(bg.filter.names_exclude) do
                for name in pairs(data) do
                    self:AddKnownName(auratype, name)
                end
            end
        end
        if bg.filter.selfbuffs then
            -- keyed by class now (see migrated_perclass_selfbuffs in OnProfileEnable) -- passing
            -- the class here backfills db.global.buffclasses for names that were only ever
            -- selected in "My Self Buffs" and never actually observed live via UNIT_AURA (e.g.
            -- you're not currently grouped with anyone who'd show it), which is also what keeps
            -- them properly hidden from OTHER classes' Group Watcher/checklists going forward.
            for classname, data in pairs(bg.filter.selfbuffs) do
                for auratype, names in pairs(data) do
                    for name in pairs(names) do
                        self:AddKnownName(auratype, name, classname)
                    end
                end
            end
        end
        if bg.filter.selfbuffaltgroups then
            -- also keyed by class now -- same backfill reasoning as selfbuffs above.
            for classname, slots in pairs(bg.filter.selfbuffaltgroups) do
                for _, slot in pairs(slots) do
                    for auratype, data in pairs(slot) do
                        if auratype ~= "count" and auratype ~= "spec" and auratype ~= "onlygrouped" and auratype ~= "shared" then
                            for name in pairs(data) do
                                self:AddKnownName(auratype, name, classname)
                            end
                        end
                    end
                end
            end
        end
        if bg.filter.classbuffs then
            for classname, byclass in pairs(bg.filter.classbuffs) do
                for auratype, data in pairs(byclass) do
                    for name in pairs(data) do
                        self:AddKnownName(auratype, name, classname)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Bar group management

ElkBuffBars.bargroups = {}

local function ApplyDefaults(defaults, data)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if data[k] == nil or type(data[k]) ~= "table" then data[k] = {} end
            ApplyDefaults(v, data[k])
        else
            if data[k] == nil then data[k] = v end
        end
    end
end

local DEFAULT_LAYOUT = {
    bars = {
        icon				= "LEFT",				-- "LEFT", "RIGHT", false
        iconcount			= true,					-- true, false
        iconcountanchor		= "CENTER",				-- <anchor>
        iconcountfont		= "Arial Narrow",		-- <LSM:font>
        iconcountfontsize	= 14,					-- <font size>
        iconcountcolor		= {1, 1, 1, 1},			-- <color set>
        iconcountstyle		= "OUTLINE",			-- "", OUTLINE, THICKOUTLINE -- matches the previously hardcoded look, so existing setups don't change
        iconcountbackdrop	= false,				-- true, false
        iconcountbackdropcolor = {0, 0, 0, 0.6},	-- <color set>
        bar					= true,					-- true, false
        bgbar				= true,					-- true, false
        bartexture			= "Otravi",				-- <LSM:statusbar>, false
        barright			= false,				-- true, false
        spark				= false,				-- true, false
        textTL				= "NAMERANKCOUNT",		-- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
        textTLfont			= "Friz Quadrata TT",	-- <LSM:font>
        textTLfontsize		= 14,					-- <font size>
        textTLcolor			= {1, 1, 1, 1},			-- <color set>
        textTLstyle			= "",					-- "", OUTLINE, THICKOUTLINE
        textTLalign			= "LEFT",				-- left, center, right
        textTR				= "TIMELEFT",			-- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
        textTRfont			= "Friz Quadrata TT",	-- <LSM:font>
        textTRfontsize		= 14,					-- <font size>
        textTRcolor			= {1, 1, 1, 1},			-- <color set>
        textTRstyle			= "",					-- "", OUTLINE, THICKOUTLINE
        textBL				= false,				-- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
        textBLfont			= "Friz Quadrata TT",	-- <LSM:font>
        textBLfontsize		= 14,					-- <font size>
        textBLcolor			= {1, 1, 1, 1},			-- <color set>
        textBLstyle			= "",					-- "", OUTLINE, THICKOUTLINE
        textBLalign			= "LEFT",				-- left, center, right
        textBR				= false,				-- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
        textBRfont			= "Friz Quadrata TT",	-- <LSM:font>
        textBRfontsize		= 14,					-- <font size>
        textBRcolor			= {1, 1, 1},			-- <color set>
        textBRstyle			= "",					-- "", OUTLINE, THICKOUTLINE
        barcolor			= {0.3, 0.5, 1, 0.8},	-- <color set>
        barbgcolor			= {0, 0.5, 1, 0.3},		-- <color set>
        debufftypecolor		= true,					-- true, false
        timeformat			= "CONDENSED",			-- "DEFAULT", "CLOCK", "CONDENSED"
        timeFraction		= false,				-- true, false
        width				= 250,
        height				= 20,
        tooltipanchor		= "default",			-- <tooltip anchor>, "default"
        tooltipcaster		= true,					-- true, false
        timelessfull		= false,				-- true, false
        padding				= 1,					-- 0 - 10
        abbreviate_name		= 0,					--
    },
    filter = {
        type = {},
        showmissing = false,						-- true, false
        whitelistisfilter = true,					-- true, false -- true = White List restricts what's shown (classic behavior); false = White List is only consulted for Show Missing, doesn't restrict the group's normal display
        alertblacklisted = false,					-- true, false -- flags (instead of hiding) a Black List name if it's currently active
    },
    alpha			= 1,							-- alpha value
    scale			= 1,
    sorting			= "timeleft",					-- timeleft, timemax
    target			= "player",						-- player, pet, target
    growup			= false,						-- true, false
    barspacing		= 0,							-- 0+
    configmode		= false,						-- true, false
    anchortext		= "unknown bargroup",			-- <string>
    anchorshown		= false,						-- true, false
    hideanchorwhenempty = false,					-- true, false
    hideincombat	= false,						-- true, false -- hides the WHOLE group's bars while in combat
    hidewhennomissing = false,						-- true, false -- hides the WHOLE group unless Show Missing has a red bar up
    hidewhenallmissing = false,					-- true, false -- hides the WHOLE group if every tracked name is missing (0 active)
    hideunlesssoon	= false,						-- true, false -- hides the WHOLE group unless a bar is inside its expiry warning window
    hideunlesssoonseconds = 20,					-- 1+ -- how many seconds left counts as "about to expire" for the above, and for blinking
}

-- resets corrupt entries in the given layout to default values; returns a now valid layout
function ElkBuffBars:CheckLayout(layout)
    if not layout or type(layout) ~= "table" then layout = {} end
    ApplyDefaults(DEFAULT_LAYOUT, layout)
    if layout.id and layout.stickto == layout.id then layout.stickto = nil end
    return layout
end

function ElkBuffBars:CheckLayouts()
    local bglayouts = self.db.profile.bargroups
    for k, v in ipairs(bglayouts) do
        self:CheckLayout(v)
    end
end

function ElkBuffBars:CreateBarGroups()
    for k, v in pairs(self.bargroups) do
        self:RecycleBarGroup(v)
        self.bargroups[k] = nil
    end

    local bglayouts = self.db.profile.bargroups
    for k, v in ipairs(bglayouts) do
        self:AddBarGroup(v)
    end
    for k, v in ipairs(self.bargroups) do
        local layout = bglayouts[k]
        v:SetPosition()
        v:GetContainer():Show()
    end
end

function ElkBuffBars:RemoveBarGroups()
    for i, v in pairs(self.bargroups) do
        self:RecycleBarGroup(v)
        self.bargroups[i] = nil
        AO_groupsettings[tostring(i)] = nil
    end
end

function ElkBuffBars:AddBarGroup(layout)
    if not layout then
        layout = {
            bars = {
            },
            filter = {
                type = {
                    BUFF = true,
                }
            },
            anchortext = "new bargroup",			-- <string>
        }

        table_insert(self.db.profile.bargroups, layout)
    end
    local bargroup = self:GetBarGroup()
    table_insert(self.bargroups, bargroup)
    layout.id = #self.bargroups
    self:CheckLayout(layout)
    bargroup:SetLayout(layout)
    local settingsId = tostring(layout.id)
    if not AO_groupsettings[settingsId] then
        AO_groupsettings[settingsId] = self:GetGroupOptions(layout.id)
    end
    AO_groupsettings[settingsId].disabled = false
    AO_groupsettings[settingsId].hidden = false
    return bargroup
end

function ElkBuffBars:RemoveBarGroup(id)
    local settingsId = tostring(#self.bargroups)
    local bg = table_remove(self.bargroups, id)
    table_remove(self.db.profile.bargroups, id)
    for k, v in pairs(self.bargroups) do
        local layout = v.layout
        layout.id = k
        if layout.stickto then
            if layout.stickto == id then
                -- the group we sticked to was removed
                local container = v:GetContainer()
                layout.stickto = nil
                container:ClearAllPoints()
                container:SetPoint("CENTER", UIParent, "CENTER", layout.x, layout.y)
                v:ToggleConfigMode(true)
            elseif layout.stickto > id then
                layout.stickto = layout.stickto - 1
            end
        end
    end
    AO_groupsettings[settingsId].disabled = true
    AO_groupsettings[settingsId].hidden = true
    self:RecycleBarGroup(bg)
end

function ElkBuffBars:CopyBarLayout(target, source)
    if target == source then return end
    if not source then source = DEFAULT_LAYOUT end
    target.bars = {}
    ApplyDefaults(source.bars, target.bars)
    target.sorting = source.sorting
    self.bargroups[target.id]:SetLayout()
end

-- -----
-- buff scanning
-- -----
ElkBuffBars.buffdata = {
    focus = {},
    pet = {},
    player = {},
    target = {},
    vehicle = {},
}
ElkBuffBars.debuffdata = {
    focus = {},
    pet = {},
    player = {},
    target = {},
    vehicle = {},
}
ElkBuffBars.tenchdata = {}
ElkBuffBars.trackingdata = {}

function ElkBuffBars:ClearAllData()
    for _, data in pairs(self.buffdata) do
        for k, v in pairs(data) do
            RecycleDataTable(v)
            data[k] = nil
        end
    end
    for _, data in pairs(self.debuffdata) do
        for k, v in pairs(data) do
            RecycleDataTable(v)
            data[k] = nil
        end
    end
    for k, v in pairs(self.tenchdata) do
        RecycleDataTable(v)
        self.tenchdata[k] = nil
    end
end

function ElkBuffBars:PLAYER_FOCUS_CHANGED()
    self:ScanData_UnitAura("focus", "BUFF")
    self:ScanData_UnitAura("focus", "DEBUFF")

    self:UpdateGroups()
end

function ElkBuffBars:PLAYER_TARGET_CHANGED()
    self:ScanData_UnitAura("target", "BUFF")
    self:ScanData_UnitAura("target", "DEBUFF")

    self:UpdateGroups()

    -- Targeting something and clearing it again fast enough can leave the previous target's
    -- buffs/debuffs stuck on screen -- the scan above runs the instant this event fires, but
    -- WoW's client can apparently still briefly resolve the "target" token against stale data
    -- right around a fast swap. A follow-up rescan a beat later catches and corrects that.
    -- Cancels and reschedules on every call so rapid target-flicking only ever does one final
    -- confirmation scan once things settle, not one per flick.
    if self.timer_TargetRescan then
        self:CancelTimer(self.timer_TargetRescan)
    end
    self.timer_TargetRescan = self:ScheduleTimer(function()
        self.timer_TargetRescan = nil
        self:ScanData_UnitAura("target", "BUFF")
        self:ScanData_UnitAura("target", "DEBUFF")
        self:UpdateGroups()
    end, 0.15)
end

function ElkBuffBars:UNIT_PET(args)
    if args["player"] then
        self:ScanData_UnitAura("pet", "BUFF")
        self:ScanData_UnitAura("pet", "DEBUFF")

        self:UpdateGroups()
    end
end

function ElkBuffBars:UNIT_ENTERED_VEHICLE(event, unit)
    if unit ~= "player" then return end

    self:ScanData_UnitAura("vehicle", "BUFF")
    self:ScanData_UnitAura("vehicle", "DEBUFF")

    self:UpdateGroups()
end

function ElkBuffBars:UNIT_EXITED_VEHICLE(event, unit)
    if unit ~= "player" then return end

    self:ScanData_UnitAura("vehicle", "BUFF")
    self:ScanData_UnitAura("vehicle", "DEBUFF")

    self:UpdateGroups()
end

local watched_unitids = { focus = true, pet = true, player = true, target = true, vehicle = true }
function ElkBuffBars:UNIT_AURA(args)
    for arg in pairs(args) do
        if watched_unitids[arg] then
            self:ScanData_UnitAura(arg, "BUFF")
            self:ScanData_UnitAura(arg, "DEBUFF")
        end
        if arg == "player" then
            self:ScanData_TRACKING()
        end
    end

    self:UpdateGroups()
end

--
local function hasTEnch(...)
    local RETURNS_PER_ITEM = 4
    local numVals = select("#", ...)
    local numItems = numVals / RETURNS_PER_ITEM
    for itemIndex = 1, numItems do
        local hasEnchant = select(RETURNS_PER_ITEM * (itemIndex - 1) + 1, ...)
        if hasEnchant then return true end
    end
    return false
end

local TEnchBuffer = {}
local function refreshTEnchBuffer(...)
    table_wipe(TEnchBuffer)
    for i = 1, select("#", ...) do
        TEnchBuffer[i] = (select(i, ...))
    end
end
local function hasTEnchUpdate(...)
    local RETURNS_PER_ITEM = 4
    local numVals = select("#", ...)
    local numItems = numVals / RETURNS_PER_ITEM
    local changes = false
    for itemIndex = 1, numItems do
        local hasEnchant, enchantExpiration, enchantCharges, enchantId = select(RETURNS_PER_ITEM * (itemIndex - 1) + 1, ...)
        local offset = (itemIndex - 1) * RETURNS_PER_ITEM
        if (hasEnchant ~= TEnchBuffer[offset + 1]) or (enchantExpiration or 0) > (TEnchBuffer[offset + 2] or 0) or (enchantCharges ~= TEnchBuffer[offset + 3]) or (enchantId ~= TEnchBuffer[offset + 4]) then
            changes = true
            break
        end
    end
    if not changes then
        refreshTEnchBuffer(...)
    end
    return changes
end

function ElkBuffBars:UNIT_INVENTORY_CHANGED(event, unit)
    if unit ~= "player" then return end
    self:ScanData_TENCH_Launcher()
end

function ElkBuffBars:WEAPON_ENCHANT_CHANGED()
    self:ScanData_TENCH_Launcher()
end

function ElkBuffBars:WEAPON_SLOT_CHANGED()
    self:ScanData_TENCH_Launcher()
end

local function hasRangedItemEquipped()
    local rangedSlot = TENCH_INVENTORYSLOT[3]
    return rangedSlot ~= nil and GetInventoryItemID("player", rangedSlot) ~= nil
end

local function hasOffhandItemEquipped()
    local offhandSlot = TENCH_INVENTORYSLOT[2]
    return offhandSlot ~= nil and GetInventoryItemID("player", offhandSlot) ~= nil
end

function ElkBuffBars:ScanData_TENCH_Launcher()
    -- Ascension's ranged-weapon "gadget" buffs (e.g. Stim Rounds) and shield "gadget" buffs
    -- never show up in GetWeaponEnchantInfo(), so also keep the poller running whenever a
    -- ranged weapon or an off-hand item (shield) is equipped at all -- otherwise the timer
    -- would never even start for those buffs.
    if hasTEnch(GetWeaponEnchantInfo()) or hasRangedItemEquipped() or hasOffhandItemEquipped() then
        if self.timer_TENCH == nil then
            self.timer_TENCH = self:ScheduleRepeatingTimer("ScanData_TENCH_Worker", .5)
            self:ScanData_TENCH_Worker()
        end
    elseif self.timer_TENCH ~= nil then
        self:CancelTimer(self.timer_TENCH)
        self.timer_TENCH = nil
        self:ScanData_TENCH_Worker()
    end
end

function ElkBuffBars:ScanData_TENCH_Worker()
    -- hasTEnchUpdate() alone would never be true for a ranged/shield gadget buff
    -- (GetWeaponEnchantInfo never reflects it, so it never "changes"), so also force a
    -- rescan every tick while a ranged weapon or off-hand item is equipped, to keep its
    -- tooltip-scanned duration fresh.
    if hasTEnchUpdate(GetWeaponEnchantInfo()) or hasRangedItemEquipped() or hasOffhandItemEquipped() then
        self:ScanData_TENCH()
        self:UpdateGroups()
    end
end
--

function ElkBuffBars:ScanData_TENCH()
    self:ScanData_TENCH_Helper(GetWeaponEnchantInfo())
end

function ElkBuffBars:ScanData_TENCH_Helper(...)
    refreshTEnchBuffer(...)
    local maxtimes = self.db.global.maxtimes.TENCH
    local maxcharges = self.db.global.maxcharges.TENCH
    for k, v in pairs(self.tenchdata) do
        RecycleDataTable(v)
        self.tenchdata[k] = nil
    end

    -- see function TemporaryEnchantFrame_Update(...) in FrameXML/BuffFrame.lua
    local value_GetTime = GetTime()
    local RETURNS_PER_ITEM = 4
    local numVals = select("#", ...)
    local numItems = numVals / RETURNS_PER_ITEM
    for itemIndex = 1, numItems do
        local hasEnchant, enchantExpiration, enchantCharges, enchantId = select(RETURNS_PER_ITEM * (itemIndex - 1) + 1, ...)
        if hasEnchant then
            if enchantExpiration then
                enchantExpiration = enchantExpiration / 1000
            end
            local timemax = enchantExpiration or 0

            local id = TENCH_INVENTORYSLOT[itemIndex]
            local name, rank = self:GetTempBuffName(id, enchantId)
            self:AddKnownName("TENCH", name, (UnitClass("player")))
    --		if rank then
    --			rank = string_match(rank, PATTERN_RANK)
    --		end
            -- Some Ascension-custom weapon enchants (e.g. "Ice Engraving") don't come back
            -- with a real enchantId from GetWeaponEnchantInfo(), which crashed here with
            -- "table index is nil" the moment one was equipped. Just skip the smoothing
            -- cache for those instead of erroring -- the bar still works fine without it.
            if enchantId then
                if maxtimes[enchantId] and timemax < maxtimes[enchantId] then
                    timemax = maxtimes[enchantId]
                else
                    maxtimes[enchantId] = timemax
                end
            end
            local charges = enchantCharges or 0
            if enchantId and charges > 1 and (not maxcharges[enchantId] or maxcharges[enchantId] < charges) then
                maxcharges[enchantId] = charges
            end

            local dt = GetDataTable()
            dt.id				= id
            dt.spellid			= enchantId
            dt.name				= self.db.profile.nameoverride.TENCH[name] or name
            dt.realname			= name
            dt.rank				= rank and tonumber(rank) or nil
            dt.type				= self.db.profile.typeoverride.TENCH[name] or "TENCH"
            dt.realtype			= "TENCH"
            dt.debufftype		= nil
            dt.expirytime		= timemax + value_GetTime
            dt.timemax			= timemax
            dt.timeMod			= 0
            dt.untilcancelled	= nil
            dt.charges			= charges
            dt.maxcharges		= maxcharges[enchantId]
            dt.icon				= GetInventoryItemTexture("player", id)
            dt.ismine			= true
            dt.casterName		= GetUnitName("player", true) or UNKNOWN
            dt.casterClass		= (UnitClassBase("player")) or ""
            dt.canStealOrPurge	= false

            table_insert(self.tenchdata, dt)
        end
    end

    -- Ranged-weapon "gadget" buffs (e.g. engineering Stim Rounds) never come through
    -- GetWeaponEnchantInfo() on this client, so fall back to scanning the ranged item's own
    -- tooltip for a "Name (X min)" style line. Skip it if the normal loop above already added
    -- something for that slot, to avoid double-listing it if Ascension ever fixes the API.
    local rangedSlot = TENCH_INVENTORYSLOT[3]
    if rangedSlot then
        local alreadyHandled = false
        for _, dt in ipairs(self.tenchdata) do
            if dt.id == rangedSlot then
                alreadyHandled = true
                break
            end
        end
        if not alreadyHandled then
            local gadgetName, gadgetSeconds = self:GetGadgetBuffInfo(rangedSlot)
            if gadgetName then
                self:AddKnownName("TENCH", gadgetName, (UnitClass("player")))

                local dt = GetDataTable()
                dt.id				= rangedSlot
                dt.spellid			= nil
                dt.name				= self.db.profile.nameoverride.TENCH[gadgetName] or gadgetName
                dt.realname			= gadgetName
                dt.rank				= nil
                dt.type				= self.db.profile.typeoverride.TENCH[gadgetName] or "TENCH"
                dt.realtype			= "TENCH"
                dt.debufftype		= nil
                dt.expirytime		= gadgetSeconds + value_GetTime
                dt.timemax			= gadgetSeconds
                dt.timeMod			= 0
                dt.untilcancelled	= nil
                dt.charges			= 0
                dt.maxcharges		= nil
                dt.icon				= GetInventoryItemTexture("player", rangedSlot)
                dt.ismine			= true
                dt.casterName		= GetUnitName("player", true) or UNKNOWN
                dt.casterClass		= (UnitClassBase("player")) or ""
                dt.canStealOrPurge	= false

                table_insert(self.tenchdata, dt)
            end
        end
    end

    -- Same story for shields: some Ascension shields grant a "gadget"-style buff (e.g. a
    -- block/reflect proc) that never comes through GetWeaponEnchantInfo() either, since that
    -- API only reports classic temporary weapon enchants (poisons, sharpening stones, etc.).
    -- Fall back to scanning the off-hand item's own tooltip the same way as the ranged slot.
    local offhandSlot = TENCH_INVENTORYSLOT[2]
    if offhandSlot then
        local alreadyHandled = false
        for _, dt in ipairs(self.tenchdata) do
            if dt.id == offhandSlot then
                alreadyHandled = true
                break
            end
        end
        if not alreadyHandled then
            local gadgetName, gadgetSeconds = self:GetGadgetBuffInfo(offhandSlot)
            if gadgetName then
                self:AddKnownName("TENCH", gadgetName, (UnitClass("player")))

                local dt = GetDataTable()
                dt.id				= offhandSlot
                dt.spellid			= nil
                dt.name				= self.db.profile.nameoverride.TENCH[gadgetName] or gadgetName
                dt.realname			= gadgetName
                dt.rank				= nil
                dt.type				= self.db.profile.typeoverride.TENCH[gadgetName] or "TENCH"
                dt.realtype			= "TENCH"
                dt.debufftype		= nil
                dt.expirytime		= gadgetSeconds + value_GetTime
                dt.timemax			= gadgetSeconds
                dt.timeMod			= 0
                dt.untilcancelled	= nil
                dt.charges			= 0
                dt.maxcharges		= nil
                dt.icon				= GetInventoryItemTexture("player", offhandSlot)
                dt.ismine			= true
                dt.casterName		= GetUnitName("player", true) or UNKNOWN
                dt.casterClass		= (UnitClassBase("player")) or ""
                dt.canStealOrPurge	= false

                table_insert(self.tenchdata, dt)
            end
        end
    end

    scan_happened.player = true
end

function ElkBuffBars:ScanData_TRACKING()
    for k, v in pairs(self.trackingdata) do
        RecycleDataTable(v)
        self.trackingdata[k] = nil
    end

    if isTrackingDisabled then
        return
    end

    if CURRENT_EXPANSION_LEVEL >= (LE_EXPANSION_BURNING_CRUSADE or 1) then
        local name = "Tracking"
        self:AddKnownName("TRACKING", name, (UnitClass("player")))
        local dt = GetDataTable()
        dt.id				= 1
        dt.spellid			= nil
        dt.name				= self.db.profile.nameoverride.TRACKING[name] or name
        dt.realname			= name
        dt.rank				= nil
        dt.type				= self.db.profile.typeoverride.TRACKING[name] or "TRACKING"
        dt.realtype			= "TRACKING"
        dt.debufftype		= nil
        dt.expirytime		= 0
        dt.timemax			= 0
        dt.timeMod			= 0
        dt.untilcancelled	= true
        dt.charges			= 0
        dt.maxcharges		= nil
        dt.icon				= [[Interface\Minimap\Tracking\None]]
        dt.ismine			= true
        dt.casterName		= GetUnitName("player", true) or UNKNOWN
        dt.casterClass		= (UnitClassBase("player")) or ""
        dt.canStealOrPurge	= false
        table_insert(self.trackingdata, dt)
        return
    end

    local icon = GetTrackingTexture()
    if icon then
        local name = self:GetTrackingName()
        self:AddKnownName("TRACKING", name, (UnitClass("player")))
        local dt = GetDataTable()
        dt.id				= 1
        dt.spellid			= nil
        dt.name				= self.db.profile.nameoverride.TRACKING[name] or name
        dt.realname			= name
        dt.rank				= nil
        dt.type				= self.db.profile.typeoverride.TRACKING[name] or "TRACKING"
        dt.realtype			= "TRACKING"
        dt.debufftype		= nil
        dt.expirytime		= 0
        dt.timemax			= 0
        dt.timeMod			= 0
        dt.untilcancelled	= true
        dt.charges			= 0
        dt.maxcharges		= nil
        dt.icon				= icon
        dt.ismine			= true
        dt.casterName		= GetUnitName("player", true) or UNKNOWN
        dt.casterClass		= (UnitClassBase("player")) or ""
        dt.canStealOrPurge	= false
        table_insert(self.trackingdata, dt)
    end
    scan_happened.player = true
end


local selfcast = {
    pet = true,
    player = true,
    vehicle = true,
}
function ElkBuffBars:ScanData_UnitAura(unit, auratype)
    local filter = auratype == "DEBUFF" and "HARMFUL" or "HELPFUL"
    local maxcharges = self.db.global.maxcharges[auratype]
    local datatable = auratype == "DEBUFF" and self.debuffdata[unit] or self.buffdata[unit]
    if not datatable then return end
    for k, v in pairs(datatable) do
        RecycleDataTable(v)
        datatable[k] = nil
    end
    local i = 1
    while true do
        --    name, texture, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isCastByPlayer, nameplateShowAll, timeMod...
        local name, texture, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isCastByPlayer, nameplateShowAll, timeMod
        if UNITAURA_HAS_RANK then
            local _rank -- unused legacy "rank" field, see UNITAURA_HAS_RANK above
            name, _rank, texture, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isCastByPlayer, nameplateShowAll, timeMod = UnitAura(unit, i, filter)
        else
            name, texture, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isCastByPlayer, nameplateShowAll, timeMod = UnitAura(unit, i, filter)
        end
        if not texture then break end
--		print(unit, name, tostring(name.utf8len), tostring(issecure()))
        self:AddKnownName(auratype, name, (UnitClass(unit)), spellId)
        count = count or 0
        if count > 1 and (type(maxcharges[name]) ~= "number" or maxcharges[name] < count) then
            -- (type-checked instead of a plain nil check: sessions before the UNITAURA_HAS_RANK
            -- fix above could have cached a texture-path string here instead of a number)
            maxcharges[name] = count
        end

        local dt = GetDataTable()
        dt.id				= i
        dt.spellid			= spellId
        dt.name				= self.db.profile.nameoverride[auratype][name] or name
        dt.realname			= name
        dt.rank				= nil
        dt.type				= (self.db.profile.typeoverride[auratype][name] or auratype)
        dt.realtype			= auratype
        dt.debufftype		= debuffType
        dt.expirytime		= expirationTime
        dt.timemax			= duration or 0
        dt.timeMod			= (timeMod and timeMod > 0) and timeMod or 0
        dt.untilcancelled	= ((not duration) or duration == 0) and true or nil
        dt.charges			= count
        dt.maxcharges		= maxcharges[name]
        dt.icon				= texture
        dt.ismine			= unitCaster and selfcast[unitCaster] and true or false
        dt.casterName		= unitCaster and GetUnitName(unitCaster, true) or UNKNOWN
        dt.casterClass		= unitCaster and (UnitClassBase(unitCaster)) or ""
        dt.canStealOrPurge	= canStealOrPurge

        table_insert(datatable, dt)
        i = i + 1
    end
    scan_happened[unit] = true
end

local roman_to_arabic = setmetatable({I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000}, {__index=function(self, roman)
    local arabic = 0
    local maxval = 0
    for i = roman:len(), 1, -1 do
        local digitval = self[roman:sub(i,i)]
        if digitval < maxval then
            arabic = arabic - digitval
        else
            arabic = arabic + digitval
            maxval = digitval
        end
    end
    self[roman] = arabic
    return arabic
end})

local tooltipScanner = nil
local function getTooltipScanner()
    if tooltipScanner ~= nil then
        return tooltipScanner
    end

    if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        tooltipScanner = {}

        function tooltipScanner:GetEnchantNameForPlayerSlot(slot)
            local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
            for _, line in ipairs(tooltipData.lines) do
                if line.type == Enum.TooltipDataLineType.None then
                    -- tooltip example: Venomhide Poison (5 min) (15 Charges)
                    local match = select(3, string_find(line.leftText, "^(.+) %(%d+ [^%)]+%)$")) -- removes 1st bracket (time left / charges)
                    if match then
                        match = string_gsub(match, " %(%d+ [^%)]+%)", "") -- removes 2nd bracket (time left for buffs with charges)
                        return match
                    end
                end
            end

            return nil
        end

        function tooltipScanner:GetEnchantDurationForPlayerSlot(slot)
            local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
            for _, line in ipairs(tooltipData.lines) do
                if line.type == Enum.TooltipDataLineType.None then
                    local text = line.leftText
                    for num, unit in string_gmatch(text, "%((%d+) (%a+)%)") do
                        if string_find(unit, "^min") or string_find(unit, "^sec") or string_find(unit, "^hour") or string_find(unit, "^hr") then
                            local seconds = tonumber(num) or 0
                            if string_find(unit, "^hour") or string_find(unit, "^hr") then
                                seconds = seconds * 3600
                            elseif string_find(unit, "^min") then
                                seconds = seconds * 60
                            end
                            local name = select(3, string_find(text, "^(.+) %(%d+ [^%)]+%)$")) or text
                            name = string_gsub(name, " %(%d+ [^%)]+%)", "")
                            return name, seconds
                        end
                    end
                end
            end
            return nil
        end
    else
        -- "SharedTooltipTemplate" doesn't exist in Ascension's (pre-refactor) FrameXML, which
        -- made CreateFrame() throw here and silently kill weapon-buff/tracking name scanning
        -- for the rest of the session. Fall back to the classic "GameTooltipTemplate", which
        -- has been present since Vanilla/Wrath and provides the same FontString-based lines.
        local ok
        ok, tooltipScanner = pcall(CreateFrame, "GameTooltip", "ElkBuffBarsTooltipScanner", nil, "SharedTooltipTemplate")
        if not ok or not tooltipScanner then
            tooltipScanner = CreateFrame("GameTooltip", "ElkBuffBarsTooltipScanner", nil, "GameTooltipTemplate")
        end
        tooltipScanner:SetOwner(UIParent, "ANCHOR_NONE")

        function tooltipScanner:GetEnchantNameForPlayerSlot(slot)
            self:ClearLines()
            self:SetInventoryItem("player", slot)
            local regions = {self:GetRegions()}
            for _, r in ipairs(regions) do
                if r:IsObjectType("FontString") then
                    local text = r:GetText()
                    if text then
                        -- tooltip example: Venomhide Poison (5 min) (15 Charges)
                        local match = select(3, string_find(text, "^(.+) %(%d+ [^%)]+%)$")) -- removes 1st bracket (time left / charges)
                        if match then
                            match = string_gsub(match, " %(%d+ [^%)]+%)", "") -- removes 2nd bracket (time left for buffs with charges)
                            return match
                        end
                    end
                end
            end
            return nil
        end

        function tooltipScanner:GetTrackingName()
            self:ClearLines()
            self:SetTrackingSpell()
            return self.TextLeft1:GetText()
        end

        -- Ascension's GetWeaponEnchantInfo() never reports ranged-weapon "gadget" buffs
        -- (e.g. engineering Stim Rounds) even while one is actively ticking down -- confirmed
        -- by testing, it stays nil across the board. But the remaining time still shows up as
        -- plain tooltip text on the item itself (e.g. "Stim Rounds (58 min)"), so scan for that
        -- directly instead of relying on the (broken, for this case) enchant API.
        function tooltipScanner:GetEnchantDurationForPlayerSlot(slot)
            self:ClearLines()
            self:SetInventoryItem("player", slot)
            local regions = {self:GetRegions()}
            for _, r in ipairs(regions) do
                if r:IsObjectType("FontString") then
                    local text = r:GetText()
                    if text then
                        for num, unit in string_gmatch(text, "%((%d+) (%a+)%)") do
                            if string_find(unit, "^min") or string_find(unit, "^sec") or string_find(unit, "^hour") or string_find(unit, "^hr") then
                                local seconds = tonumber(num) or 0
                                if string_find(unit, "^hour") or string_find(unit, "^hr") then
                                    seconds = seconds * 3600
                                elseif string_find(unit, "^min") then
                                    seconds = seconds * 60
                                end
                                local name = select(3, string_find(text, "^(.+) %(%d+ [^%)]+%)$")) or text
                                name = string_gsub(name, " %(%d+ [^%)]+%)", "")
                                return name, seconds
                            end
                        end
                    end
                end
            end
            return nil
        end
    end

    return tooltipScanner
end

local enchantNameCache = {}
function ElkBuffBars:GetTempBuffName(slot, enchantId)
    local enchantName = enchantNameCache[enchantId]
    if enchantName then return enchantName end

    local scanner = getTooltipScanner()
    enchantName = scanner:GetEnchantNameForPlayerSlot(slot)
    if enchantName then
        enchantName = string_gsub(enchantName, " %(%d+ [^%)]+%)", "") -- removes 2nd bracket (time left for buffs with charges)
        local tname, rank = string_match(enchantName, "^(.*) (%d+)$")
        if tname then
            enchantName = tname
        else
            tname, rank = string_match(enchantName, "^(.*) ([CDILMVX]+)$")
            if tname then
                enchantName = tname
                rank = roman_to_arabic[rank]
            end
        end
        if enchantId then
            -- some Ascension-custom enchants have no real enchantId; just skip caching those
            enchantNameCache[enchantId] = enchantName
        end
        return enchantName, rank
    end

    -- fall back to the item's name instead
    local itemlink = GetInventoryItemLink("player", slot)
    if itemlink then
        local name = GetItemInfo(itemlink)
        return name or ("Weapon "..slot)
    end
    return "Weapon "..slot
end

function ElkBuffBars:GetTrackingName()
    local scanner = getTooltipScanner()
    local name = scanner:GetTrackingName()
    return name or "Tracking..."
end

function ElkBuffBars:GetGadgetBuffInfo(slot)
    local scanner = getTooltipScanner()
    return scanner:GetEnchantDurationForPlayerSlot(slot)
end

function ElkBuffBars:DoFullUpdate()
    self:UNIT_AURA(watched_unitids)
    self:ScanData_TENCH()
    self:UpdateGroups()
end

function ElkBuffBars:UpdateGroups()
    -- if we did a scan, poke bar groups for updates
    if next(scan_happened) then
        for _, bg in pairs(self.bargroups) do
            bg:UpdateData(scan_happened)
        end
        table_wipe(scan_happened)
    end
end

local function StickGroup_CheckLoop(self, id, v)
    local parent = v
    while parent.layout.stickto do
        if parent.layout.stickto == id then
            return true
        end
        parent = self.bargroups[parent.layout.stickto]
    end
    return false
end

-- finds the CLOSEST valid stick target across every other group and both orientations
-- (stacked above/below, or side-by-side) instead of sticking to whichever candidate pairs()
-- happens to visit first. Table iteration order is unspecified, so with more than one group
-- in range at once, the old first-match-wins approach could snap to the wrong neighbor, or
-- even effectively split the difference between two candidates across repeated attempts --
-- not a mis-detection, just a right-detection-wrong-pick. Score is "how far off the touching
-- edge is" plus "how far off the alignment is", in pixels, so vertical and horizontal
-- candidates are directly comparable on the same scale; lower wins.
function ElkBuffBars:StickGroup(bargroup)
    local layout = bargroup.layout
    local id = layout.id
    local growup = layout.growup
    local container = bargroup:GetContainer()
    local base_y = growup and container:GetBottom() or container:GetTop()
    local base_left = container:GetLeft()
    local base_right = container:GetRight()
    local base_top = container:GetTop()
    local base_bottom = container:GetBottom()

    local best -- { score, k, stickmode, stickside, stickvalign }

    for k, v in pairs(self.bargroups) do
        if v.layout.id ~= id and not StickGroup_CheckLoop(self, id, v) then
            local comp_container = v:GetContainer()
            local comp_top = comp_container:GetTop()
            local comp_bottom = comp_container:GetBottom()
            local comp_left = comp_container:GetLeft()
            local comp_right = comp_container:GetRight()

            -- vertical: stack above/below -- my touching edge near their opposite edge,
            -- aligned left/center/right
            local comp_y = growup and comp_top or comp_bottom
            local ygap = comp_y and math_abs(comp_y - base_y)
            if ygap and ygap <= STICKTO_AREA then
                local dist_left = math_abs(base_left - comp_left)
                local dist_mid = math_abs((base_left + base_right) - (comp_left + comp_right)) / 2
                local dist_right = math_abs(base_right - comp_right)
                local stickside, aligndist = nil, STICKTO_AREA
                if dist_mid <= aligndist then stickside, aligndist = "", dist_mid end
                if dist_left <= STICKTO_AREA and dist_left < aligndist then stickside, aligndist = "LEFT", dist_left end
                if dist_right <= STICKTO_AREA and dist_right < aligndist then stickside, aligndist = "RIGHT", dist_right end
                if stickside then
                    local score = ygap + aligndist
                    if not best or score < best.score then
                        best = { score = score, k = k, stickmode = "vertical", stickside = stickside }
                    end
                end
            end

            -- horizontal: side-by-side -- my left/right edge near their opposite edge,
            -- aligned top/middle/bottom
            local dist_myleft_theirright = math_abs(base_left - comp_right)
            local dist_myright_theirleft = math_abs(base_right - comp_left)
            local xgap = math_min(dist_myleft_theirright, dist_myright_theirleft)
            if xgap <= STICKTO_AREA then
                local dist_top = math_abs(base_top - comp_top)
                local dist_vmid = math_abs((base_top + base_bottom) - (comp_top + comp_bottom)) / 2
                local dist_bottom = math_abs(base_bottom - comp_bottom)
                local stickvalign, aligndist = nil, STICKTO_AREA
                if dist_vmid <= aligndist then stickvalign, aligndist = "", dist_vmid end
                if dist_top <= STICKTO_AREA and dist_top < aligndist then stickvalign, aligndist = "TOP", dist_top end
                if dist_bottom <= STICKTO_AREA and dist_bottom < aligndist then stickvalign, aligndist = "BOTTOM", dist_bottom end
                if stickvalign then
                    local score = xgap + aligndist
                    if not best or score < best.score then
                        best = {
                            score = score, k = k, stickmode = "horizontal",
                            stickside = (dist_myleft_theirright <= dist_myright_theirleft) and "LEFT" or "RIGHT",
                            stickvalign = stickvalign,
                        }
                    end
                end
            end
        end
    end

    layout.stickto = best and best.k or nil
    layout.stickmode = best and best.stickmode or nil
    layout.stickside = best and best.stickside or nil
    layout.stickvalign = best and best.stickvalign or nil

    if best then
        bargroup:SetPosition()
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Options

function ElkBuffBars:GetOptions()
    if self.options then
        return self.options
    end

    self.options = {
        type = "group",
        childGroups = "tab",
        args = {
            general = {
                order = 100,
                type = "group",
                name = GENERAL,
                args = {
                    -- 101:
                    -- 102:
                    newgroup = {
                        order = 103,
                        type = "execute",
                        name = L["OPTIONS_NEWGROUP_NAME"],
                        desc = L["OPTIONS_NEWGROUP_DESC"],
                        func = function()
                            local bg = ElkBuffBars:AddBarGroup()
                            bg:SetPosition()
                            bg:GetContainer():Show()
                        end,
                    },
                    groupspacing = {
                        order = 104,
                        type = "range",
                        name = L["OPTIONS_GROUPSPACING_NAME"],
                        desc = L["OPTIONS_GROUPSPACING_DESC"],
                        min = 0, max = 50, step = 1,
                        get = function(info) return ElkBuffBars.db.profile.groupspacing end,
                        set = function(info, v)
                            ElkBuffBars.db.profile.groupspacing = v
                            for _, bg in ipairs(ElkBuffBars.bargroups) do
                                bg:SetPosition()
                            end
                        end,
                    },
                    buffframe = {
                        order = 105,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_HIDEBLIZZARDBUFFS_NAME"],
                        desc = L["OPTIONS_HIDEBLIZZARDBUFFS_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.hidebuffframe end,
                        set = function(info, v)
                            ElkBuffBars.db.profile.hidebuffframe = v
                            ElkBuffBars:HandleFrame_Blizzard_BuffFrame(ElkBuffBars.db.profile.hidebuffframe)
                        end,
                    },
                    vanitybuffs = {
                        order = 105.5,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_HIDEVANITYBUFFS_NAME"],
                        desc = L["OPTIONS_HIDEVANITYBUFFS_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.hidevanitybuffs end,
                        set = function(info, v)
                            ElkBuffBars.db.profile.hidevanitybuffs = v
                            ElkBuffBars:HandleFrame_Blizzard_VanityBuffs(ElkBuffBars.db.profile.hidevanitybuffs)
                        end,
                    },
                    tenchframe = {
                        order = 106,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_HIDEBLIZZARDTENCH_NAME"],
                        desc = L["OPTIONS_HIDEBLIZZARDTENCH_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.hidetenchframe end,
                        set = function(info, v)
                            ElkBuffBars.db.profile.hidetenchframe = v
                            ElkBuffBars:HandleFrame_Blizzard_TemporaryEnchantFrame(ElkBuffBars.db.profile.hidetenchframe)
                        end,
                    },
                    trackingframe = {
                        order = 107,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_HIDEBLIZZARDTRACKING_NAME"],
                        desc = L["OPTIONS_HIDEBLIZZARDTRACKING_DESC"],
                        disabled = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE,
                        get = function(info)
                            if WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then return false end
                            return ElkBuffBars.db.profile.hidetrackingframe
                        end,
                        set = function(info, v)
                            ElkBuffBars.db.profile.hidetrackingframe = v
                            ElkBuffBars:HandleFrame_Blizzard_MiniMapTracking(ElkBuffBars.db.profile.hidetrackingframe)
                        end,
                    },
                    minimap = {
                        order = 108,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_MINIMAP_NAME"],
                        desc = L["OPTIONS_MINIMAP_DESC"],
                        get = function(info) return not ElkBuffBars.db.profile.minimap.hide end,
                        set = function(info, value)
                            ElkBuffBars.db.profile.minimap.hide = not value
                            LibStub("LibDBIcon-1.0"):Refresh(ELKBUFFBARS)
                        end,
                    },
                },
            },
            buffsettings = {
                order = 101,
                type = "group",
                name = L["OPTIONS_OVERRIDES_NAME"],
                desc = L["OPTIONS_OVERRIDES_DESC"],
                args = {
                    BUFF = {
                        type = "group",
                        name = L["AURATYPE_BUFF"],
                        args = {},
                    },
                    DEBUFF = {
                        type = "group",
                        name = L["AURATYPE_DEBUFF"],
                        args = {},
                    },
                    TENCH = {
                        type = "group",
                        name = L["AURATYPE_TENCH"],
                        args = {},
                    },
                    TRACKING = {
                        type = "group",
                        name = L["AURATYPE_TRACKING"],
                        args = {},
                    },
                },
            },
            groupsettings = {
                order = 102,
                type = "group",
                name = L["OPTIONS_BARGROUPS_NAME"],
                desc = L["OPTIONS_BARGROUPS_DESC"],
                args = {
                    ["0"] = {
                        order = 0,
                        type = "group",
                        name = L["OPTIONS_ALLGROUPS_NAME"],
                        desc = L["OPTIONS_ALLGROUPS_DESC"],
                        args = {
                            configmode = {
                                order = 101,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_CONFIG_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_CONFIG_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.configmode then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg:ToggleConfigMode(value)
                                    end
                                end,
                            },
                            anchorshown = {
                                order = 102,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_ANCHOR_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_ANCHOR_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.anchorshown then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.anchorshown = value
                                        bg:UpdateAnchor()
                                    end
                                end,
                            },
                            hideanchorwhenempty = {
                                order = 102.5,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_HIDEANCHOREMPTY_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_HIDEANCHOREMPTY_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.hideanchorwhenempty then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.hideanchorwhenempty = value
                                        bg:RefreshAnchorVisibility()
                                    end
                                end,
                            },
                            hideincombat = {
                                order = 102.6,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_HIDEINCOMBAT_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_HIDEINCOMBAT_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.hideincombat then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.hideincombat = value
                                        bg:RefreshContainerVisibility()
                                    end
                                end,
                            },
                            hidewhennomissing = {
                                order = 102.7,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_HIDEWHENNOMISSING_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_HIDEWHENNOMISSING_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.hidewhennomissing then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.hidewhennomissing = value
                                        bg:RefreshContainerVisibility()
                                    end
                                end,
                            },
                            hidewhenallmissing = {
                                order = 102.8,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_HIDEWHENALLMISSING_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_HIDEWHENALLMISSING_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.hidewhenallmissing then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.hidewhenallmissing = value
                                        bg:RefreshContainerVisibility()
                                    end
                                end,
                            },
                            hideunlesssoon = {
                                order = 102.85,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_HIDEUNLESSSOON_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_HIDEUNLESSSOON_DESC"],
                                get = function(info)
                                    for _, bg in ipairs(ElkBuffBars.db.profile.bargroups) do
                                        if not bg.hideunlesssoon then return false end
                                    end
                                    return true
                                end,
                                set = function(info, value)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.hideunlesssoon = value
                                        bg:RefreshContainerVisibility()
                                    end
                                    ElkBuffBars:UpdateSoonToExpireTimer()
                                end,
                            },
                            hideunlesssoonseconds = {
                                order = 102.9,
                                type = "range",
                                name = L["OPTIONS_GROUP_HIDEUNLESSSOONSECONDS_NAME"],
                                desc = L["OPTIONS_ALLGROUPS_HIDEUNLESSSOONSECONDS_DESC"],
                                min = 1, max = 120, step = 1, bigStep = 5,
                                get = function(info)
                                    local bg = ElkBuffBars.db.profile.bargroups[1]
                                    return (bg and bg.hideunlesssoonseconds) or 20
                                end,
                                set = function(info, v)
                                    for _, bg in pairs(ElkBuffBars.bargroups) do
                                        bg.layout.hideunlesssoonseconds = tonumber(v)
                                        bg:RefreshContainerVisibility()
                                    end
                                end,
                            },
                        },
                    },
                },
            },
            exportimport = {
                order = 103,
                type = "group",
                name = L["OPTIONS_EXPORTIMPORT_NAME"],
                desc = L["OPTIONS_EXPORTIMPORT_DESC"],
                args = {
                    splitdesc = {
                        order = 50,
                        type = "description",
                        name = L["OPTIONS_EXPORTIMPORT_SPLIT_DESC"],
                    },
                    exportdesc = {
                        order = 100,
                        type = "description",
                        name = L["OPTIONS_EXPORT_DESC"],
                    },
                    exportstring = {
                        order = 101,
                        type = "input",
                        multiline = 10,
                        width = "full",
                        name = L["OPTIONS_EXPORT_NAME"],
                        get = function() return ElkBuffBars:ExportProfile() end,
                        set = function() end,
                    },
                    importdesc = {
                        order = 200,
                        type = "description",
                        name = L["OPTIONS_IMPORT_DESC"],
                    },
                    importstring = {
                        order = 201,
                        type = "input",
                        multiline = 10,
                        width = "full",
                        name = L["OPTIONS_IMPORT_NAME"],
                        get = function() return "" end,
                        set = function(info, value)
                            ElkBuffBars:ImportProfile(value)
                        end,
                    },
                    layoutgroup = {
                        order = 300,
                        type = "group",
                        inline = true,
                        name = L["OPTIONS_EXPORTIMPORT_LAYOUT_NAME"],
                        args = {
                            exportdesc = {
                                order = 100,
                                type = "description",
                                name = L["OPTIONS_EXPORT_LAYOUT_DESC"],
                            },
                            exportstring = {
                                order = 101,
                                type = "input",
                                multiline = 8,
                                width = "full",
                                name = L["OPTIONS_EXPORT_NAME"],
                                get = function() return ElkBuffBars:ExportLayout() end,
                                set = function() end,
                            },
                            importdesc = {
                                order = 200,
                                type = "description",
                                name = L["OPTIONS_IMPORT_LAYOUT_DESC"],
                            },
                            importstring = {
                                order = 201,
                                type = "input",
                                multiline = 8,
                                width = "full",
                                name = L["OPTIONS_IMPORT_NAME"],
                                get = function() return "" end,
                                set = function(info, value)
                                    ElkBuffBars:ImportLayout(value)
                                end,
                            },
                        },
                    },
                    buffsgroup = {
                        order = 400,
                        type = "group",
                        inline = true,
                        name = L["OPTIONS_EXPORTIMPORT_BUFFS_NAME"],
                        args = {
                            exportdesc = {
                                order = 100,
                                type = "description",
                                name = L["OPTIONS_EXPORT_BUFFS_DESC"],
                            },
                            exportstring = {
                                order = 101,
                                type = "input",
                                multiline = 8,
                                width = "full",
                                name = L["OPTIONS_EXPORT_NAME"],
                                get = function() return ElkBuffBars:ExportBuffs() end,
                                set = function() end,
                            },
                            importdesc = {
                                order = 200,
                                type = "description",
                                name = L["OPTIONS_IMPORT_BUFFS_DESC"],
                            },
                            importstring = {
                                order = 201,
                                type = "input",
                                multiline = 8,
                                width = "full",
                                name = L["OPTIONS_IMPORT_NAME"],
                                get = function() return "" end,
                                set = function(info, value)
                                    ElkBuffBars:ImportBuffs(value)
                                end,
                            },
                        },
                    },
                },
            },
        }
    }

    return self.options
end

function ElkBuffBars:ToggleOptionsWindow()
    if ACDialog.OpenFrames[ELKBUFFBARS] then
        ACDialog:Close(ELKBUFFBARS)
    else
        ACDialog:Open(ELKBUFFBARS)
    end
end

function ElkBuffBars:OpenGroupOptions(groupid)
    ACDialog:Open(ELKBUFFBARS)
    ACDialog:SelectGroup(ELKBUFFBARS, "groupsettings", tostring(groupid))
end

function ElkBuffBars:GetNameOptions(auratype, name)
    return {
        type = "group",
        name = name,
        desc = name,
        args = {
            name = {
                type = "input",
                name = L["OPTIONS_OVERRIDES_NAME_NAME"],
                desc = L["OPTIONS_OVERRIDES_NAME_DESC"],
                get = function(info) return ElkBuffBars.db.profile.nameoverride[auratype][name] end,
                set = function(info, v)
                    v = string_trim(v)
                    if v == "" or v == name then
                        ElkBuffBars.db.profile.nameoverride[auratype][name] = nil
                    else
                        ElkBuffBars.db.profile.nameoverride[auratype][name] = v
                    end
                end,
            },
            type = {
                type = "select",
                name = L["OPTIONS_OVERRIDES_TYPE_NAME"],
                desc = L["OPTIONS_OVERRIDES_TYPE_DESC"],
                values = {
                    BUFF = L["AURATYPE_BUFF"],
                    DEBUFF = L["AURATYPE_DEBUFF"],
                    TENCH = L["AURATYPE_TENCH"],
                    TRACKING = L["AURATYPE_TRACKING"],
                    [""] = L["OPTIONS_OVERRIDES_TYPE_OPTION_DEFAULT"]
                },
                get = function(info) return ElkBuffBars.db.profile.typeoverride[auratype][name] end,
                set = function(info, v)
                    v = string_trim(v)
                    if v == "" or v == auratype then
                        ElkBuffBars.db.profile.typeoverride[auratype][name] = nil
                    else
                        ElkBuffBars.db.profile.typeoverride[auratype][name] = v
                    end
                end,
            }
        }
    }
end

-- forward-declared (defined further below, near BuildClassWatchOptions) so SetSelfBuffFilter/
-- SetSelfBuffAltGroupFilter can auto-link a checked self buff into Group Watcher for your own
-- class -- see the comment on that auto-link below for why.
local SetClassTracked, SetClassBuffFilter

local function SetNameFilter(groupid, white, auratype, auraname, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local ftname = white and "names_include" or "names_exclude"
    if value then
        if not filter[ftname] then
            filter[ftname] = {}
        end
        if not filter[ftname][auratype] then
            filter[ftname][auratype] = {}
        end
        filter[ftname][auratype][auraname] = true
    elseif filter[ftname] and filter[ftname][auratype] then
        filter[ftname][auratype][auraname] = nil
        local hasdata = false
        for _ in pairs(filter[ftname][auratype]) do
            hasdata = true
            break
        end
        if not hasdata then
            filter[ftname][auratype] = nil
        end
        hasdata = false
        for _ in pairs(filter[ftname]) do
            hasdata = true
            break
        end
        if not hasdata then
            filter[ftname] = nil
        end
    end
    bg:UpdateData()
end

function ElkBuffBars:AddAuraToBlacklist(groupid, auratype, auraname)
    SetNameFilter(groupid, false, auratype, auraname, true)
end

-- "My Self Buffs" and "Self Buff Alternatives" (below) are both keyed by class first
-- (UnitClass("player")), so that two different classes sharing the same bar-group profile
-- each get their own independent set of self-buff selections instead of bleeding into each
-- other -- see migrated_perclass_selfbuffs in OnProfileEnable for the one-time migration of
-- data saved before this separation existed.
--
-- Checking a name here also auto-checks it under Group Watcher for your own class, in this
-- same bar group (and auto-tracks your own class there too, since otherwise the entry
-- wouldn't be consulted at all -- see classestracked in GetClassWatchGroups). A self buff you
-- give yourself is, by definition, something your class provides -- so if you're grouped with
-- ANOTHER member of your own class, Group Watcher should already know to check them for it,
-- without you having to configure the exact same name twice. This is one-directional and
-- additive only: unchecking a self buff does NOT remove it from Group Watcher (it may still be
-- legitimately wanted there even if you personally stopped tracking it on yourself), and
-- Group Watcher can always be given MORE names beyond whatever's mirrored from here.
local function SetSelfBuffFilter(groupid, auratype, auraname, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local class = (UnitClass("player"))
    if value then
        filter.selfbuffs = filter.selfbuffs or {}
        filter.selfbuffs[class] = filter.selfbuffs[class] or {}
        filter.selfbuffs[class][auratype] = filter.selfbuffs[class][auratype] or {}
        filter.selfbuffs[class][auratype][auraname] = true
        -- picking this as a self buff on this class IS a positive class tag, even if you've
        -- never actually seen it observed live on anyone (e.g. it's a world buff you don't
        -- have up right now) -- keeps it properly hidden from other classes' checklists.
        ElkBuffBars:AddKnownName(auratype, auraname, class)
        SetClassTracked(groupid, class, true)
        SetClassBuffFilter(groupid, class, auratype, auraname, true)
    elseif filter.selfbuffs and filter.selfbuffs[class] and filter.selfbuffs[class][auratype] then
        filter.selfbuffs[class][auratype][auraname] = nil
        local hasdata = false
        for _ in pairs(filter.selfbuffs[class][auratype]) do
            hasdata = true
            break
        end
        if not hasdata then
            filter.selfbuffs[class][auratype] = nil
        end
    end
    bg:UpdateData()
end

local SELFALTGROUP_COUNT = 4 -- number of "Self Buff Alternatives" checkbox slots per bar group

local function SetSelfBuffAltGroupFilter(groupid, groupindex, auratype, auraname, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local class = (UnitClass("player"))
    if value then
        filter.selfbuffaltgroups = filter.selfbuffaltgroups or {}
        filter.selfbuffaltgroups[class] = filter.selfbuffaltgroups[class] or {}
        filter.selfbuffaltgroups[class][groupindex] = filter.selfbuffaltgroups[class][groupindex] or {}
        filter.selfbuffaltgroups[class][groupindex][auratype] = filter.selfbuffaltgroups[class][groupindex][auratype] or {}
        filter.selfbuffaltgroups[class][groupindex][auratype][auraname] = true
        ElkBuffBars:AddKnownName(auratype, auraname, class)
        -- same auto-link into Group Watcher as SetSelfBuffFilter above -- an alt-set flavor is
        -- still a self buff your class provides.
        SetClassTracked(groupid, class, true)
        SetClassBuffFilter(groupid, class, auratype, auraname, true)
    elseif filter.selfbuffaltgroups and filter.selfbuffaltgroups[class] and filter.selfbuffaltgroups[class][groupindex] and filter.selfbuffaltgroups[class][groupindex][auratype] then
        filter.selfbuffaltgroups[class][groupindex][auratype][auraname] = nil
        local hasdata = false
        for _ in pairs(filter.selfbuffaltgroups[class][groupindex][auratype]) do
            hasdata = true
            break
        end
        if not hasdata then
            filter.selfbuffaltgroups[class][groupindex][auratype] = nil
        end
    end
    bg:UpdateData()
end

local function SetSelfBuffAltGroupCount(groupid, groupindex, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local class = (UnitClass("player"))
    filter.selfbuffaltgroups = filter.selfbuffaltgroups or {}
    filter.selfbuffaltgroups[class] = filter.selfbuffaltgroups[class] or {}
    filter.selfbuffaltgroups[class][groupindex] = filter.selfbuffaltgroups[class][groupindex] or {}
    value = tonumber(value)
    filter.selfbuffaltgroups[class][groupindex].count = (value and value > 1) and value or nil -- nil = 1 (default)
    bg:UpdateData()
end

local function SetSelfBuffAltGroupSpec(groupid, groupindex, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local class = (UnitClass("player"))
    filter.selfbuffaltgroups = filter.selfbuffaltgroups or {}
    filter.selfbuffaltgroups[class] = filter.selfbuffaltgroups[class] or {}
    filter.selfbuffaltgroups[class][groupindex] = filter.selfbuffaltgroups[class][groupindex] or {}
    filter.selfbuffaltgroups[class][groupindex].spec = (value and value ~= 0) and value or nil -- nil = any spec
    bg:UpdateData()
end

local function SetSelfBuffAltGroupOnlyGrouped(groupid, groupindex, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local class = (UnitClass("player"))
    filter.selfbuffaltgroups = filter.selfbuffaltgroups or {}
    filter.selfbuffaltgroups[class] = filter.selfbuffaltgroups[class] or {}
    filter.selfbuffaltgroups[class][groupindex] = filter.selfbuffaltgroups[class][groupindex] or {}
    filter.selfbuffaltgroups[class][groupindex].onlygrouped = value or nil
    bg:UpdateData()
end

-- when on, this set counts as satisfied if EITHER you or another party/raid member of your
-- own class currently has one of its names active -- not just you. This is what lets a set of
-- either-or class buffs (e.g. three flavors of the same buff, only one of which any single
-- Witch Hunter can have up at once) get spread across multiple same-class members in a group:
-- if another Witch Hunter already has one flavor up, this set treats that flavor as covered
-- and only asks you for one of the remaining ones. Has no effect while solo (nobody else to
-- check), so it's always safe to leave on.
local function SetSelfBuffAltGroupShared(groupid, groupindex, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    local class = (UnitClass("player"))
    filter.selfbuffaltgroups = filter.selfbuffaltgroups or {}
    filter.selfbuffaltgroups[class] = filter.selfbuffaltgroups[class] or {}
    filter.selfbuffaltgroups[class][groupindex] = filter.selfbuffaltgroups[class][groupindex] or {}
    filter.selfbuffaltgroups[class][groupindex].shared = value or nil
    bg:UpdateData()
end

-- builds the "Self Buff Alternatives" checkbox sub-tabs: for self-only buffs where only one
-- of several can be active at a time (e.g. two alternate versions of the same class's self
-- buff) -- having ANY ONE of a set's checked names active satisfies that whole set, same as
-- Class Watch, but never gated by group presence since these are self-buffs. "How Many
-- Needed" raises the bar above 1 -- e.g. 3 possible Edicts where you always have your own up
-- but also want to know if a grouped Witch Hunter has given you a DIFFERENT one: check all 3,
-- set the count to 2, and it only shows satisfied once 2 distinct ones (from any source) are
-- active, with the missing bar naming only the one(s) you don't have yet.
local function BuildSelfBuffAltGroupsOptions(id)
    -- filter.selfbuffaltgroups is keyed by class first (see SetSelfBuffAltGroupFilter etc.
    -- above), so a Chronomancer and a Witch Hunter sharing this same bar group's profile each
    -- get their own independent 4 slots instead of overwriting each other's.
    local myClass = (UnitClass("player"))
    local args = {}
    for gi = 1, SELFALTGROUP_COUNT do
        args[tostring(gi)] = {
            order = gi,
            type = "group",
            name = format(L["OPTIONS_GROUP_FILTER_SELFALTGROUP_NAME"], gi),
            desc = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_DESC"],
            args = {
                spec = {
                    order = 0.1,
                    type = "select",
                    name = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SPEC_NAME"],
                    desc = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SPEC_DESC"],
                    values = {
                        [0] = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SPEC_OPTION_ANY"],
                        [1] = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SPEC_OPTION_SPEC1"],
                        [2] = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SPEC_OPTION_SPEC2"],
                        [3] = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SPEC_OPTION_SPEC3"],
                    },
                    get = function(info)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return (ag and ag[gi] and ag[gi].spec) or 0
                    end,
                    set = function(info, v) SetSelfBuffAltGroupSpec(id, gi, v) end,
                },
                count = {
                    order = 0.2,
                    type = "input",
                    name = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_COUNT_NAME"],
                    desc = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_COUNT_DESC"],
                    pattern = "^%d+$",
                    get = function(info)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return tostring(ag and ag[gi] and ag[gi].count or 1)
                    end,
                    set = function(info, v) SetSelfBuffAltGroupCount(id, gi, v) end,
                },
                onlygrouped = {
                    order = 0.3,
                    type = "toggle",
                    width = "full",
                    name = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_ONLYGROUPED_NAME"],
                    desc = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_ONLYGROUPED_DESC"],
                    get = function(info)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return (ag and ag[gi] and ag[gi].onlygrouped) or false
                    end,
                    set = function(info, v) SetSelfBuffAltGroupOnlyGrouped(id, gi, v) end,
                },
                shared = {
                    order = 0.4,
                    type = "toggle",
                    width = "full",
                    name = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SHARED_NAME"],
                    desc = L["OPTIONS_GROUP_FILTER_SELFALTGROUP_SHARED_DESC"],
                    get = function(info)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return (ag and ag[gi] and ag[gi].shared) or false
                    end,
                    set = function(info, v) SetSelfBuffAltGroupShared(id, gi, v) end,
                },
                search = BuildSearchBoxOption("selfaltgroup_"..id.."_"..gi),
                BUFF = BuildNameChecklist("BUFF", "selfaltgroup_"..id.."_"..gi, myClass,
                    function(name)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return ag and ag[gi] and ag[gi].BUFF and ag[gi].BUFF[name] or false
                    end,
                    function(name, value) SetSelfBuffAltGroupFilter(id, gi, "BUFF", name, value) end,
                    1, L["AURATYPE_BUFF"]),
                DEBUFF = BuildNameChecklist("DEBUFF", "selfaltgroup_"..id.."_"..gi, myClass,
                    function(name)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return ag and ag[gi] and ag[gi].DEBUFF and ag[gi].DEBUFF[name] or false
                    end,
                    function(name, value) SetSelfBuffAltGroupFilter(id, gi, "DEBUFF", name, value) end,
                    2, L["AURATYPE_DEBUFF"]),
                TENCH = BuildNameChecklist("TENCH", "selfaltgroup_"..id.."_"..gi, myClass,
                    function(name)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return ag and ag[gi] and ag[gi].TENCH and ag[gi].TENCH[name] or false
                    end,
                    function(name, value) SetSelfBuffAltGroupFilter(id, gi, "TENCH", name, value) end,
                    3, L["AURATYPE_TENCH"]),
                TRACKING = BuildNameChecklist("TRACKING", "selfaltgroup_"..id.."_"..gi, myClass,
                    function(name)
                        local ag = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffaltgroups
                        ag = ag and ag[myClass]
                        return ag and ag[gi] and ag[gi].TRACKING and ag[gi].TRACKING[name] or false
                    end,
                    function(name, value) SetSelfBuffAltGroupFilter(id, gi, "TRACKING", name, value) end,
                    4, L["AURATYPE_TRACKING"]),
            },
        }
    end
    return args
end

function SetClassTracked(groupid, classname, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    if value then
        filter.classestracked = filter.classestracked or {}
        filter.classestracked[classname] = true
    elseif filter.classestracked then
        filter.classestracked[classname] = nil
    end
    bg:UpdateData()
end

function SetClassBuffFilter(groupid, classname, auratype, auraname, value)
    local bg = ElkBuffBars.bargroups[groupid]
    local filter = bg.layout.filter
    if value then
        filter.classbuffs = filter.classbuffs or {}
        filter.classbuffs[classname] = filter.classbuffs[classname] or {}
        filter.classbuffs[classname][auratype] = filter.classbuffs[classname][auratype] or {}
        filter.classbuffs[classname][auratype][auraname] = true
    elseif filter.classbuffs and filter.classbuffs[classname] and filter.classbuffs[classname][auratype] then
        filter.classbuffs[classname][auratype][auraname] = nil
        local hasdata = false
        for _ in pairs(filter.classbuffs[classname][auratype]) do
            hasdata = true
            break
        end
        if not hasdata then
            filter.classbuffs[classname][auratype] = nil
        end
    end
    bg:UpdateData()
end

-- builds the Class Watch tab for a given bar group id: a single checklist of every class
-- name ever seen (your own alts, plus anyone you've grouped with -- never freely typed, so
-- there's no way to misspell one), and one buff-name sub-checklist per class you've checked,
-- mirroring the White List / Black List multiselect structure. A checked class's buffs are
-- only consulted for Show Missing while a group member of that exact class is present in
-- your party/raid.
local function BuildClassWatchOptions(id)
    local args = {
        addclass = {
            order = 0,
            type = "input",
            width = "full",
            name = L["OPTIONS_GROUP_FILTER_CLASSWATCH_ADDCLASS_NAME"],
            desc = L["OPTIONS_GROUP_FILTER_CLASSWATCH_ADDCLASS_DESC"],
            get = false,
            set = function(info, v)
                v = string_trim(v or "")
                if v ~= "" then
                    ElkBuffBars:AddKnownClass(v)
                end
            end,
        },
        classestracked = {
            order = 1,
            type = "multiselect",
            name = L["OPTIONS_GROUP_FILTER_CLASSWATCH_TRACKED_NAME"],
            values = knownclasses_validate,
            get = function(info, i)
                local ct = ElkBuffBars.db.profile.bargroups[id].filter.classestracked
                return ct and ct[knownclasses_validate[i]] or false
            end,
            set = function(info, i, value) SetClassTracked(id, knownclasses_validate[i], value) end,
        },
    }
    -- one sub-group per known class, always present in the tree but hidden unless that
    -- class is currently checked above -- built this way (instead of only for checked
    -- classes) because this options table is only constructed once per bar group, so a
    -- class checked later still needs its entry to already exist for "hidden" to reveal it
    for i, classname in ipairs(knownclasses_validate) do
        args["class_"..classname] = {
            order = 1 + i,
            type = "group",
            name = classname,
            desc = L["OPTIONS_GROUP_FILTER_CLASSWATCH_PERCLASS_DESC"],
            hidden = function(info)
                local ct = ElkBuffBars.db.profile.bargroups[id].filter.classestracked
                return not (ct and ct[classname])
            end,
            args = {
                    search = BuildSearchBoxOption("classwatch_"..id.."_"..classname),
                    BUFF = BuildNameChecklist("BUFF", "classwatch_"..id.."_"..classname, classname,
                        function(name)
                            local cb = ElkBuffBars.db.profile.bargroups[id].filter.classbuffs
                            return cb and cb[classname] and cb[classname].BUFF and cb[classname].BUFF[name] or false
                        end,
                        function(name, value) SetClassBuffFilter(id, classname, "BUFF", name, value) end,
                        1, L["AURATYPE_BUFF"]),
                    DEBUFF = BuildNameChecklist("DEBUFF", "classwatch_"..id.."_"..classname, classname,
                        function(name)
                            local cb = ElkBuffBars.db.profile.bargroups[id].filter.classbuffs
                            return cb and cb[classname] and cb[classname].DEBUFF and cb[classname].DEBUFF[name] or false
                        end,
                        function(name, value) SetClassBuffFilter(id, classname, "DEBUFF", name, value) end,
                        2, L["AURATYPE_DEBUFF"]),
                    TENCH = BuildNameChecklist("TENCH", "classwatch_"..id.."_"..classname, classname,
                        function(name)
                            local cb = ElkBuffBars.db.profile.bargroups[id].filter.classbuffs
                            return cb and cb[classname] and cb[classname].TENCH and cb[classname].TENCH[name] or false
                        end,
                        function(name, value) SetClassBuffFilter(id, classname, "TENCH", name, value) end,
                        3, L["AURATYPE_TENCH"]),
                    TRACKING = BuildNameChecklist("TRACKING", "classwatch_"..id.."_"..classname, classname,
                        function(name)
                            local cb = ElkBuffBars.db.profile.bargroups[id].filter.classbuffs
                            return cb and cb[classname] and cb[classname].TRACKING and cb[classname].TRACKING[name] or false
                        end,
                        function(name, value) SetClassBuffFilter(id, classname, "TRACKING", name, value) end,
                        4, L["AURATYPE_TRACKING"]),
                },
            }
    end
    return args
end

local values_text_template = {
    ["false"] = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_HIDE"],
    NAME = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_NAME"],
    NAMERANK = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_NAMERANK"],
    NAMECOUNT = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_NAMECOUNT"],
    NAMERANKCOUNT = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_NAMERANKCOUNT"],
    RANK = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_RANK"],
    COUNT = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_COUNT"],
    TIMELEFT = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_TIMELEFT"],
    DEBUFFTYPE = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_DEBUFFTYPE"],
    CASTER = L["OPTIONS_GROUP_TEXT_TEMPLATE_OPTION_CASTER"],
}
local values_text_style = {
    [""] = L["OPTIONS_GROUP_TEXT_STYLE_OPTION_PLAIN"],
    ["OUTLINE"] = L["OPTIONS_GROUP_TEXT_STYLE_OPTION_OUTLINE"],
    ["THICKOUTLINE"] = L["OPTIONS_GROUP_TEXT_STYLE_OPTION_THICKOUTLINE"],
}

function ElkBuffBars:GetGroupOptions(id)
    return {
        type = "group",
        name = format(L["OPTIONS_GROUP_NAME"], id),
        desc = format(L["OPTIONS_GROUP_DESC"], id),
        disabled = true,
        hidden = true,
        args = {
            configmode = {
                order = 101,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_CONFIG_NAME"],
                desc = L["OPTIONS_GROUP_CONFIG_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].configmode end,
                set = function(info) ElkBuffBars.bargroups[id]:ToggleConfigMode() end,
            },
            anchorshown = {
                order = 102,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_ANCHOR_NAME"],
                desc = L["OPTIONS_GROUP_ANCHOR_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].anchorshown end,
                set = function(info)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.anchorshown = not bg.layout.anchorshown
                    bg:UpdateAnchor()
                end,
            },
            hideanchorwhenempty = {
                order = 102.5,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_HIDEANCHOREMPTY_NAME"],
                desc = L["OPTIONS_GROUP_HIDEANCHOREMPTY_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].hideanchorwhenempty end,
                set = function(info)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.hideanchorwhenempty = not bg.layout.hideanchorwhenempty
                    bg:RefreshAnchorVisibility()
                end,
            },
            hideincombat = {
                order = 102.6,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_HIDEINCOMBAT_NAME"],
                desc = L["OPTIONS_GROUP_HIDEINCOMBAT_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].hideincombat end,
                set = function(info)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.hideincombat = not bg.layout.hideincombat
                    bg:RefreshContainerVisibility()
                end,
            },
            hidewhennomissing = {
                order = 102.7,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_HIDEWHENNOMISSING_NAME"],
                desc = L["OPTIONS_GROUP_HIDEWHENNOMISSING_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].hidewhennomissing end,
                set = function(info)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.hidewhennomissing = not bg.layout.hidewhennomissing
                    bg:RefreshContainerVisibility()
                end,
            },
            hidewhenallmissing = {
                order = 102.8,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_HIDEWHENALLMISSING_NAME"],
                desc = L["OPTIONS_GROUP_HIDEWHENALLMISSING_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].hidewhenallmissing end,
                set = function(info)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.hidewhenallmissing = not bg.layout.hidewhenallmissing
                    bg:RefreshContainerVisibility()
                end,
            },
            hideunlesssoon = {
                order = 102.85,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_HIDEUNLESSSOON_NAME"],
                desc = L["OPTIONS_GROUP_HIDEUNLESSSOON_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].hideunlesssoon end,
                set = function(info)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.hideunlesssoon = not bg.layout.hideunlesssoon
                    bg:RefreshContainerVisibility()
                    ElkBuffBars:UpdateSoonToExpireTimer()
                end,
            },
            hideunlesssoonseconds = {
                order = 102.9,
                type = "range",
                name = L["OPTIONS_GROUP_HIDEUNLESSSOONSECONDS_NAME"],
                desc = L["OPTIONS_GROUP_HIDEUNLESSSOONSECONDS_DESC"],
                min = 1, max = 120, step = 1, bigStep = 5,
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].hideunlesssoonseconds or 20 end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.hideunlesssoonseconds = tonumber(v)
                    bg:RefreshContainerVisibility()
                end,
            },
            anchortext = {
                order = 103,
                type = "input",
                name = L["OPTIONS_GROUP_NAME_NAME"],
                desc = L["OPTIONS_GROUP_NAME_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].anchortext end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.anchortext = v
                    bg:UpdateAnchor()
                end,
            },
            bars = {
                order = 104,
                type = "group",
                name = L["OPTIONS_GROUP_BARLAYOUT_NAME"],
                desc = L["OPTIONS_GROUP_BARLAYOUT_DESC"],
                args = {
                    bar = {
                        order = 101,
                        type = "group",
                        name = L["OPTIONS_GROUP_BAR_NAME"],
                        desc = L["OPTIONS_GROUP_BAR_DESC"],
                        args = {
                            bar = {
                                order = 101,
                                type = "toggle",
--								width = "double",
                                name = L["OPTIONS_GROUP_BAR_SHOW_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_SHOW_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.bar end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.bar = v
                                    bg:SetLayout()
                                end,
                            },
                            barcolor = {
                                order = 102,
                                type = "color",
                                name = L["OPTIONS_GROUP_BAR_COLOR_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_COLOR_DESC"],
                                hasAlpha = true,
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.barcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.barcolor[1] = r
                                    bg.layout.bars.barcolor[2] = g
                                    bg.layout.bars.barcolor[3] = b
                                    bg.layout.bars.barcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            bgbar = {
                                order = 103,
                                type = "toggle",
--								width = "double",
                                name = L["OPTIONS_GROUP_BAR_BGSHOW_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_BGSHOW_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.bgbar end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.bgbar = v
                                    bg:SetLayout()
                                end,
                            },
                            barbgcolor = {
                                order = 104,
                                type = "color",
                                name = L["OPTIONS_GROUP_BAR_BGCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_BGCOLOR_DESC"],
                                hasAlpha = true,
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.barbgcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.barbgcolor[1] = r
                                    bg.layout.bars.barbgcolor[2] = g
                                    bg.layout.bars.barbgcolor[3] = b
                                    bg.layout.bars.barbgcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            bartexture = {
                                order = 105,
                                type = "select",
                                name = L["OPTIONS_GROUP_BAR_TEXTURE_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_TEXTURE_DESC"],
                                values = LSM_statusbar,
                                dialogControl = "LSM30_Statusbar",
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.bartexture end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.bartexture = v
                                    bg:SetLayout()
                                end,
                            },
                            spark = {
                                order = 106,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_BAR_SPARK_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_SPARK_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.spark end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.spark = v
                                    bg:SetLayout()
                                end,
                            },
                            debufftypecolor = {
                                order = 107,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_BAR_DEBUFFCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_DEBUFFCOLOR_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.debufftypecolor end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.debufftypecolor = v
                                    bg:UpdateBars()
                                end,
                            },
                            barright = {
                                order = 108,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_BAR_LTRDIR_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_LTRDIR_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.barright end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.barright = v
                                    bg:SetLayout()
                                end,
                            },
                            timelessfull = {
                                order = 109,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_BAR_TIMELESSFULL_NAME"],
                                desc = L["OPTIONS_GROUP_BAR_TIMELESSFULL_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.timelessfull end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.timelessfull = v
                                    bg:UpdateData()
                                end,
                            },
                        },
                    },
                    icon = {
                        order = 102,
                        type = "group",
                        name = L["OPTIONS_GROUP_ICON_NAME"],
                        desc = L["OPTIONS_GROUP_ICON_DESC"],
                        args = {
                            icon = {
                                order = 101,
                                type = "select",
                                name = L["OPTIONS_GROUP_ICON_POSITION_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_POSITION_DESC"],
                                values = {
                                    ["false"] = L["OPTIONS_GROUP_ICON_POSITION_HIDE"],
                                    ["LEFT"] = L["OPTIONS_GROUP_ICON_POSITION_LEFT"],
                                    ["RIGHT"] = L["OPTIONS_GROUP_ICON_POSITION_RIGHT"],
                                },
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.icon or "false" end,
                                set = function(info, v)
                                    if v == "false" then v = false end
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.icon = v
                                    bg:SetLayout()
                                end,
                            }, -- "LEFT", "RIGHT", false
                            iconcount = {
                                order = 102,
                                type = "toggle",
                                width = "double",
                                name = L["OPTIONS_GROUP_ICON_STACK_SHOW_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_SHOW_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.iconcount end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcount = v
                                    bg:SetLayout()
                                end,
                            }, -- true, false
                            iconcountanchor = {
                                order = 103,
                                type = "select",
                                name = L["OPTIONS_GROUP_ICON_STACK_ANCHOR_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_ANCHOR_DESC"],
                                values = {
                                    TOPLEFT = L["ANCHOR_TOPLEFT"],
                                    TOP = L["ANCHOR_TOP"],
                                    TOPRIGHT = L["ANCHOR_TOPRIGHT"],
                                    LEFT = L["ANCHOR_LEFT"],
                                    CENTER = L["ANCHOR_CENTER"],
                                    RIGHT = L["ANCHOR_RIGHT"],
                                    BOTTOMLEFT = L["ANCHOR_BOTTOMLEFT"],
                                    BOTTOM = L["ANCHOR_BOTTOM"],
                                    BOTTOMRIGHT = L["ANCHOR_BOTTOMRIGHT"],
                                },
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.iconcountanchor end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountanchor = v
                                    bg:SetLayout()
                                end,
                            }, -- <anchor>
                            iconcountfont = {
                                order = 104,
                                type = "select",
                                name = L["OPTIONS_GROUP_ICON_STACK_FONT_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_FONT_DESC"],
                                values = LSM_font,
                                dialogControl = "LSM30_Font",
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.iconcountfont end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountfont = v
                                    bg:SetLayout()
                                end,
                            }, -- <LSM:font>
                            iconcountfontsize =  {
                                order = 105,
                                type = "range",
                                name = L["OPTIONS_GROUP_ICON_STACK_FONTSIZE_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_FONTSIZE_DESC"],
                                min = 4, max = 32, step = 1,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.iconcountfontsize end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountfontsize = tonumber(v)
                                    bg:SetLayout()
                                end,
                            }, -- <font size>
                            iconcountcolor = {
                                order = 106,
                                type = "color",
                                name = L["OPTIONS_GROUP_ICON_STACK_FONTCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_FONTCOLOR_DESC"],
                                hasAlpha = true,
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.iconcountcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountcolor[1] = r
                                    bg.layout.bars.iconcountcolor[2] = g
                                    bg.layout.bars.iconcountcolor[3] = b
                                    bg.layout.bars.iconcountcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            iconcountstyle = {
                                order = 107,
                                type = "select",
                                name = L["OPTIONS_GROUP_ICON_STACK_STYLE_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_STYLE_DESC"],
                                values = values_text_style,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.iconcountstyle end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountstyle = v
                                    bg:SetLayout()
                                end,
                            }, -- "", OUTLINE, THICKOUTLINE
                            iconcountbackdrop = {
                                order = 108,
                                type = "toggle",
                                name = L["OPTIONS_GROUP_ICON_STACK_BACKDROP_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_BACKDROP_DESC"],
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.iconcountbackdrop end,
                                set = function(info, value)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountbackdrop = value
                                    bg:SetLayout()
                                end,
                            }, -- true, false
                            iconcountbackdropcolor = {
                                order = 109,
                                type = "color",
                                name = L["OPTIONS_GROUP_ICON_STACK_BACKDROPCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_ICON_STACK_BACKDROPCOLOR_DESC"],
                                hasAlpha = true,
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.iconcountbackdropcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.iconcountbackdropcolor[1] = r
                                    bg.layout.bars.iconcountbackdropcolor[2] = g
                                    bg.layout.bars.iconcountbackdropcolor[3] = b
                                    bg.layout.bars.iconcountbackdropcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                        },
                    },
                    texttl = {
                        order = 103,
                        type = "group",
                        --dialogInline = true,
                        name = L["OPTIONS_GROUP_TEXTTL_NAME"],
                        desc = L["OPTIONS_GROUP_TEXTTL_DESC"],
                        args = {
                            textTL = {
                                order = 101,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_TEMPLATE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_TEMPLATE_DESC"],
                                values = values_text_template,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTL or "false" end,
                                set = function(info, v)
                                    if v == "false" then v = false end
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTL = v
                                    bg:SetLayout()
                                end,
                            }, -- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
                            textTLfont = {
                                order = 102,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_FONT_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONT_DESC"],
                                values = LSM_font,
                                dialogControl = "LSM30_Font",
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTLfont end,
                                set = function(info, v)
                                        local bg = ElkBuffBars.bargroups[id]
                                        bg.layout.bars.textTLfont = v
                                        bg:SetLayout()
                                    end,
                            }, -- <LSM:font>
                            textTLfontsize = {
                                order = 103,
                                type = "range",
                                name = L["OPTIONS_GROUP_TEXT_FONTSIZE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTSIZE_DESC"],
                                min = 4, max = 32, step = 1,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTLfontsize end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTLfontsize = tonumber(v)
                                    bg:SetLayout()
                                end,
                            }, -- <font size>
                            textTLcolor = {
                                order = 104,
                                type = "color",
                                name = L["OPTIONS_GROUP_TEXT_FONTCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTCOLOR_DESC"],
                                hasAlpha = true,
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.textTLcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTLcolor[1] = r
                                    bg.layout.bars.textTLcolor[2] = g
                                    bg.layout.bars.textTLcolor[3] = b
                                    bg.layout.bars.textTLcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            textTLstyle = {
                                order = 105,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_STYLE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_STYLE_DESC"],
                                values = values_text_style,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTLstyle end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTLstyle = v
                                    bg:SetLayout()
                                end,
                            }, -- "", OUTLINE, THICKOUTLINE
                            textTLalign = {
                                order = 106,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_ALIGNMENT_NAME"],
                                desc = L["OPTIONS_GROUP_TEXTTL_ALIGNMENT_DESC"],
                                values = { -- @Phanx: keys capitalized for passing to SetJustifyH
                                    LEFT = L["OPTIONS_GROUP_TEXT_ALIGNMENT_LEFT"],
                                    CENTER = L["OPTIONS_GROUP_TEXT_ALIGNMENT_CENTER"],
                                    RIGHT = L["OPTIONS_GROUP_TEXT_ALIGNMENT_RIGHT"]
                                },
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTLalign end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTLalign = v
                                    bg:SetLayout()
                                end,
                            }, -- LEFT, CENTER, RIGHT
                        },
                    },
                    texttr = {
                        order = 104,
                        type = "group",
                        --dialogInline = true,
                        name = L["OPTIONS_GROUP_TEXTTR_NAME"],
                        desc = L["OPTIONS_GROUP_TEXTTR_NAME"],
                        args = {
                            textTR = {
                                order = 101,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_TEMPLATE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_TEMPLATE_DESC"],
                                values = values_text_template,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTR or "false" end,
                                set = function(info, v)
                                    if v == "false" then v = false end
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTR = v
                                    bg:SetLayout()
                                end,
                            }, -- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
                            textTRfont = {
                                order = 102,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_FONT_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONT_DESC"],
                                values = LSM_font,
                                dialogControl = "LSM30_Font",
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTRfont end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTRfont = v
                                    bg:SetLayout()
                                end,
                            }, -- <LSM:font>
                            textTRfontsize = {
                                order = 103,
                                type = "range",
                                name = L["OPTIONS_GROUP_TEXT_FONTSIZE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTSIZE_DESC"],
                                min = 4, max = 32, step = 1,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTRfontsize end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTRfontsize = tonumber(v)
                                    bg:SetLayout()
                                end,
                            }, -- <font size>
                            textTRcolor = {
                                order = 104,
                                type = "color",
                                hasAlpha = true,
                                name = L["OPTIONS_GROUP_TEXT_FONTCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTCOLOR_DESC"],
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.textTRcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTRcolor[1] = r
                                    bg.layout.bars.textTRcolor[2] = g
                                    bg.layout.bars.textTRcolor[3] = b
                                    bg.layout.bars.textTRcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            textTRstyle = {
                                order = 105,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_STYLE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_STYLE_DESC"],
                                values = values_text_style,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textTRstyle end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textTRstyle = v
                                    bg:SetLayout()
                                end,
                            }, -- "", OUTLINE, THICKOUTLINE
                        },
                    },
                    textbl = {
                        order = 105,
                        type = "group",
                        --dialogInline = true,
                        name = L["OPTIONS_GROUP_TEXTBL_NAME"],
                        desc = L["OPTIONS_GROUP_TEXTBL_NAME"],
                        args = {
                            textBL = {
                                order = 101,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_TEMPLATE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_TEMPLATE_DESC"],
                                values = values_text_template,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBL or "false" end,
                                set = function(info, v)
                                    if v == "false" then v = false end
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBL = v
                                    bg:SetLayout()
                                end,
                            }, -- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
                            textBLfont = {
                                order = 102,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_FONT_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONT_DESC"],
                                values = LSM_font,
                                dialogControl = "LSM30_Font",
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBLfont end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBLfont = v
                                    bg:SetLayout()
                                end,
                            }, -- <LSM:font>
                            textBLfontsize = {
                                order = 103,
                                type = "range",
                                name = L["OPTIONS_GROUP_TEXT_FONTSIZE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTSIZE_DESC"],
                                min = 4, max = 32, step = 1,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBLfontsize end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBLfontsize = tonumber(v)
                                    bg:SetLayout()
                                end,
                            }, -- <font size>
                            textBLcolor = {
                                order = 104,
                                type = "color",
                                name = L["OPTIONS_GROUP_TEXT_FONTCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTCOLOR_DESC"],
                                hasAlpha = true,
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.textBLcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBLcolor[1] = r
                                    bg.layout.bars.textBLcolor[2] = g
                                    bg.layout.bars.textBLcolor[3] = b
                                    bg.layout.bars.textBLcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            textBLstyle = {
                                order = 105,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_STYLE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_STYLE_DESC"],
                                values = values_text_style,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBLstyle end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBLstyle = v
                                    bg:SetLayout()
                                end,
                            }, -- "", OUTLINE, THICKOUTLINE
                            textBLalign = {
                                order = 106,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_ALIGNMENT_NAME"],
                                desc = L["OPTIONS_GROUP_TEXTBL_ALIGNMENT_DESC"],
                                values = {
                                    left = L["OPTIONS_GROUP_TEXT_ALIGNMENT_LEFT"],
                                    center = L["OPTIONS_GROUP_TEXT_ALIGNMENT_CENTER"],
                                    right = L["OPTIONS_GROUP_TEXT_ALIGNMENT_RIGHT"]
                                },
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBLalign end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBLalign = v
                                    bg:SetLayout()
                                end,
                            }, -- left, center, right
                        },
                    },
                    textbr = {
                        order = 106,
                        type = "group",
                        --dialogInline = true,
                        name = L["OPTIONS_GROUP_TEXTBR_NAME"],
                        desc = L["OPTIONS_GROUP_TEXTBR_NAME"],
                        args = {
                            textBR = {
                                order = 101,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_TEMPLATE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_TEMPLATE_DESC"],
                                values = values_text_template,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBR or "false" end,
                                set = function(info, v)
                                    if v == "false" then v = false end
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBR = v
                                    bg:SetLayout()
                                end,
                            }, -- false, "NAME", "NAMERANK", "NAMECOUNT", "NAMERANKCOUNT", "RANK", "COUNT", "TIMELEFT", "DEBUFFTYPE"
                            textBRfont = {
                                order = 102,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_FONT_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONT_DESC"],
                                values = LSM_font,
                                dialogControl = "LSM30_Font",
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBRfont end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBRfont = v
                                    bg:SetLayout()
                                end,
                            }, -- <LSM:font>
                            textBRfontsize = {
                                order = 103,
                                type = "range",
                                name = L["OPTIONS_GROUP_TEXT_FONTSIZE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTSIZE_DESC"],
                                min = 4, max = 32, step = 1,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBRfontsize end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBRfontsize = tonumber(v)
                                    bg:SetLayout()
                                end,
                            }, -- <font size>
                            textBRcolor = {
                                order = 104,
                                type = "color",
                                hasAlpha = true,
                                name = L["OPTIONS_GROUP_TEXT_FONTCOLOR_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_FONTCOLOR_DESC"],
                                get = function(info) return unpack(ElkBuffBars.db.profile.bargroups[id].bars.textBRcolor) end,
                                set = function(info, r, g, b, a)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBRcolor[1] = r
                                    bg.layout.bars.textBRcolor[2] = g
                                    bg.layout.bars.textBRcolor[3] = b
                                    bg.layout.bars.textBRcolor[4] = a
                                    bg:SetLayout()
                                end,
                            }, -- <color set>
                            textBRstyle = {
                                order = 105,
                                type = "select",
                                name = L["OPTIONS_GROUP_TEXT_STYLE_NAME"],
                                desc = L["OPTIONS_GROUP_TEXT_STYLE_DESC"],
                                values = values_text_style,
                                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.textBRstyle end,
                                set = function(info, v)
                                    local bg = ElkBuffBars.bargroups[id]
                                    bg.layout.bars.textBRstyle = v
                                    bg:SetLayout()
                                end,
                            }, -- "", OUTLINE, THICKOUTLINE
                        },
                    },
                    height = {
                        order = 107,
                        type = "range",
                        name = L["OPTIONS_GROUP_HEIGHT_NAME"],
                        desc = L["OPTIONS_GROUP_HEIGHT_DESC"],
                        min = 0, max = 100, step = 1, bigStep = 5,
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.height end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            local blayout = bg.layout.bars
                            blayout.height = tonumber(v)
                            if blayout.height > blayout.width then blayout.height = blayout.width end
                            bg:SetLayout()
                        end,
                    },
                    width = {
                        order = 108,
                        type = "range",
                        name = L["OPTIONS_GROUP_WIDTH_NAME"],
                        desc = L["OPTIONS_GROUP_WIDTH_DESC"],
                        min = 0, max = 500, step = 1, bigStep = 10,
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.width end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            local blayout = bg.layout.bars
                            blayout.width = tonumber(v)
                            if blayout.width < blayout.height then blayout.width = blayout.height end
                            bg:SetLayout()
                        end,
                    },
                    padding = {
                        order = 109,
                        type = "range",
                        name = L["OPTIONS_GROUP_PADDING_NAME"],
                        desc = L["OPTIONS_GROUP_PADDING_DESC"],
                        min = 0, max = 10, step = 1,
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.padding end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            bg.layout.bars.padding = tonumber(v)
                            bg:SetLayout()
                        end,
                    },
                    abbreviate_name = {
                        order = 110,
                        type = "range",
                        name = L["OPTIONS_GROUP_ABBREVIATE_NAME"],
                        desc = L["OPTIONS_GROUP_ABBREVIATE_DESC"],
                        min = 0, max = 100, step = 1,
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.abbreviate_name end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            bg.layout.bars.abbreviate_name = tonumber(v)
                            bg:UpdateText()
                        end,
                    },
                    timeformat = {
                        order = 111,
                        type = "select",
                        name = L["OPTIONS_GROUP_TIMEFORMAT_NAME"],
                        desc = L["OPTIONS_GROUP_TIMEFORMAT_DESC"],
                        values = {
                            DEFAULT = L["OPTIONS_GROUP_TIMEFORMAT_OPTION_DEFAULT"],
                            CLOCK = L["OPTIONS_GROUP_TIMEFORMAT_OPTION_CLOCK"],
                            CONDENSED = L["OPTIONS_GROUP_TIMEFORMAT_OPTION_CONDENSED"],
                        },
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.timeformat end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            bg.layout.bars.timeformat = v
                            bg:UpdateTimeleft()
                        end,
                    }, -- "DEFAULT", "CLOCK", "CONDENSED"
                    timefraction = {
                        order = 112,
                        type = "toggle",
                        width = "double",
                        name = L["OPTIONS_GROUP_TIMEFRACTION_NAME"],
                        desc = L["OPTIONS_GROUP_TIMEFRACTION_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.timeFraction end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            bg.layout.bars.timeFraction = v
                        end,
                    },
                    tooltipanchor = {
                        order = 113,
                        type = "select",
                        name = L["OPTIONS_GROUP_TTIPANCHOR_NAME"],
                        desc = L["OPTIONS_GROUP_TTIPANCHOR_DESC"],
                        values = {
                            default = L["ANCHOR_DEFAULT"],
                            ANCHOR_TOPRIGHT = L["ANCHOR_TOPRIGHT"],
                            ANCHOR_RIGHT = L["ANCHOR_RIGHT"],
                            ANCHOR_BOTTOMRIGHT = L["ANCHOR_BOTTOMRIGHT"],
                            ANCHOR_TOPLEFT = L["ANCHOR_TOPLEFT"],
                            ANCHOR_LEFT = L["ANCHOR_LEFT"],
                            ANCHOR_BOTTOMLEFT = L["ANCHOR_BOTTOMLEFT"],
                            ANCHOR_CURSOR = L["ANCHOR_CURSOR"],
                            ANCHOR_PRESERVE = L["ANCHOR_PRESERVE"],
                            ANCHOR_NONE = L["ANCHOR_NONE"],
                        },
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.tooltipanchor end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            bg.layout.bars.tooltipanchor = v
                        end,
                    },
                    tooltipcaster = {
                        order = 114,
                        type = "toggle",
                        width = "double",
                        name = L["OPTIONS_GROUP_TTIPCASTER_NAME"],
                        desc = L["OPTIONS_GROUP_TTIPCASTER_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.tooltipcaster end,
                        set = function(info, v)
                            local bg = ElkBuffBars.bargroups[id]
                            bg.layout.bars.tooltipcaster = v
                        end,
                    },
                },
            },
            alpha = {
                order = 105,
                type = "range",
                name = L["OPTIONS_GROUP_ALPHA_NAME"],
                desc = L["OPTIONS_GROUP_ALPHA_DESC"],
                min = 0, max = 1, step = 0.01,
                isPercent = true,
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].alpha end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.alpha = tonumber(v)
                    bg:SetLayout()
                end,
            },
            scale = {
                order = 106,
                type = "range",
                name = L["OPTIONS_GROUP_SCALE_NAME"],
                desc = L["OPTIONS_GROUP_SCALE_DESC"],
                isPercent = true, min = 0.1, max = 2, step = 0.05, bigStep = 0.1,
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].scale end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.scale = tonumber(v)
                    bg:SetLayout()
                end,
            },
            barspacing = {
                order = 107,
                type = "range",
                name = L["OPTIONS_GROUP_BARSPACING_NAME"],
                desc = L["OPTIONS_GROUP_BARSPACING_DESC"],
                min = 0, max = 50, step = 1,
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].barspacing end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.barspacing = tonumber(v)
                    bg:UpdateBarPositions()
                end,
            },
            growup = {
                order = 108,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_GROWUP_NAME"],
                desc = L["OPTIONS_GROUP_GROWUP_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].growup end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.growup = v
                    bg.layout.stickto = nil
                    bg.layout.stickside = nil
                    bg:SetLayout()
                    bg:SetPosition()
                end,
            },
            sorting = {
                order = 109,
                type = "select",
                name = L["OPTIONS_GROUP_SORTING_NAME"],
                desc = L["OPTIONS_GROUP_SORTING_DESC"],
                values = {
                    name = NAME, -- Blizzard global string
                    none = NONE, -- Blizzard global string
                    timeleft = L["OPTIONS_GROUP_SORTING_OPTION_TIMELEFT"],
                    timemax = L["OPTIONS_GROUP_SORTING_OPTION_TIMEMAX"],
                },
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].sorting end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.sorting = v
                    bg:UpdateData()
                end,
            },
            filter = { -- @Phanx: the whitelist / blacklist > buffs / debuffs have the potential to get really long, what to do?
                order = 110,
                type = "group",
                name = L["OPTIONS_GROUP_FILTER_NAME"],
                desc = L["OPTIONS_GROUP_FILTER_DESC"],
                args = {
                    type = {
                        order = 101,
                        type = "multiselect", -- @Phanx: is this really the best choice?
                        values = {
                            BUFF = L["AURATYPE_BUFF"],
                            DEBUFF = L["AURATYPE_DEBUFF"],
                            TENCH = L["AURATYPE_TENCH"],
                            TRACKING = TRACKING, -- Blizzard global string
                        },
                        name = L["OPTIONS_GROUP_FILTER_TYPE_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_TYPE_DESC"],
                        get = function(info, k) return ElkBuffBars.db.profile.bargroups[id].filter.type[k] or false end,
                        set = function(info, k, v)
                            ElkBuffBars.bargroups[id].layout.filter.type[k] = v or nil
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                    selfcast = {
                        order = 102,
                        type = "select",
                        name = L["OPTIONS_GROUP_FILTER_SELFCAST_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_SELFCAST_DESC"],
                        values = {
                            whitelist = L["OPTIONS_GROUP_FILTER_SELFCAST_OPTION_WHITELIST"],
                            none = L["OPTIONS_GROUP_FILTER_SELFCAST_OPTION_NOFILTER"],
                            blacklist = L["OPTIONS_GROUP_FILTER_SELFCAST_OPTION_BLACKLIST"],
                        },
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].filter.selfcast or "none" end,
                        set = function(info, v)
                            if v == "none" then v = nil end
                            ElkBuffBars.bargroups[id].layout.filter.selfcast = v
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                    untilcancelled = {
                        order = 103,
                        type = "select",
                        name = L["OPTIONS_GROUP_FILTER_TIMELESS_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_TIMELESS_DESC"],
                        values = {
                            only = L["OPTIONS_GROUP_FILTER_TIMELESS_OPTION_WHITELIST"],
                            none = L["OPTIONS_GROUP_FILTER_TIMELESS_OPTION_NOFILTER"],
                            hide = L["OPTIONS_GROUP_FILTER_TIMELESS_OPTION_BLACKLIST"],
                        },
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].filter.untilcancelled or "none" end,
                        set = function(info, v)
                            if v == "none" then v = nil end
                            ElkBuffBars.bargroups[id].layout.filter.untilcancelled = v
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                    timemax_min = {
                        type = "input",
                        name = L["OPTIONS_GROUP_FILTER_TIMEMAXMIN_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_TIMEMAXMIN_DESC"],
                        pattern = "^%d+$",
                        --usage = L["OPTIONS_GROUP_FILTER_TIMEMAXMIN_USAGE"], -- @Phanx: not supported by select, merge into desc
                        get = function(info) return tostring(ElkBuffBars.db.profile.bargroups[id].filter.timemax_min or "") end,
                        set = function(info, v)
                                v = tonumber(v)
                                ElkBuffBars.bargroups[id].layout.filter.timemax_min = (v ~= 0) and v or nil
                                ElkBuffBars:DoFullUpdate()
                            end,
                        order = 104,
                    },
                    timemax_max = {
                        order = 105,
                        type = "input",
                        name = L["OPTIONS_GROUP_FILTER_TIMEMAXMAX_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_TIMEMAXMAX_DESC"],
                        pattern = "^%d+$",
                        --usage = L["OPTIONS_GROUP_FILTER_TIMEMAXMAX_USAGE"], -- @Phanx: not supported by select, merge into desc
                        get = function(info) return tostring(ElkBuffBars.db.profile.bargroups[id].filter.timemax_max or "") end,
                        set = function(info, v)
                            v = tonumber(v)
                            ElkBuffBars.bargroups[id].layout.filter.timemax_max = (v ~= 0) and v or nil
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                    names_include = {
                        order = 106,
                        type = "group",
                        name = L["OPTIONS_GROUP_FILTER_NAME_WHITELIST_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_NAME_WHITELIST_DESC"],
                        args = {
                            search = BuildSearchBoxOption("whitelist_"..id),
                            BUFF = BuildNameChecklist("BUFF", "whitelist_"..id, nil,
                                function(name)
                                    local ni = ElkBuffBars.db.profile.bargroups[id].filter.names_include
                                    return ni and ni.BUFF and ni.BUFF[name] or false
                                end,
                                function(name, value) SetNameFilter(id, true, "BUFF", name, value) end,
                                1, L["AURATYPE_BUFF"]),
                            DEBUFF = BuildNameChecklist("DEBUFF", "whitelist_"..id, nil,
                                function(name)
                                    local ni = ElkBuffBars.db.profile.bargroups[id].filter.names_include
                                    return ni and ni.DEBUFF and ni.DEBUFF[name] or false
                                end,
                                function(name, value) SetNameFilter(id, true, "DEBUFF", name, value) end,
                                2, L["AURATYPE_DEBUFF"]),
                            TENCH = BuildNameChecklist("TENCH", "whitelist_"..id, nil,
                                function(name)
                                    local ni = ElkBuffBars.db.profile.bargroups[id].filter.names_include
                                    return ni and ni.TENCH and ni.TENCH[name] or false
                                end,
                                function(name, value) SetNameFilter(id, true, "TENCH", name, value) end,
                                3, L["AURATYPE_TENCH"]),
                            TRACKING = BuildNameChecklist("TRACKING", "whitelist_"..id, nil,
                                function(name)
                                    local ni = ElkBuffBars.db.profile.bargroups[id].filter.names_include
                                    return ni and ni.TRACKING and ni.TRACKING[name] or false
                                end,
                                function(name, value) SetNameFilter(id, true, "TRACKING", name, value) end,
                                4, L["AURATYPE_TRACKING"]),
                        },
                    },
                    names_exclude = {
                        order = 107,
                        type = "group",
                        name = L["OPTIONS_GROUP_FILTER_NAME_BLACKLIST_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_NAME_BLACKLIST_DESC"],
                        args = {
                            search = BuildSearchBoxOption("blacklist_"..id),
                            BUFF = BuildNameChecklist("BUFF", "blacklist_"..id, nil,
                                function(name)
                                    local ne = ElkBuffBars.db.profile.bargroups[id].filter.names_exclude
                                    return ne and ne.BUFF and ne.BUFF[name] or false
                                end,
                                function(name, value) SetNameFilter(id, false, "BUFF", name, value) end,
                                1, L["AURATYPE_BUFF"]),
                            DEBUFF = BuildNameChecklist("DEBUFF", "blacklist_"..id, nil,
                                function(name)
                                    local ne = ElkBuffBars.db.profile.bargroups[id].filter.names_exclude
                                    return ne and ne.DEBUFF and ne.DEBUFF[name] or false
                                end,
                                function(name, value) SetNameFilter(id, false, "DEBUFF", name, value) end,
                                2, L["AURATYPE_DEBUFF"]),
                            TENCH = BuildNameChecklist("TENCH", "blacklist_"..id, nil,
                                function(name)
                                    local ne = ElkBuffBars.db.profile.bargroups[id].filter.names_exclude
                                    return ne and ne.TENCH and ne.TENCH[name] or false
                                end,
                                function(name, value) SetNameFilter(id, false, "TENCH", name, value) end,
                                3, L["AURATYPE_TENCH"]),
                            TRACKING = BuildNameChecklist("TRACKING", "blacklist_"..id, nil,
                                function(name)
                                    local ne = ElkBuffBars.db.profile.bargroups[id].filter.names_exclude
                                    return ne and ne.TRACKING and ne.TRACKING[name] or false
                                end,
                                function(name, value) SetNameFilter(id, false, "TRACKING", name, value) end,
                                4, L["AURATYPE_TRACKING"]),
                        },
                    },
                    showmissing = {
                        order = 108,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_GROUP_FILTER_SHOWMISSING_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_SHOWMISSING_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].filter.showmissing end,
                        set = function(info, v)
                            ElkBuffBars.bargroups[id].layout.filter.showmissing = v
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                    whitelistisfilter = {
                        order = 108.1,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_GROUP_FILTER_WHITELISTISFILTER_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_WHITELISTISFILTER_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].filter.whitelistisfilter end,
                        set = function(info, v)
                            ElkBuffBars.bargroups[id].layout.filter.whitelistisfilter = v
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                    selfbuffs = {
                        order = 108.15,
                        type = "group",
                        name = L["OPTIONS_GROUP_FILTER_SELFBUFFS_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_SELFBUFFS_DESC"],
                        args = (function()
                            -- filter.selfbuffs is keyed by class first (see SetSelfBuffFilter
                            -- above), so switching alts on a shared profile only ever shows and
                            -- tracks THIS class's own self-buff selections.
                            local myClass = (UnitClass("player"))
                            return {
                            search = BuildSearchBoxOption("selfbuffs_"..id),
                            BUFF = BuildNameChecklist("BUFF", "selfbuffs_"..id, myClass,
                                function(name)
                                    local sb = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffs
                                    sb = sb and sb[myClass]
                                    return sb and sb.BUFF and sb.BUFF[name] or false
                                end,
                                function(name, value) SetSelfBuffFilter(id, "BUFF", name, value) end,
                                1, L["AURATYPE_BUFF"]),
                            DEBUFF = BuildNameChecklist("DEBUFF", "selfbuffs_"..id, myClass,
                                function(name)
                                    local sb = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffs
                                    sb = sb and sb[myClass]
                                    return sb and sb.DEBUFF and sb.DEBUFF[name] or false
                                end,
                                function(name, value) SetSelfBuffFilter(id, "DEBUFF", name, value) end,
                                2, L["AURATYPE_DEBUFF"]),
                            TENCH = BuildNameChecklist("TENCH", "selfbuffs_"..id, myClass,
                                function(name)
                                    local sb = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffs
                                    sb = sb and sb[myClass]
                                    return sb and sb.TENCH and sb.TENCH[name] or false
                                end,
                                function(name, value) SetSelfBuffFilter(id, "TENCH", name, value) end,
                                3, L["AURATYPE_TENCH"]),
                            TRACKING = BuildNameChecklist("TRACKING", "selfbuffs_"..id, myClass,
                                function(name)
                                    local sb = ElkBuffBars.db.profile.bargroups[id].filter.selfbuffs
                                    sb = sb and sb[myClass]
                                    return sb and sb.TRACKING and sb.TRACKING[name] or false
                                end,
                                function(name, value) SetSelfBuffFilter(id, "TRACKING", name, value) end,
                                4, L["AURATYPE_TRACKING"]),
                            altgroups = {
                                order = 5,
                                type = "group",
                                name = L["OPTIONS_GROUP_FILTER_SELFALTGROUPS_NAME"],
                                desc = L["OPTIONS_GROUP_FILTER_SELFALTGROUPS_DESC"],
                                args = BuildSelfBuffAltGroupsOptions(id),
                            },
                            }
                        end)(),
                    },
                    classwatch = {
                        order = 108.2,
                        type = "group",
                        name = L["OPTIONS_GROUP_FILTER_CLASSWATCH_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_CLASSWATCH_DESC"],
                        args = BuildClassWatchOptions(id),
                    },
                    alertblacklisted = {
                        order = 108.3,
                        type = "toggle",
                        width = "full",
                        name = L["OPTIONS_GROUP_FILTER_ALERTBLACKLISTED_NAME"],
                        desc = L["OPTIONS_GROUP_FILTER_ALERTBLACKLISTED_DESC"],
                        get = function(info) return ElkBuffBars.db.profile.bargroups[id].filter.alertblacklisted end,
                        set = function(info, v)
                            ElkBuffBars.bargroups[id].layout.filter.alertblacklisted = v
                            ElkBuffBars:DoFullUpdate()
                        end,
                    },
                },
            },
            target = {
                order = 111,
                type = "select",
                name = L["OPTIONS_GROUP_TARGET_NAME"],
                desc = L["OPTIONS_GROUP_TARGET_DESC"],
                values = {
                    focus = FOCUS, -- Blizzard global strings
                    pet = PET,
                    player = PLAYER,
                    target = TARGET,
                    vehicle = L["UNIT_VEHICLE"],
                },
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].target end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.target = v
                    bg:UpdateData()
                end,
            },
            clickthrough = {
                order = 112,
                type = "toggle",
                width = "double",
                name = L["OPTIONS_GROUP_CLICKTHROUGH_NAME"],
                desc = L["OPTIONS_GROUP_CLICKTHROUGH_DESC"],
                get = function(info) return ElkBuffBars.db.profile.bargroups[id].bars.clickthrough end,
                set = function(info, v)
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.bars.clickthrough = v
                    bg:SetLayout()
                end,
            },
            copylayout = {
                order = 113,
                type = "input",
                name = L["OPTIONS_GROUP_COPYLAYOUT_NAME"],
                desc = L["OPTIONS_GROUP_COPYLAYOUT_DESC"],
                usage = L["OPTIONS_GROUP_COPYLAYOUT_USAGE"],
                get = false,
                set = function(info, v)
                    v = tonumber(v)
                    if v ~= id and ElkBuffBars.bargroups[v] then
                        ElkBuffBars:CopyBarLayout(ElkBuffBars.bargroups[id].layout, ElkBuffBars.bargroups[v].layout)
                    end
                end,
            },
            resetpos = {
                order = 114,
                type = "execute",
                name = L["OPTIONS_GROUP_RESETPOSITION_NAME"],
                desc = L["OPTIONS_GROUP_RESETPOSITION_DESC"],
                func = function()
                    local bg = ElkBuffBars.bargroups[id]
                    bg.layout.x = nil
                    bg.layout.y = nil
                    bg.layout.stickto = nil
                    bg.layout.stickmode = nil
                    bg.layout.stickside = nil
                    bg.layout.stickvalign = nil
                    bg:SetPosition()
                end,
            },
            remove = {
                order = 115,
                type = "execute", confirm = true,
                name = L["OPTIONS_GROUP_REMOVE_NAME"],
                desc = L["OPTIONS_GROUP_REMOVE_DESC"],
                func = function()
                    ElkBuffBars:RemoveBarGroup(id)
                end,
            },
        }
    }
end
