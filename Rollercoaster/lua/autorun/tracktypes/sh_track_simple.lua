include("autorun/sh_enums.lua")

local TRACK = TRACK && TRACK:Create()
if !TRACK then return end

TRACK.Name = "Simple Track"
TRACK.Description = "The bare basics of a track. Good for customization."
TRACK.PhysWidth = 30 //How wide the physics mesh should be

trackmanager.Register( EnumNames.Tracks[COASTER_TRACK_SIMPLE], TRACK )

if !CLIENT then return end

TRACK.Material = Material( "coaster/track_metal_clean")

-- Distance track beams away from eachother
local RailOffset = 25

TRACK.CylinderRadius = 4 -- Radius of the circular track beams
TRACK.CylinderPointCount = 7 -- How many points make the cylinder of the track mesh

local function GetAngleOfSubsegment( Controller, subsegment )
	local SubAngle = Angle( 0, 0, 0 )
	local NearSub = Controller.CatmullRom.Spline[subsegment+1] -- Get a subsegment that's just next to us
	local Reverse = Controller.CatmullRom.Spline[subsegment+1] == nil 
	if Reverse then NearSub = Controller.CatmullRom.Spline[subsegment-1] end -- If there isn't a next node, get a previous one

	local NextNode = Controller.Nodes[Controller:GetSplineSegment(subsegment) + 1]
	local CurrentNode = Controller.Nodes[ Controller:GetSplineSegment(subsegment) ]

	local Normal = NearSub - Controller.CatmullRom.Spline[subsegment]
	if Reverse then Normal = -Normal end 

	Normal:Normalize()
	SubAngle = Normal:Angle()

	//Get the percent along this segment, to calculate how much we'll roll
	local perc = Controller:PercAlongNode( subsegment )
	
	//Note all Lerps are negated. This is because the actual roll value from the gun is backwards.
	local Roll = Lerp( perc, math.NormalizeAngle( CurrentNode:GetRoll() ), NextNode:GetRoll())	

	-- Take into account roll
	SubAngle:RotateAroundAxis( Normal, Roll ) 

	return SubAngle, Normal
end 

function TRACK:CreateSideBeams( Position, Angle, Position2, Angle2, Node, CurrentCylinderAngle )
	local color = Node:GetActualTrackColor()
	//Side rails
	self.Cylinder:AddBeam( Position + Angle:Right() * -RailOffset, -- Position of beginning of cylinder
		self.LastCylinderAngle, -- The angle of the first radius of the cylinder
		Position2 + Angle2:Right() * -RailOffset, -- Position of end of cylinder
		CurrentCylinderAngle, 
		self.CylinderRadius, -- Radius of cylinder
		color) -- Color

	self.Cylinder:AddBeam( Position + Angle:Right() * RailOffset, 
		self.LastCylinderAngle, 
		Position2 + Angle2:Right() * RailOffset, 
		CurrentCylinderAngle, 
		self.CylinderRadius, 
		color ) 
end

function TRACK:Generate( Controller )
	if !IsValid( Controller ) || !Controller:GetIsController() then return end

	local Vertices = {} //Create an array that will hold an array of vertices (This is to split up the model)

	self.Cylinder = Cylinder:Create()

	self.BeginningSegmentAngle = nil
	self.BeginningSegmentCylinderAngle = nil 

	self.LastAngle = nil //Last angle so previous cylinder matches with the next cylinder
	self.LastNormal = nil
	self.LastCylinderAngle = nil

	//For every single spline segment 
	for i = 1, #Controller.CatmullRom.Spline do
		local CurrentNode = Controller.Nodes[ Controller:GetSplineSegment(i) ]
		local SubsegmentAngle, SubsegmentNormal = GetAngleOfSubsegment( Controller, i )

		if i == 1 then

			local CylinderAngle = SubsegmentNormal:Angle()
			CylinderAngle:RotateAroundAxis( SubsegmentNormal:Angle():Right(), -90 )
			CylinderAngle:RotateAroundAxis( SubsegmentNormal:Angle():Up(), -270 )

			self.LastCylinderAngle = CylinderAngle -- Since there was no 'last', this is the closest we have
			self.BeginningSegmentAngle = SubsegmentAngle -- Store the angle for the very last subsegment to match to
			self.BeginningSegmentCylinderAngle = CylinderAngle -- Ditto

			-- Here we have a special case. The first subsegment is after the first node, so we'll have to slap that in now
			self:CreateSideBeams( CurrentNode:GetPos(), SubsegmentAngle, Controller.CatmullRom.Spline[i], SubsegmentAngle, CurrentNode, CylinderAngle )

		end

		if self.LastAngle && self.LastNormal then

			-- Calculate the angle of the circle for the end of the cylinder
			local CylinderAngle = self.LastNormal:Angle()
			CylinderAngle:RotateAroundAxis( self.LastNormal:Angle():Right(), -90 )
			CylinderAngle:RotateAroundAxis( self.LastNormal:Angle():Up(), -270 )

			-- If this is the last segment, adjust the angles so it will seamlessly fit with the beginning of the track (if it's looped)
			if i == #Controller.CatmullRom.Spline && Controller:GetLooped() then
				SubsegmentAngle = self.BeginningSegmentAngle
				CylinderAngle = self.BeginningSegmentCylinderAngle
			end

			-- Create the beams
			self:CreateSideBeams( Controller.CatmullRom.Spline[i-1], self.LastAngle, Controller.CatmullRom.Spline[i], SubsegmentAngle, CurrentNode, CylinderAngle )

			self.LastCylinderAngle = CylinderAngle
		end


		-- Split the model into multiple meshes if it gets large
		if #self.Cylinder.Vertices > self:GetMaxVertices() then
			self:AddSubmesh( 1, self.Cylinder.Vertices)

			--Reset our cylinder builder
			self.Cylinder.Vertices = {}
			self.Cylinder.TriCount = 1
		end
		
		self.LastAngle = SubsegmentAngle
		self.LastNormal = SubsegmentNormal

		-- Check if we need to yield, and report some information
		self:CoroutineCheck( Controller, 1, nil, i / #Controller.CatmullRom.Spline)
	end	

	-- Add any extra vertices into their own mesh
	local verts = self.Cylinder:EndBeam()
	self:AddSubmesh( 1, verts)

	-- Finalize our track and end the generation function
	self:FinalizeTrack( Controller )
end

function TRACK:Draw( meshdata )

	render.SetMaterial(self.Material)
	self:DrawSection( 1, meshdata )

end

