TransmogSets = CreateFrame("Frame","TransmogSets")

TransmogSets:SetScript("OnEvent", function(self, event, ...)
	self[event](self, event, ...)
end)
TransmogSets:RegisterEvent("ADDON_LOADED")


local print = print
-- local print = function(...)
--     local tbl = {...}
--     for k,v in pairs(tbl) do
--         tbl[k] = tostring(v)
--     end
    -- DEFAULT_CHAT_FRAME:AddMessage(table.concat({...}, " "))
-- end

local Slots = {
    [1] = "HeadSlot",
    [3] = "ShoulderSlot",
    [15] = "BackSlot",
    [5] = "ChestSlot",
    [9] = "WristSlot",
    [10] = "HandsSlot",
    [6] = "WaistSlot",
    [7] = "LegsSlot",
    [8] = "FeetSlot",
    [16] = "MainHandSlot",
    [17] = "SecondaryHandSlot",
}
local iSlots = { 1, 3, 15, 5, 9, 10, 6, 7, 8, 16, 17 }

function TransmogSets.ADDON_LOADED(self,event,arg1)
    if arg1 ~= "TransmogSets" then return end
    
    TransmogSetsDB_Character = TransmogSetsDB_Character or {}
    TransmogSetsDB = TransmogSetsDB_Character

    TransmogSetsDB.sets = TransmogSetsDB.sets or {}

    self.db = TransmogSetsDB

    self:RegisterEvent("TRANSMOGRIFY_OPEN")
    self:RegisterEvent("TRANSMOGRIFY_CLOSE")
    self:RegisterEvent("VOID_STORAGE_OPEN")
    self:RegisterEvent("VOID_STORAGE_CLOSE")
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("BANKFRAME_CLOSED")

    self.frame = TransmogSets:Create()
    self:UpdateTree(self.frame.tree)
    if self.db.selected and self.db.sets[self.db.selected] then
        self.frame.tree:SelectByValue(self.db.selected)
    elseif next(self.db.sets) then
        self.db.selected = next(self.db.sets)
        self.frame.tree:SelectByValue(self.db.selected)
    else
        self.db.selected = nil
        self:UpdateRightPanel()
    end
    
    SLASH_TRANSMOGSETS1 = "/trs";
    SLASH_TRANSMOGSETS2 = "/transmogsets";
    SlashCmdList["TRANSMOGSETS"] = TransmogSets.SlashCmd
end

function TransmogSets.SaveCurrent(self)
    local t = {}
    for slotID in pairs(Slots) do
        local isTransmogrified, canTransmogrify, cannotTransmogrifyReason,
            hasPending, hasUndo, srcItemID, texture = GetTransmogrifySlotInfo(slotID)
        if isTransmogrified then
            t[slotID] = srcItemID
            if hasUndo then t[slotID] = false end
        end
    end
    return t
end

do -- bag/bank search functions
    local bag_containers = { 0 } --backpack
    for i=1, NUM_BAG_SLOTS do table.insert(bag_containers, i) end
    local bank_containers = { -1 } -- main bank space
    for i=NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do table.insert(bank_containers, i) end
    function TransmogSets.FindItemByID(self, itemID, in_bank)
        local conts = in_bank and bank_containers or bag_containers
        for _,container in ipairs(conts) do
            for slot=1, GetContainerNumSlots(container), 1 do
                if GetContainerItemID(container,slot) == itemID and
                    not select(3,GetContainerItemInfo(container, slot)) --locked check
                then
                    return container, slot
                end
            end
        end
        return nil;
    end

    local free = {}
    function TransmogSets.FindFreeSlots(self, in_bank)
        self:ClearFree()
        local conts = in_bank and bank_containers or bag_containers
        for _,container in ipairs(conts) do
            free[container] = free[container] or {}
            GetContainerFreeSlots(container, free[container])
        end
    end

    function TransmogSets.GetNextFreeSlot(self, in_bank)
        local conts = in_bank and bank_containers or bag_containers
        for _,container in ipairs(conts) do
            local slot = table.remove(free[container])
            if slot then return container, slot end
        end
        return nil
    end

    function TransmogSets:ClearFree()
        for k,v in pairs(free) do
            table.wipe(v)
        end
    end
end

local VOID_DEPOSIT_MAX = 9;
local VOID_WITHDRAW_MAX = 9;
local VOID_STORAGE_MAX = 80;
function TransmogSets.FindInVoid(self, itemID)
    for slot=1, VOID_STORAGE_MAX do
        if GetVoidItemInfo(slot) == itemID then return slot end
    end
end

function TransmogSets.PickupItemByID(self, itemID, in_bank)
    local container, slot = self:FindItemByID(itemID, in_bank)
    if container then
        PickupContainerItem(container, slot);
        return true
    end
    return false
end

local itemTable = {}

function TransmogSets.LoadSet(self, setName)
    local setName = setName or self.db.selected
    if not setName then return end
    local set = self.db.sets[setName]
    for slotID in pairs(Slots) do
        ClearTransmogrifySlot(slotID)
    end
    for slotID, item in pairs(set) do
		GetInventoryItemsForSlot(slotID, itemTable, "transmogrify")
		local isTransmogrified, canTransmogrify, cannotTransmogrifyReason, _, _, visibleItemID = GetTransmogrifySlotInfo(slotID)			
        if canTransmogrify and visibleItemID ~= item then
			for location, itemID in pairs(itemTable) do
				if itemID == item then
						local player, bank, bags, voidStorage, slot, bag, tab, voidSlot = EquipmentManager_UnpackLocation(location)
						if voidStorage then
							UseVoidItemForTransmogrify(tab, voidSlot, slotID)
						else
							UseItemForTransmogrify(bag, slot, slotID)
						end
					break
				end
			end
        -- else
            -- local errorMsg = _G["TRANSMOGRIFY_INVALID_REASON"..cannotTransmogrifyReason];
            -- print(string.format("|cffd29f32[%s]|r |cffff8888%s|r",Slots[slotID], cannotTransmogrifyReason))
        end
    end
end

function TransmogSets.PushBank(self, setName)
    local setName = setName or self.db.selected
    if not setName then return end
    local set = self.db.sets[setName]
    self:FindFreeSlots(true)
    for invSlot, itemID in pairs(set) do
        local sc,ss = self:FindItemByID(itemID)
        if sc then
            local dc,ds = self:GetNextFreeSlot(true)
            if dc then
                PickupContainerItem(sc,ss)
                PickupContainerItem(dc,ds)
            else
                print("|cffff8888No space left in bank|r")
            end
        end
    end
    self:ClearFree()
end

function TransmogSets.PullBank(self, setName)
    local setName = setName or self.db.selected
    if not setName then return end
    local set = self.db.sets[setName]
    self:FindFreeSlots()
    for invSlot, itemID in pairs(set) do
        local sc,ss = self:FindItemByID(itemID, true)
        if sc then
            local dc,ds = self:GetNextFreeSlot()
            if dc then
                PickupContainerItem(sc,ss)
                PickupContainerItem(dc,ds)
            else
                print("|cffff8888No space left in bags|r")
            end
        end
    end
    self:ClearFree()
end


function TransmogSets.PushVoid(self, setName)
    local setName = setName or self.db.selected
    if not setName then return end
    local set = self.db.sets[setName]
    VoidStorageFrame:UnregisterEvent("VOID_DEPOSIT_WARNING")
    self:RegisterEvent("VOID_DEPOSIT_WARNING")
    self:RegisterEvent("VOID_TRANSFER_DONE")
    if self.vswarn then self.vswarn:Hide() end
    local slotIn = 1
    for invSlot, itemID in pairs(set) do
        local sc,ss = self:FindItemByID(itemID)
        if sc then
            if not GetVoidTransferDepositInfo(slotIn) then
                PickupContainerItem(sc,ss)
                ClickVoidTransferDepositSlot(slotIn)
            end
            if slotIn == VOID_DEPOSIT_MAX then break end
            slotIn = slotIn + 1
        end
    end
    VoidStorageFrame:RegisterEvent("VOID_DEPOSIT_WARNING")
    self:UnregisterEvent("VOID_DEPOSIT_WARNING")
end
function TransmogSets.VOID_DEPOSIT_WARNING(self, event)
    if not self.vswarn then self.vswarn = self:CreateWarningText() end
    self.vswarn:Show()
    VoidStorage_UpdateTransferButton();
end
function TransmogSets.VOID_TRANSFER_DONE(self, event)
    self:UnregisterEvent("VOID_TRANSFER_DONE")
    if self.vswarn then self.vswarn:Hide() end
end


function TransmogSets.PullVoid(self, setName)
    local setName = setName or self.db.selected
    if not setName then return end
    local set = self.db.sets[setName]

    local slotOut = 1
    for invSlot, itemID in pairs(set) do
        local slotStorage = self:FindInVoid(itemID)
        if slotStorage then
            if not GetVoidTransferWithdrawalInfo(slotOut) then
                ClickVoidStorageSlot(slotStorage)
                ClickVoidTransferWithdrawalSlot(slotOut)
            end
            if slotOut == VOID_WITHDRAW_MAX then break end
            slotOut = slotOut + 1
        end
    end
end

function TransmogSets.SaveSet(self)
    local label = self.frame.top.label
    local name = label:GetText()
    if not name or name == "" then return end
    self.db.sets[name] = self:SaveCurrent()
    self.db.selected = name
    self:UpdateTree()
    self.frame.tree:SelectByValue(name)
    -- self:UpdateRightPanel()
end

function TransmogSets.DeleteSet(self, name)
    if not name or name == "" then name = self.db.selected end
    self.db.sets[name] = nil
    if self.db.selected == name then
        local newset = next(self.db.sets)
        if newset then
            self.frame.tree:SelectByValue(newset)
        else
            self:UpdateRightPanel()
        end
        self.db.selected = newset
    end
    self:UpdateTree()
end


-- TransmogSets.Commands = {
--     ["save"] = function(v)
--     end,
--     ["load"] = function(v)
--         TransmogSets:LoadSet(v)
--     end,
--     ["push"] = function(v)
--         TransmogSets:PushBank(v)
--     end,
--     ["pull"] = function(v)
--         TransmogSets:PullBank(v)
--     end,
--     ["list"] = function(v)
--         print("Transmogrification Sets:")
--         for name in pairs(TransmogSetsDB) do
--             print("    ",name)
--         end
--     end,
-- }

function TransmogSets.SlashCmd(msg)
    TransmogSets.frame:Show()
    -- k,v = string.match(msg, "([%w%+%-%=]+) ?(.*)")
    -- if not k or k == "help" then 
    --     print([[Usage:
    --       |cffd29f32/trs save <set>|r
    --       |cff55ff55/trs load <set>|r]]
    --     )
    -- end
    -- if TransmogSets.Commands[k] then
    --     TransmogSets.Commands[k](v)
    -- end    
end

function TransmogSets:UpdateTree()
    local sets = TransmogSetsDB.sets
    local treegroup = self.frame.tree
    local s = {}
    local t = {}
    for name in pairs(sets) do table.insert(s, name) end
    table.sort(s)
    for i,name in ipairs(s) do
        local set = sets[name]
        local iconItemID = set[3] or select(2, next(set))
        local icon = GetItemIcon(iconItemID)
        table.insert(t, { value = name, text = name, icon = icon })
    end
    treegroup:SetTree(t)
end

function TransmogSets.UpdateRightPanel(self, group)
    if group then self.db.selected = group end
    local rpane = self.frame.rpane
    local set
    if self.db.selected and self.db.sets[self.db.selected]  then
        -- self.frame.tree:SelectByValue(self.db.selected)
        set = self.db.sets[self.db.selected] 
        self.frame.top.label:SetText(self.db.selected)
    else
        self.frame.top.label:SetText("NewSet")
        set = {}
    end
    for slotID, label in pairs(rpane.itemlabels) do
        if set[slotID] == nil then
            label:SetImage("Interface\\Icons\\Spell_Shadow_SacrificialShield")
            label:SetText("None")
            label:SetColor(0.5,0.5,0.5)
        elseif set[slotID] == false then
            label:SetImage("Interface\\Icons\\INV_Enchant_EssenceCosmicGreater")
            label:SetText("<Undo>")
            label:SetColor(0.2,0.8,0.2)
        else
            local itemID = set[slotID]
            local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID) 
            label:SetImage(texture)
            label:SetText(name)
            label:SetColor(GetItemQualityColor(quality or 1))
        end
    end

end

function TransmogSets.TRANSMOGRIFY_OPEN(self)
    if not self.tfbutton then self.tfbutton = self:CreateTransmogFrameButton() end
    local btn = self.tfbutton
    -- btn:SetParent(TransmogrifyFrame)
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMRIGHT", TransmogrifyFrame,"BOTTOMRIGHT",-25,40)
    btn:Show()
    self.frame.rpane.transmogbtn:SetDisabled(false)
end
function TransmogSets.TRANSMOGRIFY_CLOSE(self)
    local btn = self.tfbutton
    if btn then btn:Hide() end
    self.frame.rpane.transmogbtn:SetDisabled(true)
end
function TransmogSets.VOID_STORAGE_OPEN(self)
    if not self.tfbutton then self.tfbutton = self:CreateTransmogFrameButton() end
    local btn = self.tfbutton
    -- btn:SetParent(VoidStorageFrame)
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", VoidStorageFrame,"TOPRIGHT",-15,-30)
    btn:Show()
    local pullbtn, pushbtn = self.frame.rpane.pullbtn, self.frame.rpane.pushbtn
    pullbtn:SetCallback("OnClick", pullbtn.void_click)
    pullbtn:SetCallback("OnEnter", pullbtn.void_enter)
    pullbtn:SetDisabled(false)
    pushbtn:SetCallback("OnClick", pushbtn.void_click)
    pushbtn:SetCallback("OnEnter", pushbtn.void_enter)
    pushbtn:SetDisabled(false)
end
function TransmogSets.VOID_STORAGE_CLOSE(self)
    local btn = self.tfbutton
    if btn then btn:Hide() end
    self.frame.rpane.pullbtn:SetDisabled(true)
    self.frame.rpane.pushbtn:SetDisabled(true)
end
function TransmogSets.BANKFRAME_OPENED(self)
    if not self.tfbutton then self.tfbutton = self:CreateTransmogFrameButton() end
    local btn = self.tfbutton
    -- btn:SetParent(UIParent)
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", UIParent,"TOPRIGHT",-175,-2)
    btn:Show()
    local pullbtn, pushbtn = self.frame.rpane.pullbtn, self.frame.rpane.pushbtn
    pullbtn:SetCallback("OnClick", pullbtn.bank_click)
    pullbtn:SetCallback("OnEnter", pullbtn.bank_enter)
    pullbtn:SetDisabled(false)
    pushbtn:SetCallback("OnClick", pushbtn.bank_click)
    pushbtn:SetCallback("OnEnter", pushbtn.bank_enter)
    pushbtn:SetDisabled(false)
end
function TransmogSets.BANKFRAME_CLOSED(self)
    local btn = self.tfbutton
    if btn then btn:Hide() end
    self.frame.rpane.pullbtn:SetDisabled(true)
    self.frame.rpane.pushbtn:SetDisabled(true)
end


function TransmogSets.Create( self )
    local AceGUI = LibStub("AceGUI-3.0")
    -- Create a container frame
    local Frame = AceGUI:Create("Frame")
    Frame:SetTitle("TransmogSets")
    Frame:SetWidth(600)
    Frame:SetHeight(440)
    Frame:EnableResize(false)
    -- f:SetStatusText("Status Bar")
    Frame:SetLayout("Flow")

    local topgroup = AceGUI:Create("InlineGroup")
    topgroup:SetFullWidth(true)
    -- topgroup:SetHeight(0)
    topgroup:SetLayout("Flow")
    Frame:AddChild(topgroup)
    Frame.top = topgroup

    local setname = AceGUI:Create("EditBox")
    setname:SetWidth(340)
    setname:SetText("NewSet1")
    setname:DisableButton(true)
    topgroup:AddChild(setname)
    topgroup.label = setname

    local setcreate = AceGUI:Create("Button")
    setcreate:SetText("Save")
    setcreate:SetWidth(100)
    setcreate:SetCallback("OnClick", function(self) TransmogSets:SaveSet() end)
    setcreate:SetCallback("OnEnter", function() Frame:SetStatusText("Create new/overwrite existing set") end)
    setcreate:SetCallback("OnLeave", function() Frame:SetStatusText("") end)
    topgroup:AddChild(setcreate)

    local btn4 = AceGUI:Create("Button")
    btn4:SetWidth(100)
    btn4:SetText("Delete")
    btn4:SetCallback("OnClick", function() TransmogSets:DeleteSet() end)
    topgroup:AddChild(btn4)
    -- Frame.rpane:AddChild(btn4)
    -- Frame.rpane.deletebtn = btn4


    local treegroup = AceGUI:Create("TreeGroup") -- "InlineGroup" is also good
    treegroup:SetFullWidth(true)
    treegroup:SetTreeWidth(250, false)
    treegroup:SetLayout("Flow")
    treegroup:SetFullHeight(true) -- probably?
    treegroup:SetCallback("OnGroupSelected", function(self, event, group) TransmogSets:UpdateRightPanel(group) end)
    Frame:AddChild(treegroup)
    Frame.rpane = treegroup
    Frame.tree = treegroup


    local btn1 = AceGUI:Create("Button")
    btn1:SetWidth(130)
    btn1:SetText("Transmogrify")
    btn1:SetCallback("OnClick", function() TransmogSets:LoadSet() end)
    btn1:SetDisabled(true)
    Frame.rpane:AddChild(btn1)
    Frame.rpane.transmogbtn = btn1

    local pullbtn = AceGUI:Create("Button")
    pullbtn:SetWidth(80)
    pullbtn:SetText("Pull")
    pullbtn.void_click = function() TransmogSets:PullVoid() end
    pullbtn.bank_click = function() TransmogSets:PullBank() end
    pullbtn.void_enter = function() Frame:SetStatusText("Get set items to void storage") end
    pullbtn.bank_enter = function() Frame:SetStatusText("Get set items to bank") end
    pullbtn:SetCallback("OnLeave", function() Frame:SetStatusText("") end)
    pullbtn:SetDisabled(true)
    Frame.rpane:AddChild(pullbtn)
    Frame.rpane.pullbtn = pullbtn

    local pushbtn = AceGUI:Create("Button")
    pushbtn:SetWidth(80)
    pushbtn:SetText("Push")
    pushbtn.void_click = function() TransmogSets:PushVoid() end
    pushbtn.bank_click = function() TransmogSets:PushBank() end
    pushbtn.void_enter = function() Frame:SetStatusText("Move set items to void storage") end
    pushbtn.bank_enter = function() Frame:SetStatusText("Move set items to bank") end
    pushbtn:SetCallback("OnLeave", function() Frame:SetStatusText("") end)
    pushbtn:SetDisabled(true)
    Frame.rpane:AddChild(pushbtn)
    Frame.rpane.pushbtn = pushbtn

    local itemsgroup = AceGUI:Create("InlineGroup")
    itemsgroup:SetWidth(300)
    itemsgroup:SetFullHeight(true)
    itemsgroup:SetLayout("List")
    itemsgroup.labels = {}
    Frame.rpane:AddChild(itemsgroup)

    for _,k in pairs(iSlots) do
        local label = AceGUI:Create("Label")
        label:SetText('test')
        label:SetWidth(280)
        label.label:SetWordWrap(false) 
        label:SetImage("Interface\\Icons\\spell_holy_resurrection")
        itemsgroup:AddChild(label)
        itemsgroup.labels[k] = label
    end
    Frame.rpane.itemlabels = itemsgroup.labels

    Frame:Hide()

    return Frame
end

function TransmogSets.CreateTransmogFrameButton(self)
    btn = CreateFrame("Button","TransmogSetsButton", UIParent)
    btn:SetPoint("TOPRIGHT", TransmogrifyFrame,"TOPRIGHT",-25,40)
    btn:SetFrameStrata("TOOLTIP")

    btn:SetWidth(25)
    btn:SetHeight(25)
    btn:SetNormalTexture("Interface\\Icons\\INV_Gizmo_02")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")

    btn:RegisterForClicks("LeftButtonUp","RightButtonUp")
    btn:SetScript("OnClick",function(self)
        if TransmogSets.frame:IsVisible() then
            TransmogSets.frame:Hide()
        else
            TransmogSets.frame:Show()
        end
    end)
    return btn
end

function TransmogSets.CreateWarningText(self)
    local f = CreateFrame("Frame", nil, VoidStorageFrame)
    f:SetWidth(500)
    f:SetHeight(20)
    f:SetPoint("BOTTOMLEFT",VoidStorageFrame,"BOTTOMLEFT",35,17)
    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetAllPoints(f)
    label:SetJustifyH("LEFT")
    label:SetFontObject("GameFontNormalSmall")
    label:SetTextColor(1,0.6, 0)
    label:SetText(VOID_STORAGE_DEPOSIT_CONFIRMATION)
    return f
end