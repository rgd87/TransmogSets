TransmogSets = CreateFrame("Frame","TransmogSets")

TransmogSets:SetScript("OnEvent", function(self, event, ...)
	self[event](self, event, ...)
end)
TransmogSets:RegisterEvent("ADDON_LOADED")

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

function TransmogSets.ADDON_LOADED(self,event,arg1)
    if arg1 ~= "TransmogSets" then return end
    
    TransmogSetsDB_Character = TransmogSetsDB_Character or {}
    TransmogSetsDB = TransmogSetsDB_Character

    TransmogSetsDB.sets = TransmogSetsDB.sets or {}

    self.db = TransmogSetsDB

    self:RegisterEvent("TRANSMOGRIFY_OPEN")
    self:RegisterEvent("TRANSMOGRIFY_CLOSE")
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("BANKFRAME_CLOSED")

    -- local f = CreateFrame("ScrollFrame", "TransmogSetsListFrame", UIParent, "HybridScrollFrameTemplate") 
    -- f:SetBackdrop{
    --     ["bgFile"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    --     ["tileSize"] = 32,
    --     ["edgeFile"] = "Interface\\DialogFrame\\UI-DialogBox-Border",
    --     ["tile"] = 1,
    --     ["edgeSize"] = 32,
    --     ["insets"] = {
    --         ["top"] = 8,
    --         ["right"] = 8,
    --         ["left"] = 8,
    --         ["bottom"] = 8,
    --     },
    -- }
    -- f:SetWidth(200)
    -- f:SetHeight(360)
    -- f:SetPoint("CENTER",0,0)

    self.frame = TransmogSets:Create()
    self:UpdateTree(self.frame.tree)
    if self.db.selected then
        self.frame.tree:SelectByValue(self.db.selected)
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

do
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

function TransmogSets.PickupItemByID(self, itemID, in_bank)
    local container, slot = self:FindItemByID(itemID, in_bank)
    if container then
        PickupContainerItem(container, slot);
        return true
    end
    return false
end


function TransmogSets.LoadSet(self, setName)
    local setName = setName or self.db.selected
    if not setName then return end
    local set = self.db.sets[setName]
    for slotID, itemID in pairs(set) do
        ClearTransmogrifySlot(slotID)
        local isTransmogrified, canTransmogrify, cannotTransmogrifyReason,
            hasPending, hasUndo, srcItemID, texture = GetTransmogrifySlotInfo(slotID)
        if canTransmogrify then
            if itemID then
                if not isTransmogrified or srcItemID ~= itemID then
                    if self:PickupItemByID(itemID) then
                        ClickTransmogrifySlot(slotID);
                        local cursorItem = GetCursorInfo();
                        if cursorItem == "item" then
                            ClearCursor()
                            print(Slots[slotID], "Couldn't transmogrify this item")
                        end
                    else
                        print(Slots[slotID], "Item", itemID, "is missing")
                    end
                end
            else
                ClearTransmogrifySlot(slotID);
            end
        else
            local errorMsg = _G["TRANSMOGRIFY_INVALID_REASON"..cannotTransmogrifyReason];
            print(Slots[slotID], errorMsg)
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
                print("No space left in bank")
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
                print("No space left in bags")
            end
        end
    end
    self:ClearFree()
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
    end
    self:UpdateTree()
end


TransmogSets.Commands = {
    ["save"] = function(v)
    end,
    ["load"] = function(v)
        TransmogSets:LoadSet(v)
    end,
    ["push"] = function(v)
        TransmogSets:PushBank(v)
    end,
    ["pull"] = function(v)
        TransmogSets:PullBank(v)
    end,
    ["list"] = function(v)
        print("Transmogrification Sets:")
        for name in pairs(TransmogSetsDB) do
            print("    ",name)
        end
    end,
}

function TransmogSets.SlashCmd(msg)
    k,v = string.match(msg, "([%w%+%-%=]+) ?(.*)")
    if not k or k == "help" then 
        print([[Usage:
          |cff55ffff/trs save <set>|r
          |cff55ff55/trs load <set>|r]]
        )
    end
    if TransmogSets.Commands[k] then
        TransmogSets.Commands[k](v)
    end    
end

function TransmogSets:UpdateTree()
    local sets = TransmogSetsDB.sets
    local treegroup = self.frame.tree
    local t = {}
    for name,set in pairs(sets) do
        local iconItemID = set[3] or select(2, next(set))
        local icon = GetItemIcon(iconItemID)
-- 
        -- (iconItemID == false)
                    -- and "Interface\\Icons\\INV_Enchant_EssenceCosmicGreater"
                    -- or 
        table.insert(t, { value = name, text = name, icon = icon })
    end
    treegroup:SetTree(t)
end

function TransmogSets.UpdateRightPanel(self, group)
    if group then self.db.selected = group end
    local rpane = self.frame.rpane
    local set
    if self.db.selected then
        self.frame.tree:SelectByValue(self.db.selected)
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
            label:SetColor(GetItemQualityColor(quality))
        end
    end

end


function TransmogSets.TRANSMOGRIFY_OPEN(self)
    self.frame.rpane.transmogbtn:SetDisabled(false)
end
function TransmogSets.TRANSMOGRIFY_CLOSE(self)
    self.frame.rpane.transmogbtn:SetDisabled(true)
end
function TransmogSets.BANKFRAME_OPENED(self)
    self.frame.rpane.pullbtn:SetDisabled(false)
    self.frame.rpane.pushbtn:SetDisabled(false)
end
function TransmogSets.BANKFRAME_CLOSED(self)
    self.frame.rpane.pullbtn:SetDisabled(true)
    self.frame.rpane.pushbtn:SetDisabled(true)
end

function TransmogSets.Create( self )
    local AceGUI = LibStub("AceGUI-3.0")
    -- Create a container frame
    local Frame = AceGUI:Create("Frame")
    Frame:SetCallback("OnClose",function(widget) AceGUI:Release(widget) end)
    Frame:SetTitle("TransmogSets")
    Frame:SetWidth(500)
    Frame:SetHeight(470)
    -- f:SetStatusText("Status Bar")
    Frame:SetLayout("Flow")

    local topgroup = AceGUI:Create("InlineGroup")
    topgroup:SetFullWidth(true)
    -- topgroup:SetHeight(0)
    topgroup:SetLayout("Flow")
    Frame:AddChild(topgroup)
    Frame.top = topgroup

    local setname = AceGUI:Create("EditBox")
    setname:SetText("NewSet1")
    setname:DisableButton(true)
    topgroup:AddChild(setname)
    topgroup.label = setname

    local setcreate = AceGUI:Create("Button")
    setcreate:SetText("Save")
    setcreate:SetWidth(100)
    setcreate:SetCallback("OnClick", function(self) TransmogSets:SaveSet() end)
    topgroup:AddChild(setcreate)


    local treegroup = AceGUI:Create("TreeGroup") -- "InlineGroup" is also good
    local t = {}
    for i=1, 10 do
        table.insert(t, { value = "shit"..i, text = "shit" ..i})
    end
    -- treegroup:SetTree(t)
    treegroup:SetFullWidth(true)
    treegroup:SetTreeWidth(150, false)
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

    local btn2 = AceGUI:Create("Button")
    btn2:SetWidth(80)
    btn2:SetText("Pull")
    btn2:SetCallback("OnClick", function() TransmogSets:PullBank() end)
    btn2:SetDisabled(true)
    Frame.rpane:AddChild(btn2)
    Frame.rpane.pullbtn = btn2

    local btn3 = AceGUI:Create("Button")
    btn3:SetWidth(80)
    btn3:SetText("Push")
    btn3:SetCallback("OnClick", function() TransmogSets:PushBank() end)
    btn3:SetDisabled(true)
    Frame.rpane:AddChild(btn3)
    Frame.rpane.pushbtn = btn3

    local itemsgroup = AceGUI:Create("InlineGroup")
    itemsgroup:SetWidth(300)
    itemsgroup:SetLayout("Flow")
    itemsgroup.labels = {}
    Frame.rpane:AddChild(itemsgroup)

    for k,v in pairs(Slots) do
        local label = AceGUI:Create("Label")
        label:SetText('test')
        label:SetWidth(250)
        label:SetImage("Interface\\Icons\\spell_holy_resurrection")
        itemsgroup:AddChild(label)
        itemsgroup.labels[k] = label
    end
    Frame.rpane.itemlabels = itemsgroup.labels

    local btn4 = AceGUI:Create("Button")
    btn4:SetWidth(90)
    btn4:SetText("Delete")
    btn4:SetCallback("OnClick", function() TransmogSets:DeleteSet() end)
    Frame.rpane:AddChild(btn4)
    Frame.rpane.deletebtn = btn4




    -- local scrollcontainer = AceGUI:Create("InlineGroup") -- "InlineGroup" is also good
    -- scrollcontainer:SetWidth(200)
    -- scrollcontainer:SetFullHeight(true) -- probably?
    -- scrollcontainer:SetLayout("Fill") -- important!
    -- f:AddChild(scrollcontainer)

    -- local scroll = AceGUI:Create("ScrollFrame")
    -- scroll:SetLayout("Flow") -- probably?
    -- scrollcontainer:AddChild(scroll)

    -- -- Create a button
    -- for i=1,30 do
    -- local btn = AceGUI:Create("Button")
    -- btn:SetWidth(170)
    -- btn:SetText("Button !")
    -- btn:SetCallback("OnClick", function() print("Click!") end)
    -- -- -- Add the button to the container
    -- tree:AddChild(btn)

    return Frame
end