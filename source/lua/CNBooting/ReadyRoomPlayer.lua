
local baseOnReadyRoomPlayerCreate = ReadyRoomPlayer.OnCreate

Shared.LinkClassToMap("ReadyRoomPlayer", ReadyRoomPlayer.kMapName, {scale = "float (0 to 4 by 0.02)"}, true)

function ReadyRoomPlayer:OnCreate()
    baseOnReadyRoomPlayerCreate(self)
    self.scale = 1
    self.estimateScale = 1
end

function ReadyRoomPlayer:OnAdjustModelCoords(modelCoords)
    local coords = modelCoords
    coords.xAxis = coords.xAxis * self.scale
    coords.yAxis = coords.yAxis * self.scale
    coords.zAxis = coords.zAxis * self.scale
    return coords
end

local baseGetTraceCapsule = ReadyRoomPlayer.GetTraceCapsule
function ReadyRoomPlayer:GetTraceCapsule()
    local height,radius = baseGetTraceCapsule(self)
    height = height * self.scale
    radius = radius * self.scale
    return height,radius
end

local baseGetControllerSize = ReadyRoomPlayer.GetControllerSize
function ReadyRoomPlayer:GetControllerSize()
    local height,radius = baseGetControllerSize(self)
    height = height * self.scale
    radius = radius * self.scale
    return height,radius
end

local kPlayerHeight = Player.kYExtents * 2 - 0.2
function ReadyRoomPlayer:OnPostUpdateCamera()
    local offset = -self:GetCrouchShrinkAmount() * self:GetCrouchAmount()
    self:SetCameraYOffset(kPlayerHeight*(self.scale-1) + offset *self.scale)
end

if Server then
    local function SwitchScale(self,estimateScale, thirdpersonOffset)
        local reset =  self.estimateScale == estimateScale
        self.estimateScale = reset and 1 or estimateScale
        -- self:SetIsThirdPerson( reset and 0 or thirdpersonOffset)
    end
    local baseHandleButtons = ReadyRoomPlayer.HandleButtons
    function ReadyRoomPlayer:HandleButtons(input)
        baseHandleButtons(self,input)
        if not self.scalePressed and bit.band(input.commands, Move.Weapon1 + Move.Weapon2 + Move.Weapon3) ~= 0 then
            self.scalePressed=true
            if bit.band(input.commands,Move.Weapon1) ~= 0 then
                SwitchScale(self,0.3,0.5)
            end
            
            if bit.band(input.commands,Move.Weapon2) ~= 0 then
                SwitchScale(self,2,2)
            end

            if bit.band(input.commands,Move.Weapon3) ~= 0 then
                SwitchScale(self,3,3)
            end
        else
            self.scalePressed=false
        end
        
        if self.scale == self.estimateScale then
            return
        end

        local backward = self.scale > self.estimateScale
        local delta = backward and -4 or 4
        local deltedScale = self.scale + delta * input.time
        local desireScale = backward and math.max(deltedScale,self.estimateScale) or math.min(deltedScale,self.estimateScale)
        self.scale = desireScale
        
        if self.scale == self.estimateScale then
            self:UpdateControllerFromEntity()
        end
    end
end