-- PopQuest: popup for "This Item Begins a Quest" items
local ADDON = ...
local C = C_Container
local GetNumSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
local GetItemID   = (C and C.GetContainerItemID) or GetContainerItemID
local NUM_BAGS = NUM_BAG_SLOTS or 4

local known, queue, ready = {}, {}, false
local STARTS = ITEM_STARTS_QUEST or "This Item Begins a Quest"

-- hidden tooltip for scanning
local scan = CreateFrame("GameTooltip", "PopQuestScanTip", nil, "GameTooltipTemplate")
scan:SetOwner(WorldFrame, "ANCHOR_NONE")

local function StartsQuest(bag, slot)
  if C and C.GetContainerItemQuestInfo then
    local info = C.GetContainerItemQuestInfo(bag, slot)
    if info and info.questID then
      return not info.isActive
    end
  end
  scan:ClearLines()
  scan:SetBagItem(bag, slot)
  for i = 1, scan:NumLines() do
    local fs = _G["PopQuestScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and t == STARTS then return true end
  end
  return false
end

-- ===== popup frame =====
local f = CreateFrame("Frame", "PopQuestFrame", UIParent, "BackdropTemplate")
f:SetSize(320, 110)
f:SetPoint("TOP", 0, -160)
f:SetFrameStrata("DIALOG")
f:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()

local icon = f:CreateTexture(nil, "ARTWORK")
icon:SetSize(36, 36); icon:SetPoint("TOPLEFT", 20, -20)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
title:SetPoint("RIGHT", -20, 0); title:SetJustifyH("LEFT")
title:SetText("New quest available")

local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
name:SetPoint("RIGHT", -20, 0); name:SetJustifyH("LEFT")

local view = CreateFrame("Button", "PopQuestViewButton", f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
view:SetSize(120, 24); view:SetPoint("BOTTOMLEFT", 30, 16)
view:SetText("View Quest")
view:RegisterForClicks("AnyUp", "AnyDown")
view:SetAttribute("type", "item")

local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
later:SetSize(120, 24); later:SetPoint("BOTTOMRIGHT", -30, 16)
later:SetText("Later")

local ShowNext
view:HookScript("OnClick", function() if not InCombatLockdown() then f:Hide(); C_Timer.After(0.3, ShowNext) end end)
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
  if not bag or not StartsQuest(bag, slot) then return ShowNext() end
  local n, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
  icon:SetTexture(tex or GetItemIcon(itemID))
  name:SetText(link or n or ("item:" .. itemID))
  view:SetAttribute("item", bag .. " " .. slot)
  f:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN or 875)
end

-- ===== bag scanning =====
local function Scan()
  local now = {}
  for bag = 0, NUM_BAGS do
    for slot = 1, GetNumSlots(bag) or 0 do
      local id = GetItemID(bag, slot)
      if id and not now[id] and StartsQuest(bag, slot) then now[id] = true end
    end
  end
  if ready then
    for id in pairs(now) do
      if not known[id] then table.insert(queue, id) end
    end
  end
  known = now
  ready = true
  ShowNext()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(2, Scan) -- snapshot existing items silently
  elseif e == "BAG_UPDATE_DELAYED" then
    if ready then Scan() end
  elseif e == "PLAYER_REGEN_DISABLED" then
    -- secure popup cannot change in combat; queue waits until combat ends
  elseif e == "PLAYER_REGEN_ENABLED" then
    ShowNext()
  end
end)

SLASH_POPQUEST1 = "/popquest"
SlashCmdList.POPQUEST = function()
  -- re-prompt for every quest starter currently in bags
  wipe(known); Scan()
  for bag = 0, NUM_BAGS do
    for slot = 1, GetNumSlots(bag) or 0 do
      local id = GetItemID(bag, slot)
      if id and StartsQuest(bag, slot) then table.insert(queue, id) end
    end
  end
  ShowNext()
end
