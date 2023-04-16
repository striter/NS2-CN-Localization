
local Plugin = Shine.Plugin( ... )

Plugin.Version = "1.0"
Plugin.PrintName = "communityprewarm"
Plugin.HasConfig = true
Plugin.ConfigName = "CommunityPrewarm.json"
Plugin.DefaultConfig = {
    ValidationDay = 0,
    Validated = false,
    Restriction = {
        Hour = 4,           --Greater than this hour
        Player = 12,
    },
    ["Tier"] = {
        [1] = { Count = 2, Credit = 15,Inform = true, },
        [2] = { Count = 3, Credit = 10,Inform = true },
        [3] = { Count = 10, Credit = 5 },
        [4] = { Count = 99, Credit = 1 },
    },
    ["UserData"] = {
        ["55022511"] = {tier = 0 , time = 100 , credit = 0 , name = "StriteR."}
    },
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
do
    local Validator = Shine.Validator()
    Validator:AddFieldRule( "ValidationDay",  Validator.IsType( "number", Plugin.DefaultConfig.ValidationDay ))
    Validator:AddFieldRule( "Validated",  Validator.IsType( "boolean", Plugin.DefaultConfig.Validated ))
    Validator:AddFieldRule( "Restriction.Hour",  Validator.IsType( "number", Plugin.DefaultConfig.Restriction.Hour ))
    Validator:AddFieldRule( "Restriction.Player",  Validator.IsType( "number", Plugin.DefaultConfig.Restriction.Player ))
    Validator:AddFieldRule( "Tier",  Validator.IsType( "table", Plugin.DefaultConfig.Tier  ))
    Validator:AddFieldRule( "UserData",  Validator.IsType( "table", Plugin.DefaultConfig.UserData  ))
    Plugin.ConfigValidator = Validator
end

local kPrewarmColor = { 235, 152, 78 }
local tmpDate = os.date("*t", Shared.GetSystemTime())
local kCurrentDay = tmpDate.day
local kCurrentHour = tmpDate.hour

function Plugin:Initialise()
    self.PrewarmTracker = {}
    self.MemberInfos = { }
    self:CreateMessageCommands()
	return true
end

local function ReadPersistent(self)
    for k,v in pairs(self.Config.UserData) do
        self.MemberInfos[tonumber(k)] = v
    end
end

local function SavePersistent(self)
    for k,v in pairs(self.MemberInfos) do
        self.Config.UserData[tostring(k)] = v
    end
    self:SaveConfig()
end

function Plugin:ResetState()
    table.Empty(self.MemberInfos)
    table.Empty(self.PrewarmTracker)
    ReadPersistent(self)
end

function Plugin:Cleanup()
    table.Empty(self.MemberInfos)
    table.Empty(self.PrewarmTracker)
    return self.BaseClass.Cleanup( self )
end

local function GetPlayerData(self, _clientID)
    if not self.MemberInfos[_clientID] then
        self.MemberInfos[_clientID] = { tier = 0 , time = 0, credit = 0, name = "" }
    end
    
    return self.MemberInfos[_clientID]
end


local function NotifyClient(self, _client, _data)
    if not _client then return end

    local data = _data or GetPlayerData(self,_client:GetUserId())
    if data.credit > 0 then
        Shine:NotifyDualColour( _client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",
                255, 255, 255,string.format("当日剩余%s[预热点],可作用于[投票-换图提名]或者[自由下场]等特权,每日清空记得用完哦!", data.credit) )
    end
end

-- Track Clients Prewarm Time
local function TrackClient(self, client, _clientID)
    local now = Shared.GetTime()

    if not self.PrewarmTracker[_clientID] then
        self.PrewarmTracker[_clientID] = now
    end
    
    local data = GetPlayerData(self,_clientID)
    local player = client:GetControllingPlayer()
    data.time = data.time + math.floor(now - self.PrewarmTracker[_clientID])
    self.PrewarmTracker[_clientID] = now
    player:SetPrewarmData(data)
end

local function TrackAllClients(self)
    for client in Shine.IterateClients() do
        if not client:GetIsVirtual() then
            TrackClient(self,client,client:GetUserId())
        end
    end
end

local function ValidateClient(self, _clientID, _data, _tier, _credit)
    _data = _data or GetPlayerData(self,_clientID)
    _data.tier = _tier
    _data.credit = _credit
    
    local client = Shine.GetClientByNS2ID(_clientID)
    if not client then return end

    client:GetControllingPlayer():SetPrewarmData(_data)
    Shine:NotifyDualColour( client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",255, 255, 255,
            string.format("预热激励已派发,您于当日享有[预热徽章%s]并获得了[%s预热点],感谢您的付出!",_tier,_credit) )
end

local function Reset(self)
    table.Empty(self.Config.UserData)
    table.Empty(self.MemberInfos)
    self.Config.ValidationDay = kCurrentDay
    self.Config.Validated = false
end

local function PrewarmValidateEnable(self)
    if kCurrentHour < self.Config.Restriction.Hour then return false end
    return true
end

local function Validate(self)
    if not PrewarmValidateEnable(self) then return end

    if Shine.GetHumanPlayerCount() < self.Config.Restriction.Player then return end
    if self.Config.Validated then return end
    self.Config.Validated = true

    local prewarmClients = {}
    for clientID,prewarmData in pairs(self.MemberInfos) do
        table.insert(prewarmClients, { clientID = clientID, data = prewarmData})
    end

    local function PrewarmCompare(a, b) return a.data.time > b.data.time end
    table.sort(prewarmClients, PrewarmCompare)
    
    local nameList = ""
    local currentIndex = 0
    for _, prewarmClient in pairs(prewarmClients) do
        local curTier = 0
        local curTierData = nil
        local tierValidator = 0
        for tier, tierData in ipairs(self.Config.Tier) do
            tierValidator = tierValidator + tierData.Count
            if currentIndex < tierValidator then
                curTierData = tierData
                curTier = tier
                break
            end
        end
        
        if not curTierData then break end
        ValidateClient(self, prewarmClient.clientID, prewarmClient.data,curTier, curTierData.Credit)
        if curTierData.Inform then  
            nameList = nameList .. string.format("%s(%s分)|", prewarmClient.data.name, math.floor(prewarmClient.data.time / 60)) 
        end
        currentIndex = currentIndex + 1
    end

    for client in Shine.IterateClients() do
        Shine:NotifyDualColour( client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",
                255, 255, 255,string.format("预热已达成,预热排名靠前的玩家:" .. nameList .. "等,感谢各位对预热做出的贡献.",
                        self.Config.Restriction.Player))
    end
    --SavePersistent(self)
end

function Plugin:GetPrewarmPrivilege(_client, _cost, _privilege)
    if not self.Config.Validated then return end
    
    local data = GetPlayerData(self,_client:GetUserId())
    if not data.tier or data.tier <= 0 then return end
    
    if _cost == 0 then
        Shine:NotifyDualColour( _client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",
                255, 255, 255,string.format("您已使用[预热特权:%s]!", _privilege) )
        return true
    end
    
    if _cost > 0 then
        local credit = data.credit or 0
        if credit >= _cost then
            data.credit = credit - _cost
            Shine:NotifyDualColour( _client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",
                    255, 255, 255,string.format("消耗[%s预热点]获得[预热特权:%s],剩余[%s预热点]!", _cost,_privilege,data.credit) )
            return true
        end
        return false
    else
        Shine:NotifyDualColour( _client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",
                255, 255, 255,string.format("您的[预热点]不足!", _privilege) )
        return true
    end
end

-- Triggers
function Plugin:OnFirstThink()
    ReadPersistent(self)
    Shine.Hook.SetupClassHook("NS2Gamerules", "EndGame", "OnEndGame", "PassivePost")
    if self.Config.ValidationDay ~= kCurrentDay then
        Reset(self)
        --SavePersistent(self)
    end
end

function Plugin:SetGameState( Gamerules, State, OldState )
    if State == kGameState.Countdown then
        TrackAllClients(self)
        Validate(self)

        if PrewarmValidateEnable(self) and not self.Config.Validated then
            for client in Shine.IterateClients() do
                Shine:NotifyDualColour( client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",
                        255, 255, 255,string.format("当前为预热局,当游戏开始/结束时[人数>%s]后,参与预热的玩家将获得当日[预热徽章]以及对应的[预热点].",
                                self.Config.Restriction.Player))
            end
        end
    end
end

function Plugin:OnEndGame(_winningTeam)
    TrackAllClients(self)
    Validate(self)
end

function Plugin:MapChange()
    TrackAllClients(self)
    SavePersistent(self)
end

function Plugin:ClientConnect(_client)
    local clientID = _client:GetUserId()
    if clientID <= 0 then return end
    TrackClient(self,_client,clientID)

    if PrewarmValidateEnable(self) then
        if self.Config.Validated then
            NotifyClient(self,_client,nil)
        else
            Shine:NotifyDualColour( _client, kPrewarmColor[1], kPrewarmColor[2], kPrewarmColor[3],"[战局预热]",255, 255, 255,
                    string.format("服务器为预热状态,待预热成功后(>=%s人),场内所有人都将获得激励.",self.Config.Restriction.Player) )
        end
    end
end

function Plugin:ClientConfirmConnect( _client )
    local clientID = _client:GetUserId()
    if clientID <= 0 then return end

    local data = GetPlayerData(self,clientID)
    local player = _client:GetControllingPlayer()
    data.name = player:GetName()
end

function Plugin:ClientDisconnect( _client )
    local clientID = _client:GetUserId()
    if clientID <= 0 then return end

    TrackClient(self,_client,clientID)
end

function Plugin:CreateMessageCommands()
    local setCommand = self:BindCommand( "sh_prewarm", "prewarm", function(_client) NotifyClient(self,_client,nil) end,true )
    setCommand:Help( "显示你的预热状态.")
    
    local validateCommand = self:BindCommand( "sh_prewarm_validate", "prewarm_validate", function(_client,_targetID,_tier,_credit) ValidateClient(self,_targetID,nil,_tier,_credit) end,true )
    validateCommand:AddParam{ Type = "steamid" }
    validateCommand:AddParam{ Type = "number", Round = true, Min = 1, Max = 4, Default = 4 }
    validateCommand:AddParam{ Type = "number", Round = true, Min = 0, Max = 15, Default = 3 }
    validateCommand:Help( "设置玩家的预热状态以及预热点数,例如!prewarm_validate 4 3.(设置玩家段位4并给予3点预热点)")
end

return Plugin
