function widget:GetInfo()
  return {
    name      = "XTransportAI",
    desc      = "Keep Transporters going to transport units to its target Shortcut Select unit shift+t(default Keycode 116) and move unit to call transport",
    author    = "Ramthis",
    date      = "Sep 17, 2023",
	version   = "1.9.1", --ALPHA
    license   = "GNU GPL, v3 or later",
    layer     = 0,
    enabled   = true,  --  loaded by default?
	handler   = true
  }
end

--TO DO
--Dropzone 
--CMdid checken weil wenn ich den command ziehe dann muss es id sein  first und last command
-- Moveroute und Retreatmentpoint wenn Units noch zu transportieren sind Mögliche Lösung der Transporter nimmt die umgekehrte Route von der zukünftigen Einheit  so das der Transporter und Unit auf der Route treffen 
-- Guard Units funktioniert nicht mehr 
-- wenn der transporter zu nah an der Fab ist bekommt die Fab nicht alle comands übertragen an die Unit weswegen der Transporter nicht der route folgen kann
--t2 trans unload Problem

KeycodeTransport=116 --Keypress event 116=t
KeycodeGuard=103--Keypress event 103=g
KeycodeLoadOnly=98--Keypress event 98=b
MinTimeToTarget=10 -- The Minimun Time otherwise the Unit will not be pickup
MaxTargetDistance=100


Lastcheck=Spring.GetGameSeconds()

Transporters = {}
Units={}
Factories={} 
GuardedUnits={}
GuardTransports={}
GuardedFabs={}
PlayerId={}
teamId ={}
Ignorelist ={"armpw","armflea","armflash","armfav","armbanth","armraz","armmar","armvang","armlun","armthor","corak","corgator","corshiva","corseal","corkarg","corjugg","corcat","corsok","corkorg"}--Unit Ignorlist this units will be ignored
NoFab={"armfhp","corfhp","armamsub","coramsub","armplat","corplat","armasy","corasy","armsy","corsy","armshltxuw","corgantuw"}-- This are no Fabs because the Trans uses random Fabs as Retreatmentpoint and a Trans should not move to this Fabs
TransportAllFactories=false -- if false 

Debugmode=false
DebugCategories={}

transport_states={
	idle=0,
	approaching=1,
	picking_up=2,
	loaded=3, 
	arrived=4,
	move_to_retreatpoint=5,
	unloaded=6
}

function Log(Message,Category)
	DoLog=false
	if Debugmode==true then
		for i=1,#DebugCategories do
			if Category== DebugCategories[i] then
			DoLog=true
			break
			end
		end
		if DoLog==true then
			Spring.Echo(Message)
		end
	end
end




function Log(Message)
	if Debugmode==true then
		Spring.Echo(Message)
	end
end


function widget:Initialize()
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget()
	end
  
	PlayerId = Spring.GetMyPlayerID()
	_,_,_,teamId = Spring.GetPlayerInfo(PlayerId)
	if TransportAllFactories==true then
		GetAllFabs()
	end
	GetAllTransporters()
end


function widget:Update()
	local currentTime = Spring.GetGameSeconds()	
		UnPauseUnits()
		if Lastcheck<currentTime then
			CheckOnlyLoads()
			CheckGuardedTransport()
			CheckTransports()
			
			Lastcheck=currentTime+1
		end
end


function UnPauseUnits()
	for i=1,#Transporters do
		if Transporters[i].SleepTime~=-1 then
			local CMDS= FirstCommand(Transporters[i].unitid)
			if CMDS~=nil then
				if CMDS.id==CMD.WAIT then
					if Transporters[i].SleepTime<Spring.GetGameSeconds() then
						Spring.GiveOrderToUnit(Transporters[i].unitid,CMD.WAIT ,0,0 )
						Transporters[i].SleepTime=-1
					end
				end
			end
		end
	end
	

end


--#################################### Transporter Function ######################################################

Transporter={unitid=0,
	units={},
	state=0,
	TransportMass=0,
	UnitDEFS={},
	Capacity=0,
	Retreatpoint={},
	Targetpoint={},
	CurrentTransportMass=0,
	CurrentCapacity=0,
	Transportsize=0,
	Guard=-1,
	GuardFab=-1,
	LoadCount=1,
	SleepTime=-1,
	MoveRoute={},
	RetreatRoute={},
	StuckCount=0,
	OnlyLoad=false

}


function Transporter:new(unitid,state)
	o = {}
	setmetatable(o, {__index=self})
  
	  o.UnitDEFS=UnitDefs[Spring.GetUnitDefID(unitid)]
	  o.TransportMass=o.UnitDEFS.transportMass 
	  o.Capacity=o.UnitDEFS.transportCapacity 
	  o.Retreatpoint={}
	  o.Transportsize=o.UnitDEFS.transportSize
	  o.LoadCount=1
	  o.Guard=-1
	  o.unitid= unitid
	  o.state=state
	  o.SleepTime=-1
	  o.units={}
	  o.GuardFab=-1
	  o.MoveRoute={}
	  o.RetreatRoute={}
	  o.StuckCount=0
	  o.Targetpoint={}
	  o.OnlyLoad=false

	  Log(" unitid "..unitid.." Capacity "..o.Capacity.." TransportMass"..o.TransportMass)
	  return o
end

function Transporter:Sleep(seconds)
   Spring.GiveOrderToUnit(self.unitid,CMD.WAIT ,0,0 )--Load Unit
   Log("SLEEP ".. seconds)
   local currentTime = Spring.GetGameSeconds()
   self.SleepTime=currentTime+seconds
end


function Transporter:CanTransportUnit(Unit)
	local canTransport=false
	local TempCapacity=self.CurrentCapacity
	local TempTransportMass=self.CurrentTransportMass
	if TempCapacity<self.Capacity then
		--für T1
		if self.Capacity==1 then
		
			if self.TransportMass>=Unit.Mass then
					--table.insert(self.units,Unit) 
					canTransport=true
			end

		--für T2
		elseif self.Capacity>1 then

				Log(Unit.Mass)

				TempTransportMass=TempTransportMass +Unit.Mass
				--self.CurrentCapacity=(Unit.XSize/2)+self.CurrentCapacity
				local StaticValue=0

				if Unit.XSize==6 then
					 StaticValue=2.5
				elseif Unit.XSize==4 then
					StaticValue=2
				elseif Unit.XSize==2 then
					StaticValue=1
				end

				TempCapacity=TempCapacity+StaticValue

			if TempTransportMass<self.TransportMass then

				if self.Capacity>=TempCapacity then
					canTransport=true
				end
			else
				--self.CurrentTransportMass=self.CurrentTransportMass -Unit.Mass
				--self.CurrentCapacity=self.CurrentCapacity-StaticValue
				canTransport=false

			end
		

		end
	end
	return canTransport
end


function Transporter:AddUnit(Unit)
	local StaticValue=1
	if self:CanTransportUnit(Unit)==true then
		if self.Capacity==1 then

		else
			if Unit.XSize==6 then
					StaticValue=2.5
			elseif Unit.XSize==4 then
				StaticValue=2
			elseif Unit.XSize==2 then
				StaticValue=1
			end

		end
		if table.getn(self.units)==0 then
			if self.Guard==-1 then
				if Unit.targetpoint~=nil then
					self.Targetpoint=Unit.targetpoint
					Log ("Targetpoint "..Unit.targetpoint[1].." "..Unit.targetpoint[2].." "..Unit.targetpoint[3])
				end
			end
		end

		self.CurrentCapacity=self.CurrentCapacity+StaticValue
		self.CurrentTransportMass=self.CurrentTransportMass +Unit.Mass
		
		table.insert(self.units,Unit) 


	end
end


function Transporter:SortUnitsbyTarget()
	local i=1
	
	while  table.getn(self.units)>=i do
		if self.units[i].targetpoint~=nil then
			if table.getn(self.units[i].targetpoint)>0 then
				self.units[i]:GetTargetExpectationTime()
			end
		end
		i=i+1
	end
	table.sort(self.units, function(a, b) return a.TimeToTarget < b.TimeToTarget end)
end


function Transporter:LoadUnits()

	local Index=0
	local CMDCount= Spring.GetUnitCommands(self.unitid,-1)	
	if self.LoadCount>1 then
		if table.getn(self.units)>0 then
			local Trans= Spring.GetUnitTransporter(self.units[self.LoadCount-1].unitid) 
	
			if Trans==nil then
				self.LoadCount=self.LoadCount-1
			end
		end
	end

	Log("Transport Unitcount "..table.getn(self.units))
	Log("LoadCount "..self.LoadCount)
	if table.getn(self.units)>=self.LoadCount then
	Log("Trans"..self.unitid.."Unit"..self.units[self.LoadCount].unitid)
		if Spring.GetUnitTransporter(self.units[self.LoadCount].unitid)==nil then
			self.state=transport_states.approaching
			Log("Builder? "..tostring(IsBuilder(self.units[self.LoadCount].unitid)))
			Spring.GiveOrderToUnit(self.unitid,CMD.LOAD_UNITS ,self.units[self.LoadCount].unitid,{"right"} )--Load Unit
			self.LoadCount=self.LoadCount+1
		end
	else
			if self.OnlyLoad==false then
				self:MoveToTarget()
				self.LoadCount=1
			end
	end

end


function Transporter:GoGuardMode()
	Log("Transporter --"..self.unitid.." guard "..self.Guard)
	Spring.GiveOrderToUnit(self.unitid,CMD.GUARD ,self.Guard,{"left"} )--Load Unit
end



function Transporter:UnitsInRectancle(X1,Y1,X2,Y2)
	local Units= Spring.GetUnitsInRectangle(X1,Y1,X2,Y2) 
	Log("Units in Rectancle "..table.getn(Units))
	local i=1
	while table.getn(Units)>=i do
		if self.unitid==Units[i] then
			table.remove(Units,i)
			i=i-1
		end
		for j=1,#self.units do
			if self.units[j].unitid==Units[i] then
				table.remove(Units,i)
				i=i-1
				break
			end
		end
		i=i+1
	end
	return Units
end


function Transporter:GetNextTargetPoint(X,Y,Z)
	local factor= 70--self.units[x].XSize/2
	local Units=0--= self:UnitsInRectancle(X-factor,Y-factor,X+factor,Y+factor)
	local Find=false
	local TX=X
	local TY=Y
	local TZ=Z
	local i=1
	local j=1
	
	--if table.getn(Units)>0 then
		Log("SEARCH for new Targetpoint X "..X.." Y "..Y.." Z "..Z)
				
		while i<=10 and Find==false do
			local Direction=1	
	
			j=1
			TX=X+(factor*i)
			TY=Y-(factor*i)
	
			while j<=i*8 and Find==false do
				if j>1 then
					local factorY=(2*i)+1
	

					if j== factorY+1 then
						Direction=2
	

					elseif j==factorY*2 then
						Direction=3
	

					elseif j==factorY*3-1 then
						Direction=4

					end
							

					if	Direction==1 then
						TX=TX-(factor)

					elseif	Direction==2 then
						TY=TY+(factor)

					elseif	Direction==3 then
						TX=TX+(factor)

					elseif	Direction==4 then
						TY=TY-(factor)

					end
				end
				Units= self:UnitsInRectancle(TX-factor,TY-factor,TX+factor,TY+factor)
				Log("Look for Place X "..TX.." Y "..TY.." Z "..TZ .." Factor "..factor)
				Log("COUNT "..table.getn(Units))
				if table.getn(Units)==0 then
	
					Find=true
					Log("Find New Targetpoint X "..TX.." Y "..TY.." Z "..TZ)

				end
				j=j+1
					
			end
					
		i=i+1
		end
		
	--end
	return TX,TY,TZ
end






function Transporter:Unload(Counter)
	self.state=transport_states.arrived
	Counter=Counter+1
	local factor= 70
	-- -1 stuck mode nehme den nächsten Punkt
	if table.getn(self.units)>0 then
	local x=0
	if self.units[1].targetpoint~=nil then
		while x<self.StuckCount do
			local X=self.units[1].targetpoint[1]		
			local Z=self.units[1].targetpoint[2]				
			local Y=self.units[1].targetpoint[3]

			local TX,TY,TZ= self:GetNextTargetPoint(X,Y,Z)
			self.units[1].targetpoint[1]=TX	
			self.units[1].targetpoint[2]=TZ				
			self.units[1].targetpoint[3]=TY
			x=x+1
		end
		if Counter<20 then
		Log("Unit in Transporter"..table.getn(self.units))
		
				local X=self.units[1].targetpoint[1]		
				local Z=self.units[1].targetpoint[2]				
				local Y=self.units[1].targetpoint[3]
			
				local Units= self:UnitsInRectancle(X-factor,Y-factor,X+factor,Y+factor)
				local TX,TY,TZ= self:GetNextTargetPoint(X,Y,Z)
				local Test=false

				if table.getn(Units)>0 then
					self.units[1].targetpoint[1]=TX	
					self.units[1].targetpoint[2]=TZ				
					self.units[1].targetpoint[3]=TY
					self:Unload(Counter)
					--Test=  Spring.GiveOrderToUnit(self.unitid,CMD.UNLOAD_UNIT,{TX,TZ,TY,self.units[1].unitid},{"left"})--Move to Target 
				else
					Test=  Spring.GiveOrderToUnit(self.unitid,CMD.UNLOAD_UNIT,{X,Z,Y,self.units[1].unitid},{"left"})--Move to Target 
					Log("Unload"..self.unitid..tostring(Test))
				end
			
			

				if Test==false then
					self.units[1].targetpoint[1]=TX	
					self.units[1].targetpoint[2]=TZ				
					self.units[1].targetpoint[3]=TY
					self:Unload(Counter)
					--TX,TY,TZ= self:GetNextTargetPoint(TX,TY,TZ)
					--Spring.GiveOrderToUnit(self.unitid,CMD.UNLOAD_UNIT,{TX,TZ,TY,self.units[1].unitid},{"left"})--Move to Target 
				end
		
			end
			--[[	
			else
				self.state=transport_states.unloaded
				Log("Unloaded Transporter "..self.unitid.." State "..self.state)
				self.units={}
				--self.UnloadCount=1
				self.CurrentTransportMass=0
				self.CurrentCapacity=0
			
				if self.Guard==-1 then
					Log("Go to Retreatmentpoint")
					self:MoveToRetreatPoint()
				else
					Log("Go Guarding")
					self:GoGuardMode()
				end

				]]--	
		end
	end
end


function Transporter:IndexOfUnit(unitID)
	local Index=-1
	local i=1
	Log	("Unitcount "..table.getn(self.units))
	local count=table.getn(self.units)
		while count>=i and Index==-1 do 
			if self.units[i].unitid==unitID then
				Index=i
			end
		i=i+1
		end
		return Index

end


function Transporter:RemoveUnit(unitID)
	local Index=self:IndexOfUnit(unitID)

	if Index>0 then
		if table.getn(self.units)>1 then
			self.CurrentCapacity=self.CurrentCapacity-1
			self.CurrentTransportMass=self.CurrentTransportMass-self.units[Index].Mass
			table.remove(self.units,Index)

			if self.state==transport_states.approaching then
				self:LoadUnits()
			end

		else
			self.units={}
			self.StuckCount=0
			self.CurrentTransportMass=0
			self.CurrentCapacity=0
			self.state=transport_states.unloaded
			if self.OnlyLoad==false then
				if self.Guard==-1 then
					Log("Go to Retreatmentpoint")
					self:MoveToRetreatPoint()
				else
					Log("Go Guarding")
					self:GoGuardMode()
				end

			end
		end
	end

end


function Transporter:MoveToRetreatPoint()
		Log	("Unitcount "..table.getn(self.units))
		self.state=transport_states.move_to_retreatpoint
		local Route=false
		if	table.getn(self.units)==0 then
			local FabID=-1

			local j=table.getn(self.RetreatRoute)
			Log("Command count Retreat "..j)
			if j>0 then
				Route=true
				Log("Route=true")
				while j>0 do
					if self.RetreatRoute[j].id == CMD.MOVE then
						Log("Command"..self.RetreatRoute[j].id.."X"..self.RetreatRoute[j].params[1])
					--Spring.GiveOrderToUnit(unitID,CMD.INSERT, {-1,CMD.MOVE,CMD.OPT_SHIFT,unitID2}, {"alt"}  );
						Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, self.RetreatRoute[j].params,{"shift","right"})
					end
					j=j-1
				end
			end


			if self.GuardFab~=-1 then 
				FabID=self.GuardFab
				--Spring.GiveOrderToUnit(Transid, ,unitid,{"left"} )--Load Unit
				Spring.GiveOrderToUnit(self.unitid,CMD.GUARD,FabID ,{"shift","left"})--Move to Target 
				Log("Guard to retreatpoint Transporter "..self.unitid.." State "..self.state)

			else
				
					FabID=GetNextFab()--removen von Fabs 
					if FabID~=-1 then
						local XP,YP,ZP=Spring.GetUnitPosition(FabID)
						self.Retreatpoint={XP+300,YP,ZP+300}
						if Route==false then 
							Log("Move ohne Shift")
							Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, self.Retreatpoint,{"right"})--Move to Target 
						else
							Log("Move mit Shift")
							Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, self.Retreatpoint,{"shift","right"})--Move to Target 
						end
						Log("Move to retreatpoint Transporter "..self.unitid.." State "..self.state)
					
					end	
				
			end

			if Route ==false then
				local XP,YP,ZP=Spring.GetUnitPosition(self.unitid)
				self.Retreatpoint={XP+100,YP,ZP+100}
				Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, self.Retreatpoint,{"right"})--Move to Target 
						--else
							--Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, self.Retreatpoint,{"shift","right"})--Move to Target 
						--end
			end
			
		end
		self.targetpoint={}
		self.MoveRoute={}
		self.RetreatRoute={}
			
end


function Transporter:Idle()
	if table.getn(self.units)==0 then
		self.state=transport_states.idle
		Log("Idle Transporter "..self.unitid.." State "..self.state)
	end

end



function Transporter:MoveToTarget()
	--self:SortUnitsbyTarget()
	
	
	if table.getn(self.units)>0 then
		if self.units[1].targetpoint~=nil then
			local X=self.units[1].targetpoint[1]		
			local Z=self.units[1].targetpoint[2]				
			local Y=self.units[1].targetpoint[3]				
			local TX,TY,TZ= self:GetNextTargetPoint(X,Y,Z)
			if table.getn(self.MoveRoute)>0 then
				
				-- Übertragen der Commands
			
				local j=1
				while j<=table.getn(self.MoveRoute) do
					if self.MoveRoute[j].id == CMD.MOVE then
						Log("Command"..self.MoveRoute[j].id.."X"..self.MoveRoute[j].params[1])
					--Spring.GiveOrderToUnit(unitID,CMD.INSERT, {-1,CMD.MOVE,CMD.OPT_SHIFT,unitID2}, {"alt"}  );
						Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, self.MoveRoute[j].params,self.MoveRoute[j].options)
					end
					j=j+1
				end
		
			else
				Spring.GiveOrderToUnit(self.unitid,CMD.MOVE, {TX,TZ,TY},{"right"})--Move to Target 
			end
			self.state=transport_states.loaded
		
			Log("Move Target Transporter "..self.unitid.." State "..self.state .. "Target X"..self.units[1].targetpoint[1].. "Target Y"..self.units[1].targetpoint[2].. "Target Z"..self.units[1].targetpoint[3])

		end
	end
end

function Transporter:GetExpectedTransportTime( Unit )

	local CurrentTransPosition={Spring.GetUnitPosition(self.unitid)}
	local CurrentUnitPosition={Spring.GetUnitPosition(Unit.unitid)}
	local UnitPickupDistance=Distance(CurrentTransPosition,CurrentUnitPosition)
	local TimetoPickup=UnitPickupDistance/self.UnitDEFS.speed 

	local TargetDistance= Distance(CurrentUnitPosition,Unit.targetpoint)
	local TimeToTarget=TargetDistance/self.UnitDEFS.speed 
	local TimeResult=TimeToTarget+TimetoPickup

	return TimeResult

end



--##################################### Unit Functions #####################################

Unit=
{
	unitid=0,
	targetpoint=nil,
	UnitDEFS={},
	Mass=0,
	XSize =0,
	IsFactory=false,
	IsBuilder=false,
	GuardUnit=-1,
	TimeToTarget=-1,
	BuilderID=-1,
	OnlyFromFabTrans=false,
	MoveRoute={},
	SavedCommands={},
	
	OnlyLoad=false

}


function Unit:new(unitid)

	o = {}
	setmetatable(o, {__index=self})
  
	o.targetpoint=nil
  
	o.UnitDEFS=UnitDefs[Spring.GetUnitDefID(unitid)]
	o.IsFactory=o.UnitDEFS.isFactory
	o.XSize=o.UnitDEFS.xsize
	o.IsBuilder=o.UnitDEFS.isBuilder
	o.Mass=o.UnitDEFS.mass
	o.unitid = unitid 
	o.TimeToTarget=-1
	o.BuilderID=-1
	o.OnlyFromFabTrans=false
	o.MoveRoute={}
	o.SavedCommands={}
	o.OnlyLoad=false
	return o

end



function Unit:GetTargetExpectationTime()

	if self.targetpoint~=nil then
		local TempTimeToTarget=-1
		local Position={Spring.GetUnitPosition(self.unitid)}
		
		local TargetDistance=0
		if table.getn(self.MoveRoute)>0 then
			for i=1, #self.MoveRoute do

				 TargetDistance=TargetDistance+Distance(Position,self.MoveRoute[i].params)	
				 Position=self.MoveRoute[i].params
			end
		else
			 TargetDistance=Distance(Position,self.targetpoint)	
		end

		self.TimeToTarget=TargetDistance/self.UnitDEFS.speed
		
	end

end

function Unit:SetTargetpoint(Targetpoint)
	local X=Targetpoint[1]+50
	local Y=Targetpoint[2]
	local Z=Targetpoint[3]+50
	self.targetpoint={X,Y,Z}
	Log("Set Targetpoint ".. self.targetpoint[1].." Unitid "..self.unitid)
	
end

--################################# Global Function ##############################################

function Distance(Point1,Point2)

	local Distance=-1
	if Point1~=nil and Point2~=nil then
		if table.getn(Point2)>2 and table.getn(Point1)>2 then
			local ResultX=Point1[1]-Point2[1]
			local ResultY=Point1[2]-Point2[2]
			local ResultZ=Point1[3]-Point2[3]

			local SqaureSum=math.pow(ResultX,2)+math.pow(ResultY,2)+math.pow(ResultZ,2)
			Distance=math.sqrt (SqaureSum)
		end
	end

	return Distance
end


function AddUnit(unitID)
   local UnitIndex=FindUnit(unitID)
   Log("Index: "..UnitIndex)
	if UnitIndex==-1 then

		local Unit=Unit:new (unitID)
		table.insert(Units,Unit) 

	end


end

function AddTransporter(unitID)
	local TransIndex=FindTransport(unitID)
	if TransIndex==-1 then

		local transporter=Transporter:new (unitID,transport_states.idle)
		table.insert(Transporters,transporter) 
		ShowTransportValue()
	end
	
end

function AddGuardedFab(unitID)
	local FabIndex=FindGuardedFab(unitID)
	if FabIndex==-1 then

		
		table.insert(GuardedFabs,unitID) 
	end
	
end

function RemoveGuardedFab(unitID)
	local FabIndex=FindGuardUnit(unitID)
	
	if FabIndex>-1 then
		table.remove(GuardedFabs,FabIndex) 

	end
	
end


function DestroyGuardTransporter(unitID)
	local TransIndex=FindGuardTransport(unitID)
	
	if TransIndex>-1 then
		local PassengerID=GuardTransports[TransIndex].Guard	
		RemoveGuardUnit(PassengerID)
		table.remove(GuardTransports,TransIndex) 
		
	end
	--GetAllTransporters()
	--AddTransporter(unitID)
	
end

function RemoveGuardTransporter(unitID)
	local TransIndex=FindGuardTransport(unitID)
	if TransIndex>-1 then
		local PassengerID=GuardTransports[TransIndex].Guard	
		RemoveGuardUnit(PassengerID)
		table.remove(GuardTransports,TransIndex) 
		AddTransporter(unitID)
	end
end


function RemoveGuardUnit(unitID)
	local UnitIndex=FindGuardUnit(unitID)
	if UnitIndex>-1 then
		table.remove(GuardedUnits,UnitIndex) 
	end
end


function AddGuardTransporter(unitID)
	local TransIndex=FindGuardTransport(unitID)
	RemoveTransporter(unitID)
	if TransIndex==-1 then
		local transporter=Transporter:new (unitID,transport_states.idle)
		table.insert(GuardTransports,transporter) 
	end
end


function AddGuardUnit(unitID)
	local UnitIndex=FindGuardUnit(unitID)
	RemoveUnit(unitID)
	if UnitIndex==-1 then
		Log("Add GuardUnit")
		local Unit=Unit:new (unitID)
		table.insert(GuardedUnits,Unit) 
	end
end


function AddFab(unitID)
	local FabIndex=FindFab(unitID)
	if FabIndex==-1 then
		table.insert(Factories,unitID) 
	end
end


function GetAllFabs()
	local playerUnits = Spring.GetTeamUnits(teamId)
	Factories={}
	for i = 1, #playerUnits do
		if IsFab(playerUnits[i]) ==true then
			AddFab(playerUnits[i])
		end
	end
end


function IsFab(unitID)
	local Index=Spring.GetUnitDefID(unitID)
	local IsFactory=false
	
	if Index~=nil then
		Log("IsFAB Index ".. Index)
		local UnitDEFS=UnitDefs[Index]
		local Name= UnitDEFS.name
		IsFactory=UnitDEFS.isFactory
		for i=1,#NoFab do
			if NoFab[i]==Name then
		
			IsFactory=false
			end
		end
	end
	  
	return IsFactory
end


function GetAllTransporters()

	local playerUnits = Spring.GetTeamUnits(teamId)
	Transporters={}
	for i = 1, #playerUnits do
		if IsTransporter(playerUnits[i])==true then
			AddTransporter(playerUnits[i])
		end
	end
end


function RemoveTransporter(unitID)
	local TransIndex= FindTransport(unitID)
	if TransIndex>-1 then
		table.remove(Transporters,TransIndex)
	end
	ShowTransportValue()
end



function RemoveUnit(unitID)
	local UnitIndex= FindUnit(unitID)
		if UnitIndex>-1 then
			
			table.remove(Units,UnitIndex)
		end
end


function DestroyUnit(unitID)
		local UnitIndex= FindUnit(unitID)

		if UnitIndex>-1 then
			table.remove(Units,UnitIndex)
			
		end

		for i=1,#Transporters do
			Transporters[i]:RemoveUnit(unitID)
		end
end


function RemoveFab(unitID)
	local FabIndex= FindFab(unitID)
	if FabIndex>-1 then
		table.remove(Factories,FabIndex)
	end
end


function IsTransporter(unitID)
	 local Index=Spring.GetUnitDefID(unitID)
		 if Index~=nil then

			return UnitDefs[Index].isTransport
	    else
			return false
		end
end


function IsBuilder(unitID)
	local isBuilder=UnitDefs[Spring.GetUnitDefID(unitID)].isBuilder
	return isBuilder
end





function GetNeareastTransporter(Unit,Modus)

	local TransDistance=-1
	local Transindex=-1
	local Unitid=Unit.unitid
	local TempDistance=-1
	local Transport=false
	for i=1,#Transporters do
		Log("Check Transport"..i)
		if Transporters[i].state==transport_states.idle or Transporters[i].state==transport_states.move_to_retreatpoint or Transporters[i].state==transport_states.approaching  then 
			
			--Transporter überwacht eine Fab
			Log("Transport Guard "..Transporters[i].GuardFab)
			if Transporters[i].GuardFab~=-1 then
				--Ist die Unit aus dieser Fab
				if Transporters[i].GuardFab==Unit.BuilderID then
					--Ja dann einladen
					Transport=true
				
				end

			else
				Log("Unit.OnlyFromFabTrans ".. tostring(Unit.OnlyFromFabTrans))
				if Unit.OnlyFromFabTrans~=true  then
					Transport=true
				end
		    end
			
			-- Wenn eine Unit einen anderen Targetpoint hat als der Transporter der den Schwellwert 600 überschreitet wird ignoriert.
			Log("Transporters[i].Capacity "..Transporters[i].Capacity)
			if Transporters[i].Capacity>1 then
				Log("table.getn(Transporters[i].units) "..table.getn(Transporters[i].units))
				if table.getn(Transporters[i].units)>0 then
					if Modus==0 then
						Log("Transporters[i].Targetpoint ".. table.getn(Transporters[i].Targetpoint))
						Log("Unit.Targetpoint "..table.getn(Unit.targetpoint))

						local TargetDistance=Distance(Transporters[i].Targetpoint,Unit.targetpoint)
						Log("TargetDistance "..TargetDistance)
						if TargetDistance>MaxTargetDistance then
						
							Transport=false
						end
					elseif Modus==1 then
						Transport=false
					elseif Modus==2 then
						-- Nur Einladen
						if Transporters[i].units[1].OnlyLoad==true then
							if Unit.OnlyLoad==true then
								Transport=true
							else
								Transport=false
							end
						end
						
					end
				end
			end

			Log("Transport ".. tostring(Transport))

			--if FindFab(Unit.BuilderID)>-1 then--to be done was ist mit shift t 
			--end



			if Transport==true then
			

			

				if Transporters[i]:CanTransportUnit(Unit)==true then
					
					TempDistance= Spring.GetUnitSeparation(Unitid,Transporters[i].unitid)
					--Erste Transporter
					if TransDistance==-1 then
						TransDistance= TempDistance
						Transindex=i
					-- Transporter n
					elseif TransDistance>TempDistance then
						TransDistance= Spring.GetUnitSeparation(Unitid,Transporters[i].unitid)
						Transindex=i
					end


					Log("Unitid "..Unitid.."Transporters[i].unitid " ..Transporters[i].unitid.."Index "..i)
					Log("Distance"..TransDistance)


				end

			end
		end
		Transport=false
	end
	return Transindex

end

function ShowTransportValue()
	local i=1
	Log("============Start Transportvalue============")
	while  table.getn(Transporters)>=i do
		Log("ArrayIndex= "..i)
		Log("ID= "..Transporters[i].unitid)
		Log("TransportMass= "..Transporters[i].TransportMass)
		i=i+1
	end
	Log("============End Transportvalue============")
end


function ShowUnitsValue()
	local i=1
	Log("Transportvalue")
	while  table.getn(Transporters)>=i do
		Log("ID "..Transporters[i].unitid.."Index "..i .."Mass"..Transporters[i].TransportMass)
		i=i+1
	end
end



function SortAllUnits()
	local i=1
	while  table.getn(Units)>=i do
		Log("ID "..Units[i].unitid.."Index "..i .."TimeToTarget"..Units[i].TimeToTarget)
		i=i+1
	end
	i=1
	while  table.getn(Units)>=i do
		if Units[i].targetpoint~=nil then
			if table.getn(Units[i].targetpoint)>0 then
				Units[i]:GetTargetExpectationTime()
			end
		end
		i=i+1
	end
	i=1
	table.sort(Units, function(a, b) return a.TimeToTarget > b.TimeToTarget end)
	while  table.getn(Units)>=i do
		Log("ID "..Units[i].unitid.."Index "..i .."TimeToTarget"..Units[i].TimeToTarget)
		i=i+1
	end

end

function GetFarthestUnit()
	local Time=-1
	local unitindex=-1
	local i=1
	while  table.getn(Units)>=i do
		if Units[i].targetpoint~=nil then
			if table.getn(Units[i].targetpoint)>0 then
				Units[i]:GetTargetExpectationTime()
				if Units[i].TimeToTarget>10 then
					if Time< Units[i].TimeToTarget then
						Time= Units[i].TimeToTarget
						unitindex=i
					end
				
				end
				
			end
		end
		i=i+1
	end

	return unitindex
end


function CheckTransporterDistance()

	for i = 1, # Transporters do
		Log("Transporters[i].state "..Transporters[i].state)
		if Transporters[i].state==transport_states.approaching or Transporters[i].state==transport_states.move_to_retreatpoint then
			if table.getn(Transporters[i].units)>0 then
				for j=1, #Transporters[i].units do
					local Distance= Spring.GetUnitSeparation(Transporters[i].unitid,Transporters[i].units[j].unitid)
					Log("Distance "..Distance)
					if Distance~=nil then
						if Distance<200 then
							--Log("Isbuilder "..tostring(IsBuilder(Transporters[i].units[j].unitid)))
							--if IsBuilder(Transporters[i].units[j].unitid)==true then
								if IsPause(Transporters[i].units[j].unitid)==false then
									Spring.GiveOrderToUnit(Transporters[i].units[j].unitid,CMD.WAIT ,0,0 )--Load Unit
								end
								Log("WAIT")
							--else
								--Spring.GiveOrderToUnit(Transporters[i].units[j].unitid,CMD.STOP, {},{""})
							--end
						end
						if Distance<600 then

							Transporters[i]:LoadUnits()
						end

						if table.getn(Transporters[i].RetreatRoute)<2 then
							Transporters[i]:LoadUnits()
						end

					end
				end
			end
		end
	end
end


function CheckGuardedTransport()
	Log("GuardedUnits in Queue "..table.getn(GuardedUnits))

	for i=1,#GuardedUnits do

		Log("UnitID= "..GuardedUnits[i].unitid)
		local Velocity=Spring.GetUnitVelocity(GuardedUnits[i].unitid)

		local commands = Spring.GetUnitCommands(GuardedUnits[i].unitid, -1)

		Log("Move..".. Velocity)
		
		local IsBuilding= Spring.GetUnitIsBuilding (GuardedUnits[i].unitid )
		


		if Velocity~=0 then
			Log("Commands".. table.getn(commands))
			if table.getn(commands)>0 then
				local Transid=GuardedUnits[i].GuardUnit
				Log("Transid "..Transid)
				local Transindex= FindGuardTransport(Transid)
				Log("Transindex "..Transindex)
				Log("Unitscount".. table.getn(GuardTransports[Transindex].units))
				Log("Targetpoint"..tostring(table.getn(commands[1].params)))
				local Targetpoint=nil

				if table.getn(commands[1].params)>2 then
					Targetpoint=commands[1].params
				elseif table.getn(commands[1].params)==1 then
					local x, y, z =Spring.GetUnitPosition(commands[1].params[1])
					Targetpoint={x, y, z}
					Log("Commandernumber "..tostring(Targetpoint))
				end

				if Targetpoint~=nil then
					GuardedUnits[i]:SetTargetpoint(Targetpoint)
					GuardedUnits[i]:GetTargetExpectationTime()
					Log("GuardedUnits[i].TimeToTarget"..GuardedUnits[i].TimeToTarget)
					if GuardedUnits[i].TimeToTarget>MinTimeToTarget then
						Spring.GiveOrderToUnit(GuardedUnits[i].unitid,CMD.WAIT ,{},{} )--Load Unit
						Log("WAIT")
						GuardTransports[Transindex]:LoadUnits()
					end
				end
			end
		--[[else
			
			if IsBuilding==nil then
				if IsPause==false then
					--LoadCommands(GuardedUnits[i].unitid)
				else
					--UnPause(GuardedUnits[i].unitid)

				end
			end--]]
		end
	end
end

function CheckOnlyLoads()
	if Units~=nil then
		local i=1
		while i<= table.getn(Units)do
			if Units[i].OnlyLoad==true then
				local Transindex=0
				Transindex=GetNeareastTransporter(Units[i],2)-- welcher Transporter is am nächsten für diese Unit
				Transporters[Transindex]:AddUnit(Units[i])
				Transporters[Transindex].OnlyLoad=true
				RemoveUnit(Units[i].unitid)
				Transporters[Transindex]:LoadUnits()
			end
			i=i+1
		end
	end

end

function CheckTransports()
	
	if Units~=nil then
		SortAllUnits()
	
		CheckTransporterDistance()

		local Transport=false
		Log("Fabs in Queue "..table.getn(Factories))
		Log("Units in Queue "..table.getn(Units))
				local Transindex=0
				local i=1
				Log("Unitscounts"..table.getn(Units))
				--Check all Units

				while i<= table.getn(Units)do
					if Units[i].targetpoint~=nil then
						if Units[i].BuilderID~=-1 then
							local Distance= Spring.GetUnitSeparation(Units[i].BuilderID,Units[i].unitid)
							if Distance>100 then
								Transport=true
							end
						else
								Transport=true
						end
					
						if Units[i].OnlyLoad==true then
								Transport=false
						end


						if Transport==true then
						
						
							Units[i]:GetTargetExpectationTime()
							Log("TimeToTarget"..tostring(Units[i].TimeToTarget))
							if Units[i].TimeToTarget>MinTimeToTarget then
								Transindex=GetNeareastTransporter(Units[i],0)-- welcher Transporter is am nächsten für diese Unit
								Log("Transindex"..Transindex)
						
								if Transindex~=-1 then 
								--if Transporters[Transindex]:GetExpectedTransportTime(Units[i])-Units[i].TimeToTarget < Units[i].TimeToTarget/2 then
									Transporters[Transindex]:AddUnit(Units[i])
									if Units[i].BuilderID~=nil and Units[i].BuilderID~=-1  then 
										Log("Units[i].builderID"..Units[i].BuilderID)
										Transporters[Transindex].RetreatRoute=GetAllCommands(Units[i].BuilderID)
									else
										Log("To Pickuppoint")
										Transporters[Transindex].RetreatRoute=GetAllCommands(Units[i].unitid)
									end

									Log("Units[i].MoveRoute"..table.getn(Units[i].MoveRoute))
									Log("Transporters[Transindex].RetreatRoute"..table.getn(Transporters[Transindex].RetreatRoute))
									RemoveUnit(Units[i].unitid)
									local Commands=GetAllCommands(Transporters[Transindex].unitid)
								
									if table.getn(Commands)==1 then
										if Commands[1].id==CMD.GUARD then
											Transporters[Transindex]:LoadUnits()
										end

										if Transporters[Transindex].state==transport_states.move_to_retreatpoint then 
											Transporters[Transindex]:LoadUnits()
										end
									end

									if table.getn(Commands)==0 then
										Transporters[Transindex]:LoadUnits()
									end

									if Transporters[Transindex].state==transport_states.idle then
										Transporters[Transindex]:LoadUnits()
									end

									--if Transporters[Transindex].Guard==-1 then
										--Transporters[Transindex]:Sleep(0.5)
					
									--end
								end
							end
						end
					end
				i=i+1
				end

				local j=1
				--Check all Transports
				while j<=table.getn(Transporters) do
					local Transport =Transporters[j]
					local Passengers=Spring.GetUnitIsTransporting(Transport.unitid)
					if Passengers~=nil then
						if table.getn(Passengers)>0 then
							Log("(Passengers" ..table.getn(Passengers))
							local Commands=GetAllCommands(Transport.unitid)
							if table.getn(Commands)==0 then
								Log("Transport stuck" .. table.getn(Transport.units))
								if Transport.StuckCount<20 then
									Transport:Unload(1)
								end
								Transport.StuckCount=Transport.StuckCount+1
							end
						end
					end
					j=j+1
				end
	end
end

function UnitIsOnIgnoreList(unitDefID)

	local Name= UnitDefs[unitDefID].name
	local Find=false

	for i=1,#Ignorelist do
		
		if Ignorelist[i]==Name then
		
		 Find=true
		end
	end
	return Find

end

function GetNextFab()
    local UnitID=-1

	Log("Fabcount"..table.getn(Factories))
	
		if table.getn(Factories)>0 then
			local Index= math.random(1,table.getn(Factories))
			UnitID= Factories[Index]
		end
	Log("FabID "..UnitID)
	return UnitID

end

function FindIndex(ID,Array)

	local Index=-1
	for i = 1, #Array do
		if Array[i].unitid==ID then
			Index=i
			
			break
		end
	end
	Log("Array Index" .. Index)
	return Index
end



function FindTransport(unitID)
	Log("Transports")
	return FindIndex(unitID,Transporters)
end


function FindGuardTransport(unitID)
	Log("GuardedTransports")
	return FindIndex(unitID,GuardTransports)
end

function FindGuardUnit(unitID)
	Log("GuardedUnits")
	return FindIndex(unitID,GuardedUnits)
end

function FindUnit(unitID)
  Log("Units")
  return FindIndex(unitID,Units)
end

function FindFab(unitID)
	local Index=-1
	for i = 1, #Factories do
		if Factories[i]==unitID then
			Index=i
			break
		end
	end

	return Index
end

function FindGuardedFab(unitID)
	local Index=-1
	for i = 1, #GuardedFabs do
		if GuardedFabs[i]==unitID then
			Index=i
			break
		end
	end

	return Index
end

function CheckFabTransporter(Fabid)
	local Find=false
	for i = 1, #Transporters do
		if Transporters[i].GuardFab==Fabid then
			Find =true
			break
		end
	end

	if Find==false then
		
		Fabindex= FindGuardedFab(Fabid)
		if Fabindex~=-1 then
			table.remove(GuardedFabs,FabIndex)
		end
	end

	return Index
end


function FirstCommand(unitID)
	
    local commands = Spring.GetUnitCommands(unitID, -1)
	local ReturnCommand=nil
	if commands~=nil then
		local CMDCounts= table.getn(commands)
		Log("Commandscount"..CMDCounts )
		if CMDCounts>0 then
			ReturnCommand= commands[1]
		
		end
	end
	return ReturnCommand
end


function IsPause(unitID)
	
    local commands = Spring.GetUnitCommands(unitID, -1)
	local Pause=false
	if commands~=nil then
		local CMDCounts= table.getn(commands)
		Log("Commandscount"..CMDCounts )
		 for i=1,#commands do

			if commands[i].id==CMD.WAIT then
				Pause=true
				break

			end
		
		end
	end
	return Pause
	
end

function UnPause(unitID)
	
    local commands = Spring.GetUnitCommands(unitID, -1)
	
	if commands~=nil then
		local CMDCounts= table.getn(commands)
		Log("Commandscount"..CMDCounts )
		 for i=1,#commands do

			if commands[i].id==CMD.WAIT then
				Spring.GiveOrderToUnit(unitID, CMD.WAIT, 0, 0)
				break

			end
		
		end
	end
	
end

	
function LastCommand(unitID)
	
    local commands = Spring.GetUnitCommands(unitID, -1)

    local CMDCounts= table.getn(commands)

	if CMDCounts>0 then
		return commands[CMDCounts]
	else
		return nil
	end
end


function  GetAllCommands(unitID)
	local CMDCount= Spring.GetUnitCommands(unitID,-1)	
	-- Unit Commands kopieren aber nur Move
	return CMDCount
end

function CopyMoveCommandsInArray(unitID,Array)
	local CMDCount= Spring.GetUnitCommands(unitID,-1)	
	Log("Before Copy Commands"..table.getn(CMDCount))
	-- Unit Commands kopieren aber nur Move
	if table.getn(Array)==0 then
		for j=1,#CMDCount do
			if CMDCount[j].id == CMD.MOVE then
				table.insert(Array,CMDCount[j])
			end
		end	
	Log("After Copy Commands"..table.getn(Array))
	end
end


--[[function LoadCommands(unit_id)

		local UnitIndex=FindIndex(unit_id,GuardedUnits)
		
		local Trans= Spring.GetUnitTransporter(unit_id) 
		if Trans==nil then
			if UnitIndex>0 then
			
				if IsBuilder(unit_id)==true then
					local Unit=GuardedUnits[UnitIndex]
					local j=1

					if table.getn(Unit.SavedCommands)>0 then
						Log("SavedCommands"..table.getn(Unit.SavedCommands))	
						while j<=table.getn(Unit.SavedCommands) do
							Log("Load Command".. Unit.SavedCommands[j].id.."ID"..Unit.unitid)
							
							Spring.GiveOrderToUnit(Unit.unitid, Unit.SavedCommands[j].id, Unit.SavedCommands[j].params, Unit.SavedCommands[j].options)
							j=j+1
						end
						--Unit.SavedCommands={}
						--UnPause(Unit.unitid)
					
					end
				else
					Log("Stop Command")
					UnPause(Unit.unitid)
				end
			end
		end
		
end]]--

function CopyAllCommandsInArray(unitID,Array)
	local CMDCount= Spring.GetUnitCommands(unitID,-1)	
	Log("Before Copy Commands"..table.getn(CMDCount))
	
	if table.getn(Array)==0 then
		for j=1,#CMDCount do
			if CMDCount[j].id ~= CMD.WAIT then
				table.insert(Array,CMDCount[j])
			end
		end	
	Log("After Copy Commands"..table.getn(Array))
	end
end


--#################################### Widget Function ################################################

--manchmal geht er einfach zum retreatpoint und dann zu der Einheit die schon lange draussen ist dadurch verlängert sich die Strecke


function widget:UnitLoaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
	
	local Transport=nil
	local Guarded=false
	

	if IsTransporter(transportID)==true then
		
		local TransIndex=FindGuardTransport(transportID)
		if TransIndex>-1 then
			Transport=GuardTransports[TransIndex]
			UnitIndex=FindGuardUnit(unitID)
			Unit=GuardedUnits[UnitIndex]
			Guarded=true
			Unit.SavedCommands={}
			CopyAllCommandsInArray(Unit.unitid,Unit.SavedCommands)
			Log("Commands saved?".. table.getn(Unit.SavedCommands))						
			
		else
			TransIndex=FindTransport(transportID)
			if  TransIndex>-1 then
				Transport=Transporters[TransIndex]
				Guarded=false
			end
		end



		if Transport~=nil then
			if Transport.state~=nil then
				
				
				Log("Loading Done ".. transportID ) 
				if Guarded==false and Transport.OnlyLoad==false then
					CopyMoveCommandsInArray(unitID,Transport.MoveRoute)
					
				end
				
				
				
				Transport:LoadUnits()
				if Guarded==false then
					
					
					Transport:Sleep(0.5)
					
				end
				
			end
		end
	end
end

function widget:UnitUnloaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
	
	local Transport=nil
	local Guarded=false
	
	if IsTransporter(transportID)==true then
		
		local TransIndex=FindGuardTransport(transportID)
		if TransIndex>-1 then
			Transport=GuardTransports[TransIndex]
			Guarded=true
		else
			TransIndex=FindTransport(transportID)
			if  TransIndex>-1 then
				Transport=Transporters[TransIndex]
				Guarded=false
				Spring.GiveOrderToUnit(unitID,CMD.STOP, {},{""})
			end
		end
	end
	UnPause(unitID)
	
	

	if Transport~=nil then
		
		
			local Trans= Spring.GetUnitTransporter(unitID) 
			if Trans~=nil then
				
				Log("Unload try again")
							
			else
				--Transport.UnloadCount=Transport.UnloadCount+1
				Transport:RemoveUnit(unitID)
				Transport.MoveRoute={}
				

				
				Log("Unload Done Going Next ") 
			end
			Log("table.getn(Transport.units)"..table.getn(Transport.units))
			if table.getn(Transport.units)>0 then
				Transport:MoveToTarget()
				if Guarded==false then
					Transport:Sleep(0.5)
				end
			else
				
				Transport.OnlyLoad=false
				Transport:Idle()
				Log("Transport.OnlyLoad"..tostring(Transport.OnlyLoad))
			end
			
			

			--Transport:LoadUnits()
			
			
			
		
	end
end


function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	Log("Given")--schmiert hier ab
	if IsTransporter(unitID)==true then
		RemoveTransporter(unitID)
		DestroyGuardTransporter(unitID)

	elseif IsFab(unitID)==true then
		RemoveFab(unitID)

	else
		RemoveUnit(unitID)
		RemoveGuardUnit(unitID)
	end
end


function widget:UnitCmdDone(unit_id, unitDefID, unitTeam, cmdID, cmdTag)	
	Log("Command done "..cmdID.." unitID "..unit_id)
	local CMDCount= Spring.GetUnitCommands(unit_id,-1)	
	local Transport=nil
	local Guarded=false
	if IsTransporter(unit_id)==true then
		
		local TransIndex=FindGuardTransport(unit_id)
		if TransIndex>-1 then
			Transport=GuardTransports[TransIndex]
			Guarded=true
		else
			TransIndex=FindTransport(unit_id)
			if  TransIndex>-1 then
				Transport=Transporters[TransIndex]
				Guarded=false
			end
		end
	end			


	if cmdID==CMD.GUARD then
		if IsTransporter(unit_id)==true then
							
			local Transindex=FindTransport(unit_id)
			if  table.getn(Transporters[Transindex].units)<1 then
				if Transporters[Transindex].GuardFab~=-1 then
					local temp= Transporters[Transindex].GuardFab
					Transporters[Transindex].GuardFab=-1
					CheckFabTransporter(temp)
				end
			end
		end
	end

	if cmdID==CMD.MOVE then
				
			if Transport~=nil then
				Log("CMD MOVE done State"..Transport.state)
				if Transport.state==transport_states.loaded or Transport.state==transport_states.arrived then

				if table.getn(CMDCount)==0 then
					Log("Move Done ".. unit_id )  
					Transport:Unload(1)
					if Transport.Guard==-1 then
						Transport:Sleep(0.5)
					end
				end
					  
					
				elseif Transport.state==transport_states.move_to_retreatpoint then
					Log("Move Done Idle  ".. unit_id )  

					if table.getn(GetAllCommands(Transport.unitid))==0 then
						if table.getn(Transport.units)>0 then
							Log("Load")
							Transport:LoadUnits()
						else
							Log("go Idle")
							Transport:Idle()
						end
					end
				
					
				   
				end
			else
				if table.getn(CMDCount)==0 then
					Log("Target Reached ".. unit_id)
					RemoveUnit(unit_id)
				end
			end
	end

end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	local UnitDEFS=UnitDefs[unitDefID]
	local UnitIndex=FindUnit(unitID)
	local GuardTransIndex=FindGuardTransport(unitID)
	local GuardUnitIndex=FindGuardUnit(unitID)
	local CMDCount= Spring.GetUnitCommands(unitID,-1)	
	local x, y, z = Spring.GetUnitPosition(unitID)
	Log("Command incoming "..cmdID.." unitID "..unitID)
	 Log("Commands  "..tostring(table.getn(CMDCount)).." unitID "..unitID)
	--Log("Commmand --->"..cmdID)-- if -value it is the builddefid to build
	--Log("Parameter --->"..tostring(table.getn(cmdParams)))
	--Log("Get CMDPostion "..tostring(cmdParams[1]))
	--Log("Unit Position --->"..x.."--"..y.."--"..z.."--")
	--Log("Options --->"..tostring(cmdOpts))
	--Log("Tag --->"..tostring(cmdTag))
	--Log("Tag --->"..tostring(unitDefID))
	
	

	if cmdID==CMD.MOVE then
		if GuardTransIndex>-1 then
			local Trans= Spring.GetUnitTransporter(GuardTransports[GuardTransIndex].Guard) 
			if Trans==nil then
				Log("Remove Guard")
				RemoveGuardTransporter(unitID)
						
				
			end	
		end
	end


	if cmdID==CMD.GUARD then
		if IsTransporter(unitID)==true then
			--Pärchen bilden 1-1 Beziehung Transporter und Unit
			local UnitDEFS=UnitDefs[Spring.GetUnitDefID(cmdParams[1])]

			if IsFab(cmdParams[1])==true then
				local Transindex=FindTransport(unitID)
				if Transindex~=-1 then
					AddGuardedFab(cmdParams[1])
					Transporters[Transindex].GuardFab=cmdParams[1]
				end
			else

			--if UnitIsOnIgnoreList(unitDefID)==false then
				AddGuardTransporter(unitID)
				Log("Parameter ".. tostring(cmdParams[1]))
				AddGuardUnit(cmdParams[1])

				GuardUnitIndex=FindGuardUnit(cmdParams[1])
				GuardTransIndex=FindGuardTransport(unitID)

				-- Pärchen verbinden
				if GuardUnitIndex>-1 and GuardUnitIndex>-1 then
					Log("Guard accepted Transport "..unitID.."Unit "..cmdParams[1])
					GuardTransports[GuardTransIndex].Guard=GuardedUnits[GuardUnitIndex].unitid
					GuardTransports[GuardTransIndex]:AddUnit(GuardedUnits[GuardUnitIndex])
					GuardedUnits[GuardUnitIndex].GuardUnit=unitID
				end
			end
		end
	end

	
	


	if UnitIndex>-1 then
	
		if cmdID==CMD.MOVE then
			Units[UnitIndex]:SetTargetpoint(cmdParams)
			Log("Get MoveCMD  "..unitID .. "X "..cmdParams[1].."Y "..cmdParams[1].."Z "..cmdParams[3])
		
		elseif cmdID==CMD.FIGHT or cmdID==CMD.ATTACK then
			Log("Fight".. UnitDEFS.moveState)
			if UnitDEFS.moveState>0 then 
				Units[UnitIndex]:SetTargetpoint(cmdParams)
				
			end
		end	
	else
	if cmdID==CMD.MOVE then
		local Trans= Spring.GetUnitTransporter(unitID) 
		
		local UnitDEFS= UnitDefs[unitDefID]

		if UnitDEFS.moveState<0 then 
			if UnitDEFS.cantBeTransported==false then
			Log("Trans"..tostring(Trans))
				if Trans==nil then
					for i = 1, #Transporters do
						local TransIndex= Transporters[i]:IndexOfUnit(unitID)
						if TransIndex~=-1 then
						--löschen aus beiden Listen
							Log("Removed Unit".. unitID)
							Transporters[i]:RemoveUnit(unitID)

						end
					end
				end		
			end
		end
		end
	end
end


function widget:KeyPress(key, mods, isRepeat)
	Log("Key="..key)

	--if key == KeycodeTransport and mods.ctrl then -- strg + t
		--AutomaticTransport= not AutomaticTransport
	
	if key == KeycodeTransport or key == KeycodeLoadOnly and mods.shift then -- shift + t
		local selectedUnits = Spring.GetSelectedUnits()
		for i=1, #selectedUnits do
			 local unitid = selectedUnits[i]
			 local UnitDefID= Spring.GetUnitDefID(unitid)
			 local UnitDEFS= UnitDefs[UnitDefID]
			 if IsFab(unitid)==true then
				local FabIndex=FindFab(unitid)
				if FabIndex~=-1 then
					RemoveFab(unitid)
				else
					AddFab(unitid)
				end
			 end

			 --if UnitDEFS.moveState<0 then 
			if UnitDEFS.cantBeTransported==false then
				
				local UnitIndex= FindUnit(unitid)
				Log("UnitIndex:" .. UnitIndex)
					
				if UnitIndex==-1 then
					local NewUnit=Unit:new(unitid)
					if key == KeycodeLoadOnly then
						NewUnit.OnlyLoad=true
					else
						local COMMANDS= Spring.GetUnitCommands(unitid,-1)	
						if table.getn(COMMANDS)>0 then

							LastCommand= COMMANDS[table.getn(COMMANDS)]
							if LastCommand.id==CMD.MOVE then
								NewUnit:SetTargetpoint(LastCommand.params)
							end
						end
					end	
					table.insert(Units,NewUnit)		
						
				else
					RemoveUnit(unitid)
						
				end
			end
		end
	end	
	if key == KeycodeGuard    and mods.shift  then -- shift + g
		local selectedUnits = Spring.GetSelectedUnits()
		for i=1, #selectedUnits do
			local unitid = selectedUnits[i]
			local UnitDefID= Spring.GetUnitDefID(unitid)
			local UnitDEFS= UnitDefs[UnitDefID]
			 
			
			if IsTransporter(unitid)==true then
				local TransGuardindex=FindGuardTransport(unitid)
				local Transindex=FindTransport(unitid)

				if TransGuardindex~=-1 then
					if  table.getn(GuardTransports[TransGuardindex].units)<1 then
						
							
							local CMDCount= Spring.GetUnitCommands(unitid,-1)	
	
							for j=1,#CMDCount do
								Log("Remove Command")
								Spring.GiveOrderToUnit(unitid, CMD.REMOVE, {CMDCount[j].tag}, {})-- das funktioniert nicht zuverlässing
							end
						
					end
				
				end
				if Transindex~=-1 then
					if  table.getn(Transporters[Transindex].units)<1 then
						if Transporters[Transindex].GuardFab~=-1 then
							local temp= Transporters[Transindex].GuardFab
							Transporters[Transindex].GuardFab=-1
							CheckFabTransporter(temp)
							local CMDCount= Spring.GetUnitCommands(unitid,-1)	
	
							for j=1,#CMDCount do
								Log("Remove Command")
								Spring.GiveOrderToUnit(unitid, CMD.REMOVE, {CMDCount[j].tag}, {})-- das funktioniert nicht zuverlässing
							end
						end
					end
				end
			end

			

			if UnitDEFS.cantBeTransported==false then
				local UnitIndex= FindGuardUnit(unitid)
				Log("UnitIndex:" .. UnitIndex)
				
				if UnitIndex==-1 then
					local NewUnit=Unit:new(unitid)
					
					local Transindex=GetNeareastTransporter(NewUnit,1)-- welcher Transporter is am nächsten für diese Unit

					if Transindex>-1 then 
						local Transid=Transporters[Transindex].unitid
						RemoveTransporter(Transid)
						Spring.GiveOrderToUnit(Transid,CMD.GUARD ,unitid,{"left"} )--Load Unit
							
					end
						
				else
					local CMDCount= Spring.GetUnitCommands(GuardedUnits[UnitIndex].GuardUnit,-1)	--Transporter alle Commands löschen
	
					for j=1,#CMDCount do
						Log("Remove Command")
						Spring.GiveOrderToUnit(GuardedUnits[UnitIndex].GuardUnit, CMD.REMOVE, {CMDCount[j].tag}, {})-- das funktioniert nicht zuverlässing
					end
					RemoveGuardTransporter(GuardedUnits[UnitIndex].GuardUnit)
						
				end
				
			end
		end
	end
	
	

end


function widget:UnitTaken(unitID, unitDefID, newTeam, oldTeam)
	Log("Taken")-- schmiert hier ab  
	if IsTransporter(unitID)==true then
		AddTransporter(unitID)

	elseif IsFab(unitID) ==true then
		AddFab(unitID)
	end
end

function widget:DrawWorld()
    for i=1, #Units do
        local x, y, z = Spring.GetUnitPosition(Units[i].unitid)
		gl.PushMatrix()
		gl.Color(1, 0, 0, 1)
		--gl.Texture("T")
		gl.Translate(x,y,z)
		gl.Billboard()			
		gl.TexRect(0, 20, 10, 30)
		gl.PopMatrix()
    end
	for i=1, #Factories do
        local x, y, z = Spring.GetUnitPosition(Factories[i])
		gl.PushMatrix()
		gl.Color(1, 0, 0, 1)
		--gl.Texture("T")
		gl.Translate(x,y,z)
		gl.Billboard()			
		gl.TexRect(0, 20, 10, 30)
		gl.PopMatrix()
    end

end


--[[function widget:UnitIdle(unitID, unitDefID, unitTeam)

	if IsTransporter(unitID)==true then
		local TransIndex= FindTransport(unitID)

		if TransIndex>-1 then
			if table.getn(GetAllCommands(unitID))==0 then
				if table.getn(Transporters[TransIndex].units)==0 then
					Log("Unit Idle??")
					Transporters[TransIndex]:Idle()
				end
			end
		end
	end
end]]--


function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	Log("BOOM ".. unitID)
	if IsTransporter(unitID)==true then
		RemoveTransporter(unitID)
		DestroyGuardTransporter(unitID)

	elseif IsFab(unitID)==true then
		RemoveFab(unitID)

	else
		DestroyUnit(unitID)
		RemoveGuardUnit(unitID)
	end
end 


function widget:UnitFinished(unitID, unitDefID, teamID, builderID)
	local UnitDEFS= UnitDefs[unitDefID]
	local TeamID= Spring.GetUnitTeam(unitID)
	local X,Y,Z=Spring.GetUnitPosition(unitID)
	Log("Unitposition ".. unitID .." X "..X.." Y "..Y.." Z "..Z)
	if TeamID ==teamId then
		if IsTransporter(unitID)==true then
	
			AddTransporter(unitID)
			Log("Transporter Finish " .. unitID)
			

		elseif IsFab(unitID) ==true then
			if TransportAllFactories==true then

				AddFab(unitID)
			end
		
		--else
		end
	end
end

function widget:SelectionChanged(selection)
	local tempselection={}

	if table.getn(selection)>1 then

		for i=1,#selection  do
			if selection[i]~=nil then
				
				local Istransporter=IsTransporter(selection[i])
				if Istransporter~=nil then
				if Istransporter==false then
					table.insert(tempselection, selection[i])
					Log("Transport in Selection ".. i)
				end
				end
			end
		end

		

	if table.getn(tempselection)>0 then
			Log("New Selection "..table.getn(tempselection))
			Spring.SelectUnitArray(tempselection)
		end
	end
 

	
end
	
function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
	local UnitDEFS= UnitDefs[unitDefID]
	local TeamID= Spring.GetUnitTeam(unitID)
	local X,Y,Z=Spring.GetUnitPosition(unitID)
	local OnlyFromFabTrans=false;
	if TeamID ==teamId then
		if UnitIsOnIgnoreList(unitDefID)==false then
			if UnitDEFS.moveState<0 then 
					
				if UnitDEFS.cantBeTransported==false then
						
					if IsBuilder(unitID)==false then
						local NewUnit=Unit:new(unitID)
						
						Log("Unit Finish ".. NewUnit.unitid)
						for x=1,#Factories do
							Log("Fab "..Factories[x])
						end

						local UnitIndex=-1
						Log("BuilderID "..factID)



						if FindFab(factID)~=-1 then
							AddUnit(unitID)
							UnitIndex= FindUnit(unitID)
						else
							if FindGuardedFab(factID)~=-1 then
								AddUnit(unitID)
								UnitIndex= FindUnit(unitID)
								OnlyFromFabTrans=true
							end
						end
						if UnitIndex~=-1 then
							Units[UnitIndex].BuilderID=factID
							local COMMANDS= Spring.GetUnitCommands(unitID,-1)	
							if table.getn(COMMANDS)>0 then
								LastCommand= COMMANDS[table.getn(COMMANDS)]
								if LastCommand.id==CMD.MOVE then
									Units[UnitIndex]:SetTargetpoint(LastCommand.params)	
									Units[UnitIndex].OnlyFromFabTrans=OnlyFromFabTrans
								end
							end
						end

						Log("Unitposition ".. unitID .." X "..X.." Y "..Y.." Z "..Z)
					end
				end			
			end
		end
	end			
end
