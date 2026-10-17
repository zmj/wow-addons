local addonName, ns = ...

--------------------------------------------------------------------------------
-- OrderScout - Color crafting order rows by the cost of the reagents you'd supply
--
-- Prices come from two places, both stored in copper per unit:
--   * Vendors: every MERCHANT_SHOW records trade goods sold for gold. Later
--     visits overwrite, so reputation discounts and patch changes are picked up.
--   * Auction house: every browse result (including the favorites search that
--     runs when the AH opens) records minPrice.
-- The cheaper of the two is used.
--
-- An order is "good" when the reagents you supply cost no more than
-- commission (tipAmount) x multiplier. The multiplier stands in for the value
-- of the order's rewards without pricing them.
--
-- Commands: /os            report for the order list currently shown
--           /os mult <n>   set the commission multiplier (default 2)
--           /os prices     list known prices
--------------------------------------------------------------------------------

local DEFAULT_MULTIPLIER = 2

-- Vendor reagents known before the first merchant visit: [itemID] = copper per unit.
-- A merchant visit replaces these with the live price.
local SEED_VENDOR_PRICES = {
}

local COLORS = {
    good = { 0.1, 0.9, 0.1 },
    bad = { 0.9, 0.15, 0.1 },
    unknown = { 0.95, 0.8, 0.1 },
}

local db

--------------------------------------------------------------------------------
-- Debug Output (uses the DebugConsole addon's copyable window when loaded)
--------------------------------------------------------------------------------

local function ShowDebugOutput(text)
    if DebugConsole and DebugConsole.Show then
        DebugConsole.Show(text)
    else
        for line in text:gmatch("[^\n]+") do
            print(line)
        end
    end
end

--------------------------------------------------------------------------------
-- Saved Variables
--------------------------------------------------------------------------------

local function InitDB()
    OrderScoutDB = OrderScoutDB or {}
    db = OrderScoutDB
    db.multiplier = db.multiplier or DEFAULT_MULTIPLIER
    db.prices = db.prices or {}

    for itemID, price in pairs(SEED_VENDOR_PRICES) do
        local record = db.prices[itemID] or {}
        if not record.vendor then
            record.vendor = price
        end
        db.prices[itemID] = record
    end
end

local function GetRecord(itemID)
    local record = db.prices[itemID]
    if not record then
        record = {}
        db.prices[itemID] = record
    end
    return record
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

-- Returns unit price, source ("vendor" or "AH"), and time seen (nil for seeded prices)
local function GetUnitPrice(itemID)
    local record = db.prices[itemID]
    if not record then return nil end

    if record.vendor and (not record.ah or record.vendor <= record.ah) then
        return record.vendor, "vendor", record.vendorTime
    elseif record.ah then
        return record.ah, "AH", record.ahTime
    end
end

local function IsReagentClass(itemID)
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == Enum.ItemClass.Tradegoods or classID == Enum.ItemClass.Reagent
end

local function GetMerchantGoldPrice(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then
            return info.price, info.stackCount, info.hasExtendedCost
        end
    elseif GetMerchantItemInfo then
        local _, _, price, stackCount, _, _, _, hasExtendedCost = GetMerchantItemInfo(index)
        return price, stackCount, hasExtendedCost
    end
end

local function ScanMerchant()
    local now = time()
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        local price, stackCount, hasExtendedCost = GetMerchantGoldPrice(i)
        if itemID and price and price > 0 and not hasExtendedCost and IsReagentClass(itemID) then
            local record = GetRecord(itemID)
            record.vendor = price / math.max(stackCount or 1, 1)
            record.vendorTime = now
        end
    end
end

local function RecordBrowseResults(results)
    if not results then return end
    local now = time()
    for _, result in ipairs(results) do
        local itemID = result.itemKey and result.itemKey.itemID
        if itemID and result.minPrice and result.minPrice > 0 then
            local record = GetRecord(itemID)
            record.ah = result.minPrice
            record.ahTime = now
        end
    end
end

--------------------------------------------------------------------------------
-- Order Evaluation
--------------------------------------------------------------------------------

local function SlotItemIDs(slot)
    local ids = {}
    for _, reagent in ipairs(slot.reagents or {}) do
        local itemID = reagent.itemID or (reagent.reagent and reagent.reagent.itemID)
        if itemID then
            table.insert(ids, itemID)
        end
    end
    return ids
end

local function IsRequiredBasicSlot(slot)
    return slot.required and slot.reagentType == Enum.CraftingReagentType.Basic
end

-- Returns { status, cost, budget, missing = { {itemIDs, quantity, price, source, time} } }
-- or nil when the row isn't an order we can evaluate
local function EvaluateOrder(order)
    if not (order and order.orderID and order.spellID and order.reagents) or order.isRecraft then
        return nil
    end

    local schematic = C_TradeSkillUI.GetRecipeSchematic(order.spellID, false)
    if not (schematic and schematic.reagentSlotSchematics) then
        return nil
    end

    local provided = {}
    for _, reagent in ipairs(order.reagents) do
        local quantity = reagent.reagentInfo and reagent.reagentInfo.quantity or 0
        provided[reagent.slotIndex] = (provided[reagent.slotIndex] or 0) + quantity
    end

    local eval = { cost = 0, missing = {}, slotsChecked = 0 }
    local anyUnknown = false

    for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
        if IsRequiredBasicSlot(slot) then
            eval.slotsChecked = eval.slotsChecked + 1
            local quantity = slot.quantityRequired - (provided[slotIndex] or 0)
            if quantity > 0 then
                local itemIDs = SlotItemIDs(slot)
                local entry = { itemIDs = itemIDs, itemID = itemIDs[1], quantity = quantity }

                -- Cheapest known quality for this slot
                for _, itemID in ipairs(itemIDs) do
                    local price, source, seen = GetUnitPrice(itemID)
                    if price and (not entry.price or price < entry.price) then
                        entry.itemID, entry.price, entry.source, entry.time = itemID, price, source, seen
                    end
                end

                if entry.price then
                    eval.cost = eval.cost + entry.price * quantity
                else
                    anyUnknown = true
                end
                table.insert(eval.missing, entry)
            end
        end
    end

    eval.budget = (order.tipAmount or 0) * db.multiplier
    if anyUnknown then
        eval.status = "unknown"
    elseif eval.cost <= eval.budget then
        eval.status = "good"
    else
        eval.status = "bad"
    end
    return eval
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local function Money(copper)
    -- Round to the silver; reagent unit prices can be fractional after stack division
    return GetMoneyString(math.floor((copper or 0) / 100 + 0.5) * 100, true)
end

local function Age(seen)
    if not seen then return "seeded" end
    local seconds = time() - seen
    if seconds < 3600 then
        return math.floor(seconds / 60) .. "m ago"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. "h ago"
    end
    return math.floor(seconds / 86400) .. "d ago"
end

local function ItemName(itemID)
    return (itemID and C_Item.GetItemNameByID(itemID)) or ("item " .. tostring(itemID))
end

local function DescribeMissing(entry)
    local name = entry.quantity .. " x " .. ItemName(entry.itemID)
    if not entry.price then
        return name, "no price"
    end
    return name, Money(entry.price * entry.quantity) .. " (" .. entry.source .. ", " .. Age(entry.time) .. ")"
end

--------------------------------------------------------------------------------
-- Order List Rows
--------------------------------------------------------------------------------

local function SetIndicator(row, status)
    if not row.OrderScoutTint then
        local tint = row:CreateTexture(nil, "BACKGROUND", nil, 7)
        tint:SetAllPoints()
        tint:SetColorTexture(1, 1, 1)
        row.OrderScoutTint = tint

        local bar = row:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        bar:SetWidth(3)
        bar:SetColorTexture(1, 1, 1)
        row.OrderScoutBar = bar
    end

    local color = status and COLORS[status]
    if color then
        row.OrderScoutTint:SetVertexColor(color[1], color[2], color[3], 0.15)
        row.OrderScoutBar:SetVertexColor(color[1], color[2], color[3], 1)
        row.OrderScoutTint:Show()
        row.OrderScoutBar:Show()
    else
        row.OrderScoutTint:Hide()
        row.OrderScoutBar:Hide()
    end
end

local function OnRowInit(row, elementData)
    local eval = EvaluateOrder(elementData and elementData.option)
    row.OrderScoutEval = eval
    SetIndicator(row, eval and eval.status)
end

local function OnRowEnter(row)
    local eval = row.OrderScoutEval
    if not eval then return end

    local tooltip = GameTooltip
    if not tooltip:IsShown() then
        tooltip:SetOwner(row, "ANCHOR_RIGHT")
    end

    local color = COLORS[eval.status]
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("OrderScout",
        "cost " .. Money(eval.cost) .. " / budget " .. Money(eval.budget),
        1, 0.82, 0, color[1], color[2], color[3])
    if #eval.missing == 0 then
        tooltip:AddLine("All reagents provided", 0.8, 0.8, 0.8)
    end
    for _, entry in ipairs(eval.missing) do
        local left, right = DescribeMissing(entry)
        tooltip:AddDoubleLine(left, right, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    end
    tooltip:Show()
end

local hooked = false

local function TryHookOrderList()
    if hooked or not ProfessionsCrafterOrderListElementMixin then return end
    hooksecurefunc(ProfessionsCrafterOrderListElementMixin, "Init", OnRowInit)
    hooksecurefunc(ProfessionsCrafterOrderListElementMixin, "OnLineEnter", OnRowEnter)
    hooked = true
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function ShowReport()
    local output = {
        "OrderScout: multiplier " .. db.multiplier .. ", row hook " .. (hooked and "installed" or "NOT installed"),
    }

    local orders = C_CraftingOrders.GetCrafterOrders() or {}
    if #orders == 0 then
        table.insert(output, "No orders loaded; open a crafting order tab first.")
    end

    for _, order in ipairs(orders) do
        local eval = EvaluateOrder(order)
        table.insert(output, "")
        if eval then
            table.insert(output, string.format("[%s] %s (spell %d): cost %s / budget %s, %d required slots",
                eval.status, ItemName(order.itemID), order.spellID, Money(eval.cost), Money(eval.budget), eval.slotsChecked))
            for _, entry in ipairs(eval.missing) do
                local left, right = DescribeMissing(entry)
                table.insert(output, "    " .. left .. " [" .. table.concat(entry.itemIDs, "/") .. "]: " .. right)
            end
        else
            table.insert(output, ItemName(order.itemID) .. ": not evaluated")
        end
    end

    ShowDebugOutput(table.concat(output, "\n"))
end

local function ShowPrices()
    local output = { "OrderScout known prices (copper per unit):" }
    local ids = {}
    for itemID in pairs(db.prices) do
        table.insert(ids, itemID)
    end
    table.sort(ids)
    for _, itemID in ipairs(ids) do
        local record = db.prices[itemID]
        table.insert(output, string.format("%d %s: vendor %s (%s), AH %s (%s)", itemID, ItemName(itemID),
            tostring(record.vendor), record.vendor and Age(record.vendorTime) or "-",
            tostring(record.ah), record.ah and Age(record.ahTime) or "-"))
    end
    ShowDebugOutput(table.concat(output, "\n"))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_UPDATE")
eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            InitDB()
        end
        -- The order list mixin lives in a load-on-demand Blizzard addon
        TryHookOrderList()
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        ScanMerchant()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        RecordBrowseResults(C_AuctionHouse.GetBrowseResults())
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        RecordBrowseResults(arg1)
    end
end)

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

SLASH_ORDERSCOUT1 = "/os"
SLASH_ORDERSCOUT2 = "/orderscout"

function SlashCmdList.ORDERSCOUT(msg)
    local args = { strsplit(" ", msg) }
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" or cmd == "report" then
        ShowReport()
    elseif cmd == "mult" then
        local value = tonumber(args[2])
        if value and value > 0 then
            db.multiplier = value
            print("|cffff8800OrderScout:|r Multiplier set to " .. value .. "; reopen the order tab to recolor.")
        else
            print("|cffff8800OrderScout:|r Multiplier is " .. db.multiplier .. ". Usage: /os mult <number>")
        end
    elseif cmd == "prices" then
        ShowPrices()
    else
        print("|cffff8800OrderScout:|r Usage: /os [report|mult <n>|prices]")
    end
end
