-- PopQuest: popup for "This Item Begins a Quest" items
local C = C_Container
local GetNumSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
local GetItemID   = (C and C.GetContainerItemID) or GetContainerItemID
local NUM_BAGS = NUM_BAG_SLOTS or 4
local STARTS = ITEM_STARTS_QUEST or "This Item Begins a Quest"

local known, queue, ready, debug = {}, {}, false, false
local function dprint(...) if debug then print("|cff33ff99PopQuest|r", ...) end end

local scan = CreateFrame("GameTooltip", "PopQuestScanTip", nil, "GameTooltipTemplate")

-- returns true = starts a quest (not active), false = no, nil = data not loaded yet
local function StartsQuest(bag, slot)
  -- API 1: C_Container (newer clients)
  if C and C.GetContainerItemQuestInfo then
    local ok, info = pcall(C.GetContainerItemQuestInfo, bag, slot)
    if ok and type(info) == "table" and info.questID then return not info.isActive end
  end
  -- API 2: old global (returns isQuestItem, questID, isActive)
  if GetContainerItemQuestInfo then
    local ok, _, qid, active = pcall(GetContainerItemQuestInfo, bag, slot)
    if ok and qid then return not active end
  end
  -- API 3: tooltip scan
  scan:SetOwner(WorldFrame, "ANCHOR_NONE")
  scan:ClearLines()
  scan:SetBagItem(bag, slot)
  local n = scan:NumLines()
  if n == 0 then return nil end
  for i = 1, n do
    local fs = _G["PopQuestScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and t:find(STARTS, 1, true) then return true end
  end
  -- first line blank/"Retrieving item information" = not cached
  local first = PopQuestScanTipTextLeft1 and PopQuestScanTipTextLeft1:GetText()
  if not first or first == "" or first == RETRIEVING_ITEM_INFO then return nil end
  return false
end

-- ===== popup =====
local f = CreateFrame("Frame", "PopQuestFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
f:SetSize(320, 110)
f:SetPoint("TOP", 0, -160)
f:SetFrameStrata("DIALOG")
if f.SetBackdrop then
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
end
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()

local icon = f:CreateTexture(nil, "ARTWORK")
icon:SetSize(36, 36); icon:SetPoint("TOPLEFT", 20, -20)
local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0); title:SetPoint("RIGHT", -20, 0)
title:SetJustifyH("LEFT"); title:SetText("New quest available")
local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4); name:SetPoint("RIGHT", -20, 0)
name:SetJustifyH("LEFT")

local view = CreateFrame("Button", "PopQuestViewButton", f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
view:SetSize(120, 24); view:SetPoint("BOTTOMLEFT", 30, 16)
view:SetText("View Quest")
view:RegisterForClicks("AnyUp", "AnyDown")
view:SetAttribute("type", "item")
local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
later:SetSize(120, 24); later:SetPoint("BOTTOMRIGHT", -30, 16)
later:SetText("Later")

local ShowNext
view:HookScript("OnClick", function()
  if not InCombatLockdown() then f:Hide(); C_Timer.After(0.3, function() ShowNext() end) end
end)
later:SetScript("OnClick", function() f:Hide(); ShowNext() end)

local function FindItem(itemID)
  for bag = 0, NUM_BAGS do
    for slot = 1, GetNumSlots(bag) or 0 do
      if GetItemID(bag, slot) == itemID then return bag, slot end
    end
  end
end

function ShowNext()
  if InCombatLockdown() or f:IsShown() then return end
  local itemID = table.remove(queue, 1)
  if not itemID then return end
  local bag, slot = FindItem(itemID)
  if not bag then return ShowNext() end
  local nm, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
  icon:SetTexture(tex or GetItemIcon(itemID))
  name:SetText(link or nm or ("item " .. itemID))
  view:SetAttribute("item", bag .. " " .. slot)
  f:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN or 875)
end

-- ===== scanning =====
local pending = false
local function Scan()
  local now, unresolved = {}, false
  for bag = 0, NUM_BAGS do
    for slot = 1, GetNumSlots(bag) or 0 do
      local id = GetItemID(bag, slot)
      if id and now[id] == nil then
        local r = StartsQuest(bag, slot)
        if r == nil then unresolved = true; if known[id] ~= nil then now[id] = known[id] end
        else now[id] = r end
        if r then dprint("quest starter in bag", bag, slot, id) end
      end
    end
  end
  if ready then
    for id, yes in pairs(now) do
      if yes and not known[id] then
        dprint("new quest starter", id); table.insert(queue, id)
      end
    end
  end
  known = now
  ready = true
  if unresolved and not pending then -- retry once item data has loaded
    pending = true
    C_Timer.After(1, function() pending = false; Scan() end)
  end
  ShowNext()
end

local function Soon()
  if ready then C_Timer.After(0.2, Scan) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_ENTERING_WORLD" then
    if not ready then C_Timer.After(3, Scan) end -- snapshot existing items silently
  elseif e == "PLAYER_REGEN_ENABLED" then
    ShowNext()
  else
    Soon()
  end
end)

SLASH_POPQUEST1 = "/popquest"
SlashCmdList.POPQUEST = function(msg)
  msg = (msg or ""):lower()
  if msg == "debug" then
    debug = not debug; print("PopQuest debug", debug and "on" or "off")
  else
    -- prompt for every quest starter currently in bags
    local found = 0
    for bag = 0, NUM_BAGS do
      for slot = 1, GetNumSlots(bag) or 0 do
        local id = GetItemID(bag, slot)
        if id and StartsQuest(bag, slot) then table.insert(queue, id); found = found + 1 end
      end
    end
    print("|cff33ff99PopQuest|r found " .. found .. " quest starter(s) in your bags.")
    ShowNext()
  end
end
