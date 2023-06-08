--[[
	Category panel.

	Separates objects into categories.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local Units = SGUI.Layout.Units
local Percentage = Units.Percentage
local Spacing = Units.Spacing
local UnitVector = Units.UnitVector

local TableRemove = table.remove
local TableRemoveByValue = table.RemoveByValue

local CategoryPanel = {}

SGUI.AddProperty( CategoryPanel, "CategoryHeight" )

CategoryPanel.CategoryHeight = 24
CategoryPanel.ScrollPos = Vector( 0, 0, 0 )
CategoryPanel.ScrollbarHeightOffset = 0
CategoryPanel.BufferAmount = 0

function CategoryPanel:Initialise()
	Controls.Panel.Initialise( self )

	self.Categories = {}
	self.NumCategories = 0
	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical", {} ) )

	self:SetScrollable()
end

function CategoryPanel:AddCategory( Name )
	local Categories = self.Categories

	local Button = self:Add( "Button" )
	Button:SetAutoSize( UnitVector( Percentage.ONE_HUNDRED, self.CategoryHeight ) )
	Button:SetText( Name )
	Button:SetStyleName( "CategoryPanelButton" )
	Button.InvalidateImmediately = true

	self.NumCategories = self.NumCategories + 1

	local CategoryObj = {
		Header = Button,
		Objects = {},
		Expanded = true,
		Name = Name
	}

	Categories[ self.NumCategories ] = CategoryObj

	self.Layout:AddElement( Button )

	function Button.DoClick()
		self:SetCategoryExpanded( Name, not CategoryObj.Expanded, Button.InvalidateImmediately )
	end

	return Button
end

function CategoryPanel:RemoveCategory( Name )
	local Categories = self.Categories
	local CategoryObj
	local Index

	--This is not ideal, but maintaining a name -> index mapping would be annoying.
	for i = 1, #Categories do
		local Category = Categories[ i ]

		if Category.Name == Name then
			Index = i
			CategoryObj = Category
			break
		end
	end

	if not CategoryObj then return end

	-- We get the total height taken up by this category, and destroy its objects.
	local Objects = CategoryObj.Objects
	for i = 1, #Objects do
		local Object = Objects[ i ]
		Object.Removing = true
		Object:Destroy()
		self.Layout:RemoveElement( Object )
	end

	CategoryObj.Header:Destroy()
	self.Layout:RemoveElement( CategoryObj.Header )

	TableRemove( Categories, Index )

	self.NumCategories = self.NumCategories - 1
end

function CategoryPanel:SetCategoryExpanded( Name, Expand, InvalidateNow )
	local Categories = self.Categories
	for i = 1, #Categories do
		local Category = Categories[ i ]

		if Category.Name == Name then
			if Expand and Category.Expanded then return end
			if not Expand and not Category.Expanded then return end

			if not Expand then
				Category.Header:AddStylingState( "Collapsed" )
			else
				Category.Header:RemoveStylingState( "Collapsed" )
			end

			Found = true
			for j = 1, #Category.Objects do
				local Object = Category.Objects[ j ]
				Object:SetIsVisible( not not Expand )
			end

			Category.Expanded = not not Expand

			break
		end
	end

	self:InvalidateLayout( InvalidateNow )
end

-- Shortcut functions.
function CategoryPanel:ExpandCategory( Name, InvalidateNow )
	self:SetCategoryExpanded( Name, true, InvalidateNow )
end

function CategoryPanel:ContractCategory( Name, InvalidateNow )
	self:SetCategoryExpanded( Name, false, InvalidateNow )
end

function CategoryPanel:GetAllObjects()
	local AllObjects = {}
	local Categories = self.Categories

	for i = 1, self.NumCategories do
		local Category = Categories[ i ]
		local Objects = Category.Objects

		for j = 1, #Objects do
			AllObjects[ #AllObjects + 1 ] = Objects[ j ]
		end
	end

	return AllObjects
end

function CategoryPanel:GetCategory( Name )
	local Categories = self.Categories

	for i = 1, self.NumCategories do
		local Category = Categories[ i ]

		if Category.Name == Name then
			return Category
		end
	end

	return nil
end

function CategoryPanel:AddObject( CatName, Object )
	local CategoryObj = self:GetCategory( CatName )
	if not CategoryObj then return end

	local Objects = CategoryObj.Objects
	local LastObject = Objects[ #Objects ] or CategoryObj.Header

	self:Add( nil, Object )
	self.Layout:InsertElementAfter( LastObject, Object )

	Object:CallOnRemove( function()
		if not SGUI.IsValid( self ) or Object.Removing then
			-- The whole thing's being removed.
			return
		end

		TableRemoveByValue( Objects, Object )
	end )

	Objects[ #Objects + 1 ] = Object

	if not CategoryObj.Expanded then
		Object:SetIsVisible( false )
	end

	return Object
end

function CategoryPanel:RemoveObject( CatName, ObjectToRemove )
	local CategoryObj = self:GetCategory( CatName )
	if not CategoryObj then return false end

	local Objects = CategoryObj.Objects
	for i = 1, #Objects do
		local Object = Objects[ i ]
		if Object == ObjectToRemove then
			Object.Removing = true
			Object:Destroy()
			self.Layout:RemoveElement( Object )
			TableRemove( Objects, i )
			return true
		end
	end

	return false
end

SGUI:Register( "CategoryPanel", CategoryPanel, "Panel" )
