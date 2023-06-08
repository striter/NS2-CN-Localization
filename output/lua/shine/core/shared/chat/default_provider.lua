--[[
	The default chat provider, providing 2-colour text using the vanilla chat system.
]]

local ColourElement = require "shine/lib/gui/richtext/elements/colour"
local TextElement = require "shine/lib/gui/richtext/elements/text"

local Floor = math.floor
local getmetatable = getmetatable
local TableConcat = table.concat
local TableEmpty = table.Empty
local type = type

local DefaultColour = Colour( 1, 1, 1 )
local DefaultProvider = {}

function DefaultProvider:SupportsRichText()
	return false
end

function DefaultProvider.ConvertRichTextToDualColour( Contents )
	local MessageParts = {}
	local CurrentText = {}
	local NumColours = 0

	for i = 1, #Contents do
		local Entry = Contents[ i ]
		local Type = type( Entry )

		if Type == "table" then
			local MetaTable = getmetatable( Entry )
			if MetaTable == TextElement then
				Type = "string"
				Entry = Entry.Value
			elseif MetaTable == ColourElement then
				Type = "cdata"
				Entry = Entry.Value
			end
		end

		if Type == "string" then
			if #MessageParts == 0 then
				NumColours = NumColours + 1
				MessageParts[ #MessageParts + 1 ] = DefaultColour
			end
			CurrentText[ #CurrentText + 1 ] = Entry
		elseif Type == "cdata" then
			if NumColours < 2 then
				if #CurrentText > 0 then
					MessageParts[ #MessageParts + 1 ] = TableConcat( CurrentText )
					TableEmpty( CurrentText )
				end

				if type( MessageParts[ #MessageParts ] ) == "cdata" then
					MessageParts[ #MessageParts ] = Entry
				else
					NumColours = NumColours + 1
					MessageParts[ #MessageParts + 1 ] = Entry
				end
			end
		end
	end

	if #MessageParts == 0 then return nil end

	MessageParts[ #MessageParts + 1 ] = TableConcat( CurrentText )

	return MessageParts
end

-- Converts a rich-text message into a 2-colour message.
-- Ideally clients of the API should use AddMessage instead when they know rich text is not supported.
function DefaultProvider:AddRichTextMessage( MessageData )
	if MessageData.FallbackMessage then
		local Message = MessageData.FallbackMessage
		if Message.Prefix then
			return self:AddDualColourMessage(
				Message.PrefixColour, Message.Prefix, Message.MessageColour, Message.Message
			)
		end
		return self:AddMessage( Message.MessageColour, Message.Message )
	end

	local MessageParts = self.ConvertRichTextToDualColour( MessageData.Message )
	if not MessageParts then return end

	if #MessageParts == 2 then
		-- Only a single colour, use the message component to display it.
		return self:AddMessage( MessageParts[ 1 ], MessageParts[ 2 ], MessageData.Targets )
	end

	return self:AddDualColourMessage(
		MessageParts[ 1 ], MessageParts[ 2 ], MessageParts[ 3 ], MessageParts[ 4 ], MessageData.Targets
	)
end

if Client then
	function DefaultProvider:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message )
		Shine.AddChatText(
			Floor( PrefixColour.r * 255 ),
			Floor( PrefixColour.g * 255 ),
			Floor( PrefixColour.b * 255 ),
			Prefix,
			MessageColour.r,
			MessageColour.g,
			MessageColour.b,
			Message
		)
	end
else
	function DefaultProvider:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message, Targets )
		Shine:NotifyDualColour(
			Targets,
			Floor( PrefixColour.r * 255 ),
			Floor( PrefixColour.g * 255 ),
			Floor( PrefixColour.b * 255 ),
			Prefix,
			Floor( MessageColour.r * 255 ),
			Floor( MessageColour.g * 255 ),
			Floor( MessageColour.b * 255 ),
			Message
		)
	end
end

function DefaultProvider:AddMessage( MessageColour, Message, Targets )
	return self:AddDualColourMessage( DefaultColour, "", MessageColour, Message, Targets )
end

return DefaultProvider
