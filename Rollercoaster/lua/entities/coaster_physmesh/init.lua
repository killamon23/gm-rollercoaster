AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )
include( "mesh_physics.lua")

ENT.Segment = -1

function ENT:Initialize()

	self:SetModel("models/props_junk/PopCan01a.mdl")
	self.Model = "models/props_junk/PopCan01a.mdl"

	self:SetUseType( SIMPLE_USE )

	self:PhysicsInit(SOLID_CUSTOM)
	self:GetPhysicsObject():EnableMotion( false )
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_VPHYSICS)

	self:SetCustomCollisionCheck(true)

	//self:DrawShadow( false )

	self:SetAngles( Angle( 0, 0, 0 ) )

	//Network which segment we are
	self:SetSegment( self.Segment )

	//Figure out the resolution we should build our mesh at
	local convar = GetConVar("coaster_physmesh_resolution")
	local num = convar && convar:GetInt() or 10
	self:SetMeshResolution( num )

	//shh
	self:SetNoDraw( true )

	self:GetPhysicsObject():SetMass(500)

	timer.Simple(0.5, function()
		if IsValid( self ) then
			self.Initialized = true
			self:BuildMesh()
		end
	end )
end

function ENT:GetCoasterID()
	local ctrl = self:GetController()
	return IsValid( ctrl ) && ctrl.GetCoasterID && ctrl:GetCoasterID() or -1 
end

//Build the mesh for the specific segment
//This function is NOT controller only, call it on the segment you want to update the mesh on
function ENT:BuildMesh()
	//If we aren't yet initialized when this function is called stay the fuck still
	if !self.Initialized then return end

	local Controller = self:GetController()
	//If we have no controller, we really should not exist
	if !IsValid( Controller ) || !istable(Controller.Nodes) then self:Remove() return end

	//Make sure the client knows it's shit
	self:SetSegment( self.Segment )
	self.Resolution = math.Clamp(self.GetMeshResolution && self:GetMeshResolution() or 10, 1, 1000)

	//Make sure our segment has actual information
	if self.Segment < 2 or self.Segment >= #Controller.Nodes - 1 then return end

	//change width according to the track type
	local track = trackmanager.GetStatic(EnumNames.Tracks[Controller:GetTrackType()])
	if track then
		self.Tri_Width = track.PhysWidth or 30
	else self.Tri_Width = 30 end

	//We're starting up making a beam of cylinders
	physmesh_builder.Start( self.Tri_Width, self.Tri_Height ) 

	//Create some variables
	local CurNode = Controller.Nodes[ self.Segment ]
	local NextNode = Controller.Nodes[ self.Segment + 1 ]

	local LastAngle = Angle( 0, 0, 0 )
	local ThisAngle = Angle( 0, 0, 0 )

	local ThisPos = Vector( 0, 0, 0 )
	local NextPos = Vector( 0, 0, 0 )
	for i = 0, self.Resolution - 1 do
		ThisPos = Controller.CatmullRom:Point(self.Segment, i/self.Resolution)
		NextPos = Controller.CatmullRom:Point(self.Segment, (i+1)/self.Resolution)

		local ThisAngleVector = ThisPos - NextPos
		ThisAngle = ThisAngleVector:Angle()

		if IsValid( CurNode ) && IsValid( NextNode ) && CurNode.GetRoll && NextNode.GetRoll then
			local Roll = -Lerp( i/self.Resolution, math.NormalizeAngle( CurNode:GetRoll() ), NextNode:GetRoll() )	
			ThisAngle.r = Roll
		end

		if i==1 then LastAngle = ThisAngle end

		physmesh_builder.AddBeam(ThisPos, LastAngle, NextPos, ThisAngle, Radius )

		LastAngle = ThisAngle
	end

	local Remaining = physmesh_builder.EndBeam()

	//move all the positions so they are relative to ourselves
	for i=1, #Remaining do
		Remaining[i].pos = Remaining[i].pos - self:GetPos()
	end

	self:SetAngles( Angle( 0, 0, 0 ) )
	self:PhysicsFromMesh( Remaining, true ) //THIS MOTHERFUCKER
	self:GetPhysicsObject():EnableMotion( false )
	self:EnableCustomCollisions( )

	self:SetCustomCollisionCheck(true)

end

function ENT:Use(activator, caller)
	if IsValid(activator) then
		-- Find the closest cart, if one exists
		local closestDist = math.huge 
		local closestCart = nil
		for _, v in pairs( ents.FindByClass("coaster_cart") ) do
			local dist = IsValid( v) && v.CoasterID == self:GetCoasterID() && activator:GetPos():Distance( v:GetPos() ) or math.huge
			if dist < closestDist then
				closestDist = dist
				closestCart = v
			end
		end

		-- Check if we got a valid cart
		if IsValid( closestCart ) then
			-- Tell the seats module we want to enter the cart
			ForceEnterGivenCart( closestCart, activator, activator:GetPos() )
		end
	end
end

//Set the networkvar when the cvar changes
cvars.AddChangeCallback( "coaster_physmesh_resolution", function()
	local convar = GetConVar("coaster_physmesh_resolution")
	local num = convar && convar:GetInt() or 10

	//Go through all of the nodes and tell them to update their shit
	for k, v in pairs( ents.FindByClass("coaster_physmesh") ) do
		if IsValid( v ) then
			v:SetMeshResolution(num)
		end
	end
end )

function ENT:OnRemove()

end
