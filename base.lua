local floor = math.floor;

function courseplay.prerequisitesPresent(specializations)
	return true;
end

function courseplay:onLoad(savegame)
	local xmlFile = self.xmlFile;
	self.setCourseplayFunc = courseplay.setCourseplayFunc;
	self.getIsCourseplayDriving = courseplay.getIsCourseplayDriving;
	self.setIsCourseplayDriving = courseplay.setIsCourseplayDriving;
	-- TODO: this is the worst programming practice ever. Defined as courseplay:setCpVar() but then self refers to the
	-- vehicle, this is the ugliest hack I've ever seen.
	self.setCpVar = courseplay.setCpVar;
	
	--SEARCH AND SET self.name IF NOT EXISTING
	if self.name == nil then
		self.name = courseplay:getObjectName(self, xmlFile);
	end;

	if self.cp == nil then self.cp = {}; end;

	-- TODO: some mods won't install properly as vehicle types and thus the courseplay event listeners are not
	-- installed for those. In that case, they'll have the Courseplay spec (as checked with hasSpecialization()) but
	-- onLoad is not called so they do not have a full CP setup, so as of now, we need this to verify if courseplay
	-- was correctly installed in this vehicle
	self.hasCourseplaySpec = true;

	self.cp.varMemory = {};

	-- XML FILE NAME VARIABLE
	if self.cp.xmlFileName == nil then
		self.cp.xmlFileName = courseplay.utils:getFileNameFromPath(self.configFileName);
	end;

	courseplay:setNameVariable(self);
	self.cp.isCombine = courseplay:isCombine(self);
	self.cp.isChopper = courseplay:isChopper(self);

	self.cp.speedDebugLine = "no speed info"

	--turn maneuver
	self.cp.waitForTurnTime = 0.00   --float

	self.cp.combineOffsetAutoMode = true
	self.cp.isDriving = false;
	
	self.cp.waypointIndex = 1;
	self.cp.previousWaypointIndex = 1;
	self.cp.recordingTimer = 1
	self.timer = 0.00
	self.cp.timers = {}; 
	self.cp.driveSlowTimer = 0;
	self.cp.positionWithCombine = nil;

	-- RECORDING
	self.cp.isRecording = false;
	self.cp.recordingIsPaused = false;
	self.cp.isRecordingTurnManeuver = false;
	self.cp.drivingDirReverse = false;

	self.cp.waitPoints = {};
	self.cp.numWaitPoints = 0;
	self.cp.unloadPoints = {};
	self.cp.numUnloadPoints = 0;
	self.cp.waitTime = 0;
	self.cp.crossingPoints = {};
	self.cp.numCrossingPoints = 0;


	self.Waypoints = {}
	self.cp.canDrive = false --can drive course (has >4 waypoints, is not recording)
	self.cp.coursePlayerNum = nil;

	self.cp.infoText = nil; -- info text in tractor
	self.cp.toolTip = nil;

	-- global info text - also displayed when not in vehicle
	self.cp.hasSetGlobalInfoTextThisLoop = {};
	self.cp.activeGlobalInfoTexts = {};
	self.cp.numActiveGlobalInfoTexts = 0;

	

	-- CP mode
	self.cp.mode = courseplay.MODE_TRANSPORT;
	--courseplay:setNextPrevModeVars(self);
	self.cp.modeState = 0
	-- for modes 4 and 6, this the index of the waypoint where the work begins
	self.cp.startWork = nil
	-- for modes 4 and 6, this the index of the waypoint where the work ends
	self.cp.stopWork = nil
	self.cp.abortWork = nil
	self.cp.abortWorkExtraMoveBack = 0;
	self.cp.hasUnloadingRefillingCourse = false;
	self.cp.wait = true;
	self.cp.waitTimer = nil;
	self.cp.canSwitchMode = false;
	self.cp.slippingStage = 0;
	self.cp.saveFuel = false;
	self.cp.hasAugerWagon = false;
	self.cp.generationPosition = {}
	self.cp.generationPosition.hasSavedPosition = false

	-- Visual i3D waypoint signs
	self.cp.signs = {
		crossing = {};
		current = {};
	};

	self.cp.numCourses = 1;
	self.cp.numWaypoints = 0;
	self.cp.currentCourseName = nil;
	self.cp.currentCourseId = 0;
	self.cp.lastMergedWP = 0;

	self.cp.loadedCourses = {}
	self.cp.course = {} -- as discussed with Peter, this could be the container for all waypoint stuff in one table
	
	-- forced waypoints
	self.cp.curTarget = {};
	self.cp.curTargetMode7 = {};
	self.cp.nextTargets = {};
	self.cp.turnTargets = {};
	self.cp.curTurnIndex = 1;

	-- alignment course data
	self.cp.alignment = { enabled = true }

	-- speed limits
	self.cp.speeds = {
		reverse =  6;
		turn =   10;
		field =  24;
		street = self:getCruiseControlMaxSpeed() or 50;
		crawl = 3;
		discharge = 8;
		bunkerSilo = 20;
		approach = 10;
		
		minReverse = 3;
		minTurn = 3;
		minField = 3;
		minStreet = 3;
		max = self:getCruiseControlMaxSpeed() or 60;
	};

	self.cp.orgRpm = nil;

	-- data basis for the Course list
	self.cp.reloadCourseItems = true
	self.cp.sorted = {item={}, info={}}	
	self.cp.folder_settings = {}
	courseplay.settings.update_folders(self)

	-- DIRECTION NODE SETUP
	local DirectionNode;
	if self.getAIVehicleDirectionNode ~= nil then -- Check if function exist before trying to use it
		if self.cp.componentNumAsDirectionNode then
			-- If we have specified a component node as the derection node in the special tools section, then use it.
			DirectionNode = self.components[self.cp.componentNumAsDirectionNode].node;
		else
			DirectionNode = self:getAIVehicleDirectionNode();
		end;
	else
		-- TODO: (Claus) Check Wheel Loaders Direction node a bit later.
		--if courseplay:isWheelloader(self)then
		--	if self.spec_articulatedAxis and self.spec_articulatedAxis.rotMin then
		--		local nodeIndex = Utils.getNoNil(self.cp.componentNumAsDirectionNode, 2)
		--		if self.components[nodeIndex] ~= nil then
		--			DirectionNode = self.components[nodeIndex].node;
		--		end
		--	end;
		--end
	end;

	-- If we cant get any valid direction node, then use the rootNode
	if DirectionNode == nil then
		DirectionNode = self.rootNode;
	end

	local directionNodeOffset, isTruck = courseplay:getVehicleDirectionNodeOffset(self, DirectionNode);
	if directionNodeOffset ~= 0 then
		self.cp.oldDirectionNode = DirectionNode;  -- Only used for debugging.
		DirectionNode = courseplay:createNewLinkedNode(self, "realDirectionNode", DirectionNode);
		setTranslation(DirectionNode, 0, 0, directionNodeOffset);
	end;
	self.cp.directionNode = DirectionNode;

	-- REVERSE DRIVING SETUP
	if SpecializationUtil.hasSpecialization(ReverseDriving, self.specializations) then
		self.cp.reverseDrivingDirectionNode = courseplay:createNewLinkedNode(self, "realReverseDrivingDirectionNode", self.cp.directionNode);
		setRotation(self.cp.reverseDrivingDirectionNode, 0, math.rad(180), 0);
	end;

	-- TRIGGERS
	self.findTipTriggerCallback = courseplay.findTipTriggerCallback;
	self.findSpecialTriggerCallback = courseplay.findSpecialTriggerCallback;
	self.findFuelTriggerCallback = courseplay.findFuelTriggerCallback;
	self.cp.hasRunRaycastThisLoop = {};
	self.findBlockingObjectCallbackLeft = courseplay.findBlockingObjectCallbackLeft;
	self.findBlockingObjectCallbackRight = courseplay.findBlockingObjectCallbackRight;
	self.findVehicleHeights = courseplay.findVehicleHeights; 
	
	self.cp.fillTriggers = {}
	
	if self.maxRotation then
		self.cp.steeringAngle = math.deg(self.maxRotation);
	else
		self.cp.steeringAngle = 30;
	end
	courseplay.debugVehicle( courseplay.DBG_COURSES, self, 'steering angle is %.1f', self.cp.steeringAngle)
	if isTruck then
		self.cp.revSteeringAngle = self.cp.steeringAngle * 0.25;
	end;
	if self.cp.steeringAngleCorrection then
		self.cp.steeringAngle = Utils.getNoNil(self.cp.steeringAngleCorrection, self.cp.steeringAngle);
	elseif self.cp.steeringAngleMultiplier then
		self.cp.steeringAngle = self.cp.steeringAngle * self.cp.steeringAngleMultiplier;
	end;

	-- traffic collision
	self.cpTrafficCollisionIgnoreList = {};
	if self.trafficCollisionIgnoreList == nil then
		self.trafficCollisionIgnoreList = {}
	end

	--aiTrafficCollisionTrigger
	self.aiTrafficCollisionTrigger = nil

	local ret_findAiCollisionTrigger = false
	ret_findAiCollisionTrigger = courseplay:findAiCollisionTrigger(self)

	-- create LegacyCollisionTriggers on load game ? -> vehicles not running CP are getting the collision snake

	if not CpManager.trafficCollisionIgnoreList[g_currentMission.terrainRootNode] then
		CpManager.trafficCollisionIgnoreList[g_currentMission.terrainRootNode] = true;
	end;

	courseplay:setOwnFillLevelsAndCapacities(self)

	-- workTools
	self.cp.workTools = {};
	self.cp.numWorkTools = 0;
	self.cp.workToolAttached = false;
	self.cp.prevTrailerDistance = 100.00;
	self.cp.totalFillLevel = nil;
	self.cp.totalCapacity = nil;
	self.cp.totalFillLevelPercent = 0;
	self.cp.prevFillLevelPct = nil;
	self.cp.tipRefOffset = 0;

	self.cp.offset = nil --self = combine [flt]
	self.cp.combineOffset = 0.0
	self.cp.tipperOffset = 0.0

	self.cp.forcedSide = nil
	
	self.cp.vehicleTurnRadius = courseplay:getVehicleTurnRadius(self);
	self.cp.turnDiameter = self.cp.vehicleTurnRadius * 2;
	self.cp.turnDiameterAuto = self.cp.vehicleTurnRadius * 2;
	self.cp.turnDiameterAutoMode = true;


	--Offset
	self.cp.laneOffset = 0;
	self.cp.totalOffsetX = 0;
	self.cp.loadUnloadOffsetX = 0;
	self.cp.loadUnloadOffsetZ = 0;
	self.cp.skipOffsetX = false;

	self.cp.workWidth = 3

	--old code ??
	self.cp.searchCombineAutomatically = true;
	self.cp.selectedCombineNumber = 0

	--Copy course
	self.cp.hasFoundCopyDriver = false;
	self.cp.copyCourseFromDriver = nil;
	self.cp.selectedDriverNumber = 0;

	--MultiTools
	self.cp.multiTools = 1;
	self.cp.laneNumber = 0;

	--Course generation	
	self.cp.startingCorner = 4;
	self.cp.hasStartingCorner = false;
	self.cp.startingDirection = 0;
	self.cp.rowDirectionDeg = 0
	self.cp.rowDirectionMode = courseGenerator.ROW_DIRECTION_AUTOMATIC
	self.cp.hasStartingDirection = false;
	self.cp.isNewCourseGenSelected = function()
		return self.cp.hasStartingCorner and self.cp.startingCorner > courseGenerator.STARTING_LOCATION_SE_LEGACY
	end
	self.cp.hasGeneratedCourse = false;
	self.cp.hasValidCourseGenerationData = false;
	-- TODO: add all old course gen settings to a SettingsContainer
	self.cp.oldCourseGeneratorSettings = {
		startingLocation = self.cp.startingCorner,
		manualStartingLocationWorldPos = nil,
		islandBypassMode = Island.BYPASS_MODE_NONE,
		nRowsToSkip = 0,
		centerMode = courseGenerator.CENTER_MODE_UP_DOWN
	}
	self.cp.headland = {
		-- with the old, manual direction selection course generator
		manuDirMaxNumLanes = 6;
		-- with the new, auto direction selection course generator
		autoDirMaxNumLanes = 50;
		maxNumLanes = 20;
		numLanes = 0;
		mode = courseGenerator.HEADLAND_MODE_NORMAL;
		userDirClockwise = true;
		orderBefore = true;
		-- we abuse the numLanes to switch to narrow field mode,
		-- negative headland lanes mean we are in narrow field mode
		-- TODO: this is an ugly hack to make life easy for the UI but needs
		-- to be refactored
		minNumLanes = -1;
		-- another ugly hack: the narrow mode is like the normal headland mode
		-- for most uses (like the turn system). The next two functions are
		-- to be used instead of the numLanes directly to hide the narrow mode
		getNumLanes = function()
			if self.cp.headland.mode == courseGenerator.HEADLAND_MODE_NARROW_FIELD then
				return math.abs( self.cp.headland.numLanes )
			else
				return self.cp.headland.numLanes
			end
		end;
		exists = function()
			return self.cp.headland.getNumLanes() > 0
		end;
		getMinNumLanes = function()
			return self.cp.isNewCourseGenSelected() and self.cp.headland.minNumLanes or 0
		end,
		getMaxNumLanes = function()
			return self.cp.isNewCourseGenSelected() and self.cp.headland.autoDirMaxNumLanes or self.cp.headland.manuDirMaxNumLanes
		end,
		turnType = courseplay.HEADLAND_CORNER_TYPE_SMOOTH;
		reverseManeuverType = courseplay.HEADLAND_REVERSE_MANEUVER_TYPE_STRAIGHT;

		tg = createTransformGroup('cpPointOrig_' .. tostring(self.rootNode));

		rectWidthRatio = 1.25;
		noGoWidthRatio = 0.975;
		minPointDistance = 0.5;
		maxPointDistance = 7.25;
		};
	link(getRootNode(), self.cp.headland.tg);
	if CpManager.isDeveloper then
	self.cp.headland.manuDirMaxNumLanes = 30;
	self.cp.headland.autoDirMaxNumLanes = 50;
	end;

	self.cp.fieldEdge = {
	selectedField = {
	fieldNum = 0;
	numPoints = 0;
	buttonsCreated = false;
	};
	customField = {
	points = nil;
	numPoints = 0;
	isCreated = false;
	show = false;
	fieldNum = 0;
	selectedFieldNumExists = false;
	};
	};

	self.cp.mouseCursorActive = false;

	-- 2D course
	self.cp.drawCourseMode = courseplay.COURSE_2D_DISPLAY_OFF;
	-- 2D pda map background -- TODO: MP?
	if g_currentMission.hud.ingameMap and g_currentMission.hud.ingameMap.mapOverlay and g_currentMission.hud.ingameMap.mapOverlay.filename then
		self.cp.course2dPdaMapOverlay = Overlay:new(g_currentMission.hud.ingameMap.mapOverlay.filename, 0, 0, 1, 1);
		self.cp.course2dPdaMapOverlay:setColor(1, 1, 1, CpManager.course2dPdaMapOpacity);
	end;

	-- HUD
	courseplay.hud:setupVehicleHud(self);

	courseplay:validateCanSwitchMode(self);

	---@type SettingsContainer
	self.cp.settings = SettingsContainer.createVehicleSpecificSettings(self)

	---@type SettingsContainer

	self.cp.courseGeneratorSettings = SettingsContainer.createCourseGeneratorSettings(self)

	courseplay.signs:updateWaypointSigns(self);
	
	courseplay:setAIDriver(self, self.cp.mode)
end;

function courseplay:onPostLoad(savegame)
	if savegame ~= nil and savegame.key ~= nil and not savegame.resetVehicles then
		courseplay.loadVehicleCPSettings(self, savegame.xmlFile, savegame.key, savegame.resetVehicles)
	end
end;

function courseplay:onLeaveVehicle()
	if self.cp.mouseCursorActive then
		courseplay:setMouseCursor(self, false);
    	courseEditor:reset()
	end
	---Update mouse action event texts
	CpManager:updateMouseInputText()
	--hide visual i3D waypoint signs when not in vehicle
	courseplay.signs:setSignsVisibility(self, true);
end

function courseplay:onEnterVehicle()
	--if the vehicle is attached to another vehicle, disable cp
	if not courseplay.isEnabled(self) then
		return 
	end 
	
	courseEditor:reset()
	if self.cp.mouseCursorActive then
		courseplay:setMouseCursor(self, true);
	end;
	---Update mouse action event texts
	CpManager:updateMouseInputText()
	--show visual i3D waypoint signs only when in vehicle
	courseplay.signs:setSignsVisibility(self);
end

function courseplay:onDraw()
	--if the vehicle is attached to another vehicle, disable cp
	if not courseplay.isEnabled(self) then
		return 
	end
	
	courseEditor:draw(self, self.cp.directionNode)

	courseplay:showAIMarkers(self)
	courseplay:showTemporaryMarkers(self)
	if self.cp.driver then 
		self.cp.driver.triggerHandler:onDraw()
	end
	local isDriving = self:getIsCourseplayDriving();

	--WORKWIDTH DISPLAY
	if self.cp.mode ~= 7 and self.cp.timers.showWorkWidth and self.cp.timers.showWorkWidth > 0 then
		if courseplay:timerIsThrough(self, 'showWorkWidth') then -- stop showing, reset timer
			courseplay:resetCustomTimer(self, 'showWorkWidth');
		else -- timer running, show
			courseplay:showWorkWidth(self);
		end;
	end;

	--DEBUG SHOW DIRECTIONNODE
	if courseplay.debugChannels[courseplay.DBG_PPC] then
		-- For debugging when setting the directionNodeZOffset. (Visual points shown for old node)
		if self.cp.oldDirectionNode then
			local ox,oy,oz = getWorldTranslation(self.cp.oldDirectionNode);
			cpDebug:drawPoint(ox, oy+4, oz, 0.9098, 0.6902 , 0.2706);
		end;
		if self.cp.driver then
			self.cp.driver:onDraw()
		end
		local nx,ny,nz = getWorldTranslation(self.cp.directionNode);
		cpDebug:drawPoint(nx, ny+4, nz, 0.6196, 0.3490 , 0);
	end;		
		
	if self:getIsActive() then
		if self.cp.hud.show then
			courseplay.hud:setContent(self);
			courseplay.hud:renderHud(self);
			courseplay.hud:renderHudBottomInfo(self);
			if self.cp.distanceCheck and (isDriving or (not self.cp.canDrive and not self.cp.isRecording and not self.cp.recordingIsPaused)) then -- turn off findFirstWaypoint when driving or no course loaded
				courseplay:toggleFindFirstWaypoint(self);
			end;

			if self.cp.mouseCursorActive then
				g_inputBinding:setShowMouseCursor(self.cp.mouseCursorActive);
			end;
		elseif courseplay.globalSettings.showMiniHud:is(true) then
			courseplay.hud:setContent(self);
			courseplay.hud:renderHudBottomInfo(self);
		end;
		
		if self.cp.distanceCheck and self.cp.numWaypoints > 1 then 
			courseplay:distanceCheck(self);
		elseif self.cp.infoText ~= nil and StringUtil.startsWith(self.cp.infoText, 'COURSEPLAY_DISTANCE') then  
			self.cp.infoText = nil
		end;
		
		if self:getIsEntered() and self.cp.toolTip ~= nil then
			courseplay:renderToolTip(self);
		end;
	end;


	--RENDER
	courseplay:renderInfoText(self);

	if self.cp.drawCourseMode == courseplay.COURSE_2D_DISPLAY_2DONLY or self.cp.drawCourseMode == courseplay.COURSE_2D_DISPLAY_BOTH then
		courseplay:drawCourse2D(self, false);
	end;
end; --END draw()

function courseplay:showWorkWidth(vehicle)
	local offsX, offsZ = vehicle.cp.settings.toolOffsetX:get() or 0, vehicle.cp.settings.toolOffsetZ:get() or 0;

	local left =  (vehicle.cp.workWidth *  0.5) + offsX;
	local right = (vehicle.cp.workWidth * -0.5) + offsX;

	-- TODO: refactor this, move showWorkWidth into the AIDriver?
	if vehicle.cp.directionNode and vehicle.cp.driver.getMarkers then
		local f, b = vehicle.cp.driver:getMarkers()
		local p1x, p1y, p1z = localToWorld(vehicle.cp.directionNode, left,  1.6, b - offsZ);
		local p2x, p2y, p2z = localToWorld(vehicle.cp.directionNode, right, 1.6, b - offsZ);
		local p3x, p3y, p3z = localToWorld(vehicle.cp.directionNode, right, 1.6, f - offsZ);
		local p4x, p4y, p4z = localToWorld(vehicle.cp.directionNode, left,  1.6, f - offsZ);

		cpDebug:drawPoint(p1x, p1y, p1z, 1, 1, 0);
		cpDebug:drawPoint(p2x, p2y, p2z, 1, 1, 0);
		cpDebug:drawPoint(p3x, p3y, p3z, 1, 1, 0);
		cpDebug:drawPoint(p4x, p4y, p4z, 1, 1, 0);

		cpDebug:drawLine(p1x, p1y, p1z, 1, 0, 0, p2x, p2y, p2z);
		cpDebug:drawLine(p2x, p2y, p2z, 1, 0, 0, p3x, p3y, p3z);
		cpDebug:drawLine(p3x, p3y, p3z, 1, 0, 0, p4x, p4y, p4z);
		cpDebug:drawLine(p4x, p4y, p4z, 1, 0, 0, p1x, p1y, p1z);
	else
		local lX, lY, lZ = localToWorld(vehicle.rootNode, left,  1.6, -6 - offsZ);
		local rX, rY, rZ = localToWorld(vehicle.rootNode, right, 1.6, -6 - offsZ);

		cpDebug:drawPoint(lX, lY, lZ, 1, 1, 0);
		cpDebug:drawPoint(rX, rY, rZ, 1, 1, 0);

		cpDebug:drawLine(lX, lY, lZ, 1, 0, 0, rX, rY, rZ);
	end;
end;

function courseplay:drawWaypointsLines(vehicle)
	if vehicle ~= g_currentMission.controlledVehicle then return; end;

	local height = 2.5;
	local r,g,b,a;
	for i,wp in pairs(vehicle.Waypoints) do
		if wp.cy == nil or wp.cy == 0 then
			wp.cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, wp.cx, 1, wp.cz);
		end;
		local np = vehicle.Waypoints[i+1];
		if np and (np.cy == nil or np.cy == 0) then
			np.cy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, np.cx, 1, np.cz);
		end;

		if i == 1 or wp.turnStart then
			r,g,b,a = 0, 1, 0, 1;
		elseif i == vehicle.cp.numWaypoints or wp.turnEnd then
			r,g,b,a = 1, 0, 0, 1;
		elseif i == vehicle.cp.waypointIndex then
			r,g,b,a = 0.9, 0, 0.6, 1;
		else
			r,g,b,a = 1, 1, 0, 1;
		end;
		cpDebug:drawPoint(wp.cx, wp.cy + height, wp.cz, r,g,b);

		if i < vehicle.cp.numWaypoints then
			if i + 1 == vehicle.cp.waypointIndex then
				--drawDebugLine(wp.cx, wp.cy + height, wp.cz, 0.9, 0, 0.6, np.cx, np.cy + height, np.cz, 1, 0.4, 0.05);
				cpDebug:drawLine(wp.cx, wp.cy + height, wp.cz, 0.9, 0, 0.6, np.cx, np.cy + height, np.cz);
			else
				cpDebug:drawLine(wp.cx, wp.cy + height, wp.cz, 0, 1, 1, np.cx, np.cy + height, np.cz);
			end;
		end;
	end;
end;

function courseplay:onUpdate(dt)	
	--if the vehicle is attached to another vehicle, disable cp
	if not courseplay.isEnabled(self) then
		return 
	end

	if self.cp.infoText ~= nil then
		self.cp.infoText = nil
	end

	if self.cp.postInitDone == nil then 
		if self.cp.driver then 
			---Post init function, as not all giants variables are
			---set correctly at the first courseplay:setAIDriver() call.
			self.cp.driver:postInit()
			self.cp.postInitDone = true
		end
	end


	if self.cp.drawCourseMode == courseplay.COURSE_2D_DISPLAY_DBGONLY or self.cp.drawCourseMode == courseplay.COURSE_2D_DISPLAY_BOTH then
		courseplay:drawWaypointsLines(self);
	end;

	-- we are in record mode
	if self.cp.isRecording then
		courseplay:record(self);
	end;

	-- we are in drive mode and single player /MP server
	if self.cp.isDriving and g_server ~= nil then
		for refIdx,_ in pairs(CpManager.globalInfoText.msgReference) do
			self.cp.hasSetGlobalInfoTextThisLoop[refIdx] = false;
		end;

		local status, err = xpcall(self.cp.driver.update, function(err) printCallstack(); return err end, self.cp.driver, dt)

		for refIdx,_ in pairs(self.cp.activeGlobalInfoTexts) do
			if not self.cp.hasSetGlobalInfoTextThisLoop[refIdx] then
				CpManager:setGlobalInfoText(self, refIdx, true); --force remove
			end;
		end;

		if not status then
			courseplay.infoVehicle(self, 'Exception, stopping Courseplay driver, %s', tostring(err))
			courseplay.onStopCpAIDriver(self,AIVehicle.STOP_REASON_UNKOWN)
			return
		end
	end
	 
	if self.cp.onSaveClick and not self.cp.doNotOnSaveClick then
		if courseplay.vehicleToSaveCourseIn == self then
			inputCourseNameDialogue:onSaveClick()
		end
		self.cp.onSaveClick = false
		self.cp.doNotOnSaveClick = false
	end
	if self.cp.onMpSetCourses then
		courseplay.courses:reloadVehicleCourses(self)
		self.cp.onMpSetCourses = nil
	end

	if self.cp.collidingVehicleId ~= nil and g_currentMission.nodeToObject[self.cp.collidingVehicleId] ~= nil and g_currentMission.nodeToObject[self.cp.collidingVehicleId].isCpPathvehicle then
		courseplay:setPathVehiclesSpeed(self,dt)
	end

	--reset selected field num, when field doesn't exist anymone (contracts)
	if courseplay.fields.fieldData[self.cp.fieldEdge.selectedField.fieldNum] == nil then
		self.cp.fieldEdge.selectedField.fieldNum = 0;
	end	
	
	-- this really should be only done in one place.
	self.cp.curSpeed = self.lastSpeedReal * 3600;
	
	--updateFunction for play testing workingToolPostions(manually)
	self.cp.settings.frontloaderToolPositions:updatePositions(dt)
	self.cp.settings.augerPipeToolPositions:updatePositions(dt)

end; --END update()

--[[
function courseplay:postUpdate(dt)
end;
]]

function courseplay:onUpdateTick(dt)
	--print("base:courseplay:updateTick(dt)")
	--if the vehicle is attached to another vehicle, disable cp
	if not courseplay.isEnabled(self) then
		return 
	end
	if not self.cp.fieldEdge.selectedField.buttonsCreated and courseplay.fields.numAvailableFields > 0 then
		courseplay:createFieldEdgeButtons(self);
	end;

	if self.cp.toolsDirty then
		courseplay:updateOnAttachOrDetach(self)
		self.cp.toolsDirty = nil
	end

	if self.cp.isDriving and g_server ~= nil then
		local status, err = xpcall(self.cp.driver.updateTick, function(err) printCallstack(); return err end, self.cp.driver, dt)
		if not status then
			courseplay.infoVehicle(self, 'Exception, stopping Courseplay driver, %s', tostring(err))
			courseplay.onStopCpAIDriver(self,AIVehicle.STOP_REASON_UNKOWN)
			return
		end
	end
	
	self.timer = self.timer + dt;
end

--[[
function courseplay:postUpdateTick(dt)
end;
]]

function courseplay:onPreDelete()
	---Delete map hotspot and all global info texts leftovers.
	CpMapHotSpot.deleteMapHotSpot(self)
	if g_server ~= nil then
		for refIdx,_ in pairs(CpManager.globalInfoText.msgReference) do
			if self.cp.activeGlobalInfoTexts[refIdx] ~= nil then
				CpManager:setGlobalInfoText(self, refIdx, true)
			end
		end
	end
end

function courseplay:onDelete()
	if self.cp.driver and self.cp.driver.collisionDetector then
		self.cp.driver.collisionDetector:deleteTriggers()
	end

	if self.cp ~= nil then
		if self.cp.headland and self.cp.headland.tg then
			unlink(self.cp.headland.tg);
			delete(self.cp.headland.tg);
			self.cp.headland.tg = nil;
		end;

		if self.cp.hud.bg ~= nil then
			self.cp.hud.bg:delete();
		end;
		if self.cp.hud.bgWithModeButtons ~= nil then
			self.cp.hud.bgWithModeButtons:delete();
		end;
		if self.cp.directionArrowOverlay ~= nil then
			self.cp.directionArrowOverlay:delete();
		end;
		if self.cp.buttons ~= nil then
			courseplay.buttons:deleteButtonOverlays(self);
		end;
		if self.cp.signs ~= nil then
			for _,section in pairs(self.cp.signs) do
				for k,signData in pairs(section) do
					courseplay.signs:deleteSign(signData.sign);
				end;
			end;
			self.cp.signs = nil;
		end;
		if self.cp.course2dPdaMapOverlay then
			self.cp.course2dPdaMapOverlay:delete();
		end;
		if self.cp.ppc then
			self.cp.ppc:delete()
		end
	end;
end;

function courseplay:setInfoText(vehicle, text)
	if not vehicle:getIsEntered() then
		return
	end
	if vehicle.cp.infoText ~= text and  text ~= nil and vehicle.cp.lastInfoText ~= text then
		vehicle.cp.infoText = text
		vehicle.cp.lastInfoText = text
	elseif vehicle.cp.infoText ~= text and  text ~= nil and vehicle.cp.lastInfoText == text then
		vehicle.cp.infoText = text
	end;
end;

function courseplay:renderInfoText(vehicle)
	if vehicle:getIsEntered()and vehicle.cp.infoText ~= nil and vehicle.cp.toolTip == nil then
		local text;
		local what = StringUtil.splitString(";", vehicle.cp.infoText);
		
		if what[1] == "COURSEPLAY_LOADING_AMOUNT"
		or what[1] == "COURSEPLAY_UNLOADING_AMOUNT"
		or what[1] == "COURSEPLAY_TURNING_TO_COORDS"
		or what[1] == "COURSEPLAY_DRIVE_TO_WAYPOINT" then
			if what[3] then	 
				text = string.format(courseplay:loc(what[1]), tonumber(what[2]), tonumber(what[3]));
			end		
		elseif what[1] == "COURSEPLAY_STARTING_UP_TOOL"
		or what[1] == "COURSEPLAY_WAITING_POINTS_TOO_FEW"
		or what[1] == "COURSEPLAY_WAITING_POINTS_TOO_MANY"
		or what[1] == "COURSEPLAY_UNLOADING_POINTS_TOO_FEW"
		or what[1] == "COURSEPLAY_UNLOADING_POINTS_TOO_MANY" then
			if what[2] then
				text = string.format(courseplay:loc(what[1]), what[2]);
			end
		elseif what[1] == "COURSEPLAY_WAITING_FOR_FILL_LEVEL" then
			if what[3] then
				text = string.format(courseplay:loc(what[1]), what[2], tonumber(what[3]));
			end
		elseif what[1] == "COURSEPLAY_DISTANCE" then
			if what[2] then
				local dist = tonumber(what[2]);
				if dist >= 1000 then
					text = ('%s: %.1f%s'):format(courseplay:loc('COURSEPLAY_DISTANCE'), dist * 0.001, courseplay:getMeasuringUnit());
				else
					text = ('%s: %d%s'):format(courseplay:loc('COURSEPLAY_DISTANCE'), dist, courseplay:loc('COURSEPLAY_UNIT_METER'));
				end;
			end
		else
			text = courseplay:loc(vehicle.cp.infoText)
		end;

		if text then
			courseplay:setFontSettings('white', false, 'left');
			renderText(courseplay.hud.infoTextPosX, courseplay.hud.infoTextPosY, courseplay.hud.fontSizes.infoText, text);
		end;
	end;
end;

function courseplay:setToolTip(vehicle, text)
	if vehicle.cp.toolTip ~= text then
		vehicle.cp.toolTip = text;
	end;
end;

function courseplay:renderToolTip(vehicle)
	courseplay:setFontSettings('white', false, 'left');
	renderText(courseplay.hud.toolTipTextPosX, courseplay.hud.toolTipTextPosY, courseplay.hud.fontSizes.infoText, vehicle.cp.toolTip);
	vehicle.cp.hud.toolTipIcon:render();
end;

function courseplay:setVehicleWaypoints(vehicle, waypoints)
	vehicle.Waypoints = waypoints
	vehicle.cp.numWaypoints = #waypoints
	courseplay.signs:updateWaypointSigns(vehicle, "current");
	if vehicle.cp.numWaypoints > 3 then
		vehicle.cp.canDrive = true
	end
end;

function courseplay:onReadStream(streamId, connection)
	courseplay:debug("id: "..tostring(self.id).."  base: readStream", courseplay.DBG_MULTIPLAYER)
		
	for _,variable in ipairs(courseplay.multiplayerSyncTable)do
		local value = courseplay.streamDebugRead(streamId, variable.dataFormat)
		if variable.dataFormat == 'String' and value == 'nil' then
			value = nil
		end
		courseplay:setVarValueFromString(self, variable.name, value)
	end
	courseplay:debug("id: "..tostring(NetworkUtil.getObjectId(self)).."  base: read courseplay.multiplayerSyncTable end", courseplay.DBG_MULTIPLAYER)
-------------------
	-- SettingsContainer:
	self.cp.settings:onReadStream(streamId)
	-- courseGeneratorSettingsContainer:
	self.cp.courseGeneratorSettings:onReadStream(streamId)
-------------------	
	local savedFieldNum = streamDebugReadInt32(streamId)
	if savedFieldNum > 0 then
		self.cp.generationPosition.fieldNum = savedFieldNum
	end
		
	local copyCourseFromDriverId = streamDebugReadInt32(streamId)
	if copyCourseFromDriverId then
		self.cp.copyCourseFromDriver = NetworkUtil.getObject(copyCourseFromDriverId) 
	end

	courseplay.courses:reinitializeCourses()


	-- kurs daten
	local courses = streamDebugReadString(streamId) -- 60.
	if courses ~= nil then
		self.cp.loadedCourses = StringUtil.splitString(",", courses);
		courseplay:reloadCourses(self, true)
	end
	
	self.cp.numCourses = streamDebugReadInt32(streamId)
	
	--print(string.format("%s:read: numCourses: %s loadedCourses: %s",tostring(self.name),tostring(self.cp.numCourses),tostring(#self.cp.loadedCourses)))
	if self.cp.numCourses > #self.cp.loadedCourses then
		self.Waypoints = {}
		local wp_count = streamDebugReadInt32(streamId)
		for w = 1, wp_count do
			table.insert(self.Waypoints, CourseEvent:readWaypoint(streamId))
		end
		self.cp.numWaypoints = #self.Waypoints
		
		if self.cp.numCourses > 1 then
			self.cp.currentCourseName = string.format("%d %s", self.cp.numCourses, courseplay:loc('COURSEPLAY_COMBINED_COURSES'));
		end
	end
	-- SETUP 2D COURSE DRAW DATA
	self.cp.course2dUpdateDrawData = true;
	
	local debugChannelsString = streamDebugReadString(streamId)
	for k,v in pairs(StringUtil.splitString(",", debugChannelsString)) do
		courseplay:toggleDebugChannel(self, k, v == 'true');
	end;
		
	if streamReadBool(streamId) then 
		self.cp.timeRemaining = streamReadFloat32(streamId)
	end		
	
	if streamReadBool(streamId) then 
		self.cp.infoText = streamReadString(streamId)
	end

	--Make sure every vehicle has same AIDriver as the Server
	courseplay:setAIDriver(self, self.cp.mode)


	self.cp.driver:onReadStream(streamId)
	
	courseplay:debug("id: "..tostring(self.id).."  base: readStream end", courseplay.DBG_MULTIPLAYER)
end

function courseplay:onWriteStream(streamId, connection)
	courseplay:debug("id: "..tostring(self).."  base: write stream", courseplay.DBG_MULTIPLAYER)
		
	for _,variable in ipairs(courseplay.multiplayerSyncTable)do
		courseplay.streamDebugWrite(streamId, variable.dataFormat, courseplay:getVarValueFromString(self,variable.name),variable.name)
	end
	courseplay:debug("id: "..tostring(self).."  base: write courseplay.multiplayerSyncTable end", courseplay.DBG_MULTIPLAYER)
-------------------
	-- SettingsContainer:
	self.cp.settings:onWriteStream(streamId)
	-- courseGeneratorSettingsContainer:
	self.cp.courseGeneratorSettings:onWriteStream(streamId)
-------------
	streamDebugWriteInt32(streamId, self.cp.generationPosition.fieldNum)
	
	local copyCourseFromDriverID;
	if self.cp.copyCourseFromDriver ~= nil then
		copyCourseFromDriverID = NetworkUtil.getObjectId(self.cp.copyCourseFromDriver)
	end
	streamDebugWriteInt32(streamId, copyCourseFromDriverID)
	
	local loadedCourses;
	if #self.cp.loadedCourses then
		loadedCourses = table.concat(self.cp.loadedCourses, ",")
	end
	streamDebugWriteString(streamId, loadedCourses) -- 60.
	streamDebugWriteInt32(streamId, self.cp.numCourses)
	
	--print(string.format("%s:write: numCourses: %s loadedCourses: %s",tostring(self.name),tostring(self.cp.numCourses),tostring(#self.cp.loadedCourses)))
	if self.cp.numCourses > #self.cp.loadedCourses then
		courseplay:debug("id: "..tostring(NetworkUtil.getObjectId(self)).."  sync temp course", courseplay.DBG_MULTIPLAYER)
		streamDebugWriteInt32(streamId, #(self.Waypoints))
		for w = 1, #(self.Waypoints) do
			--print("writing point "..tostring(w))
			CourseEvent:writeWaypoint(streamId, self.Waypoints[w])
		end
	end

	local debugChannelsString = table.concat(table.map(courseplay.debugChannels, tostring), ",");
	streamDebugWriteString(streamId, debugChannelsString) 
		
	if self.cp.timeRemaining then 
		streamWriteBool(streamId,true)
		streamWriteFloat32(streamId,self.cp.timeRemaining)
	else 
		streamWriteBool(streamId,false)
	end
	
	if self.cp.infoText then 
		streamWriteBool(streamId,true)
		streamWriteString(streamId,self.cp.infoText)
	else 
		streamWriteBool(streamId,false)
	end

	self.cp.driver:onWriteStream(streamId)
	
	courseplay:debug("id: "..tostring(NetworkUtil.getObjectId(self)).."  base: write stream end", courseplay.DBG_MULTIPLAYER)
end

--TODO figure out how dirtyFlags work ??

function courseplay:onReadUpdateStream(streamId, timestamp, connection)
	 if connection:getIsServer() then
		if self.cp.driver ~= nil then 
			self.cp.driver:readUpdateStream(streamId, timestamp, connection)
		end 
		--only sync while cp is drivin!
		if streamReadBool(streamId) then
			if streamReadBool(streamId) then 
				self.cp.waypointIndex = streamReadInt32(streamId)
			else 
				self.cp.waypointIndex = 0
			end
			if streamReadBool(streamId) then -- is infoText~=nil ?
				if streamReadBool(streamId) then -- has infoText changed
					self.cp.infoText = streamReadString(streamId)
				end
			else 
				self.cp.infoText = nil
			end
			if streamReadBool(streamId) then -- is currentCourseName~=nil ?
				if streamReadBool(streamId) then -- has currentCourseName changed
					self.cp.currentCourseName = streamReadString(streamId)
				end
			else 
				self.cp.currentCourseName = nil
			end
			if streamReadBool(streamId) then -- is timeRemaining~=nil ?
				if streamReadBool(streamId) then -- has timeRemaining changed
					self.cp.timeRemaining = streamReadFloat32(streamId)
				end
			else 
				self.cp.timeRemaining = nil
			end
			--gitAdditionalText ?
		end 
	end
end

function courseplay:onWriteUpdateStream(streamId, connection, dirtyMask)
	 if not connection:getIsServer() then
		if self.cp.driver ~= nil then 
			self.cp.driver:writeUpdateStream(streamId, connection, dirtyMask)
		end 
		if streamWriteBool(streamId, self:getIsCourseplayDriving() or false) then
			if self.cp.waypointIndex then
				streamWriteBool(streamId,true)
				streamWriteInt32(streamId,self.cp.waypointIndex)
			else 
				streamWriteBool(streamId,false)
			end
			if self.cp.infoText then --is infoText~=nil ?
				streamWriteBool(streamId,true)
				if self.cp.infoText~=self.cp.infoTextSend then -- has infoText changed
					streamWriteBool(streamId,true)
					streamWriteString(streamId,self.cp.infoText)
					self.cp.infoTextSend = self.cp.infoText
				else 
					streamWriteBool(streamId,false)
				end
			else 
				streamWriteBool(streamId,false)
			end
			if self.cp.currentCourseName then -- is currentCourseName~=nil ?
				streamWriteBool(streamId,true)
				if self.cp.currentCourseName~=self.cp.currentCourseNameSend then -- has currentCourseName changed
					streamWriteBool(streamId,true)
					streamWriteString(streamId,self.cp.currentCourseName)
					self.cp.currentCourseNameSend = self.cp.currentCourseName
				else 
					streamWriteBool(streamId,false)
				end
			else 
				streamWriteBool(streamId,false)
			end
			if self.cp.timeRemaining then -- is timeRemaining~=nil ?
				streamWriteBool(streamId,true)
				if self.cp.timeRemaining~=self.cp.timeRemainingSend then -- has timeRemaining changed
					streamWriteBool(streamId,true)
					streamWriteFloat32(streamId,self.cp.timeRemaining)
					self.cp.timeRemainingSend = self.cp.timeRemaining
				else 
					streamWriteBool(streamId,false)
				end
			else 
				streamWriteBool(streamId,false)
			end
			--gitAdditionalText ?
		end 
	end
end

function courseplay:loadVehicleCPSettings(xmlFile, key, resetVehicles)
	
	if not resetVehicles and g_server ~= nil then
		-- COURSEPLAY
		local curKey = key .. '.courseplay.basics';
		courseplay:setCpMode(self,  Utils.getNoNil(getXMLInt(xmlFile, curKey .. '#aiMode'), self.cp.mode), true);
		self.cp.waitTime 		  = Utils.getNoNil(getXMLInt(xmlFile, curKey .. '#waitTime'), 0);
		local courses 			  = Utils.getNoNil(getXMLString(xmlFile, curKey .. '#courses'), '');
		self.cp.loadedCourses = StringUtil.splitString(",", courses);
		courseplay:reloadCourses(self, true);

		--HUD
		curKey = key .. '.courseplay.HUD';
		self.cp.hud.show = Utils.getNoNil(  getXMLBool(xmlFile, curKey .. '#showHud'), false);
		
		-- MODE 2
		curKey = key .. '.courseplay.combi';
		self.cp.tipperOffset 		  = Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#tipperOffset'),			 0);
		self.cp.combineOffset 		  = Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#combineOffset'),		 0);
		self.cp.combineOffsetAutoMode = Utils.getNoNil( getXMLBool(xmlFile, curKey .. '#combineOffsetAutoMode'), true);
		
		curKey = key .. '.courseplay.driving';
		self.cp.turnDiameter		  = Utils.getNoNil(  getXMLInt(xmlFile, curKey .. '#turnDiameter'),			 self.cp.vehicleTurnRadius * 2);
		self.cp.turnDiameterAutoMode  = Utils.getNoNil( getXMLBool(xmlFile, curKey .. '#turnDiameterAutoMode'),	 true);
		self.cp.alignment.enabled 	  = Utils.getNoNil( getXMLBool(xmlFile, curKey .. '#alignment'),	 		 true);
	
	
		-- MODES 4 / 6
		curKey = key .. '.courseplay.fieldWork';
		self.cp.workWidth 							= Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#workWidth'),				3);
		self.cp.abortWork							= Utils.getNoNil(  getXMLInt(xmlFile, curKey .. '#abortWork'),				0);
		self.cp.manualWorkWidth						= Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#manualWorkWidth'),		0);
		self.cp.lastValidTipDistance				= Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#lastValidTipDistance'),	0);
		self.cp.generationPosition.hasSavedPosition	= Utils.getNoNil( getXMLBool(xmlFile, curKey .. '#hasSavedPosition'),		false);
		self.cp.generationPosition.x				= Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#savedPositionX'),			0);
		self.cp.generationPosition.z				= Utils.getNoNil(getXMLFloat(xmlFile, curKey .. '#savedPositionZ'),			0);
		self.cp.generationPosition.fieldNum 		= Utils.getNoNil(  getXMLInt(xmlFile, curKey .. '#savedFieldNum'),			0);
		if self.cp.abortWork == 0 then
			self.cp.abortWork = nil;
		end;
		if self.cp.manualWorkWidth ~= 0 then
			self.cp.workWidth = self.cp.manualWorkWidth
		else
			self.cp.manualWorkWidth = nil
		end;	
		if self.cp.lastValidTipDistance == 0 then
			self.cp.lastValidTipDistance = nil;
		end;
		
		local offsetData = Utils.getNoNil(getXMLString(xmlFile, curKey .. '#offsetData'), '0;0;0;false;0;0;0'); -- 1=laneOffset, 2=toolOffsetX, 3=toolOffsetZ, 4=symmetricalLaneChange
		offsetData = StringUtil.splitString(';', offsetData);
		courseplay:changeLaneOffset(self, nil, tonumber(offsetData[1]));

		if not offsetData[5] then offsetData[5] = 0; end;
		courseplay:changeLoadUnloadOffsetX(self, nil, tonumber(offsetData[5]));
		if not offsetData[6] then offsetData[6] = 0; end;
		courseplay:changeLoadUnloadOffsetZ(self, nil, tonumber(offsetData[6]));
		if offsetData[7] ~= nil then self.cp.laneNumber = tonumber(offsetData[7]) end;

		
		self.cp.settings:loadFromXML(xmlFile, key .. '.courseplay')

		courseplay:validateCanSwitchMode(self);
	end;
	return BaseMission.VEHICLE_LOAD_OK;
end


function courseplay:saveToXMLFile(xmlFile, key, usedModNames)
	if not self.hasCourseplaySpec then
		courseplay.infoVehicle(self, 'has no Courseplay installed, not adding Courseplay data to savegame.')
		return
	end

	--cut the key to configure it for our needs 
	local keySplit = StringUtil.splitString(".", key);
	local newKey = keySplit[1]
	for i=2,#keySplit-2 do
		newKey = newKey..'.'..keySplit[i]
	end
	newKey = newKey..'.courseplay'

	
	--CP basics
	setXMLInt(xmlFile, newKey..".basics #aiMode", self.cp.mode)
	if #self.cp.loadedCourses == 0 and self.cp.currentCourseId ~= 0 then
		-- this is the case when a course has been generated and than saved, it is not in loadedCourses (should probably
		-- fix it there), so make sure it is in the savegame
		setXMLString(xmlFile, newKey..".basics #courses", tostring(self.cp.currentCourseId))
	else
		setXMLString(xmlFile, newKey..".basics #courses", tostring(table.concat(self.cp.loadedCourses, ",")))
	end
	setXMLInt(xmlFile, newKey..".basics #waitTime", self.cp.waitTime)

	--HUD
	setXMLBool(xmlFile, newKey..".HUD #showHud", self.cp.hud.show)
	

	
	--combineMode
	setXMLString(xmlFile, newKey..".combi #tipperOffset", string.format("%.1f",self.cp.tipperOffset))
	setXMLString(xmlFile, newKey..".combi #combineOffset", string.format("%.1f",self.cp.combineOffset))
	setXMLString(xmlFile, newKey..".combi #combineOffsetAutoMode", tostring(self.cp.combineOffsetAutoMode))
	
	--driving settings
	setXMLInt(xmlFile, newKey..".driving #turnDiameter", self.cp.turnDiameter)
	setXMLBool(xmlFile, newKey..".driving #turnDiameterAutoMode", self.cp.turnDiameterAutoMode)
	setXMLString(xmlFile, newKey..".driving #alignment", tostring(self.cp.alignment.enabled))
	
	--field work settings
	local offsetData = string.format('%.1f;%.1f;%.1f;%s;%.1f;%.1f;%d', self.cp.laneOffset, 0, 0, 0, self.cp.loadUnloadOffsetX, self.cp.loadUnloadOffsetZ, self.cp.laneNumber);
	setXMLString(xmlFile, newKey..".fieldWork #workWidth", string.format("%.1f",self.cp.workWidth))
	setXMLString(xmlFile, newKey..".fieldWork #offsetData", offsetData)
	setXMLInt(xmlFile, newKey..".fieldWork #abortWork", Utils.getNoNil(self.cp.abortWork, 0))
	setXMLString(xmlFile, newKey..".fieldWork #manualWorkWidth", string.format("%.1f",Utils.getNoNil(self.cp.manualWorkWidth,0)))
	setXMLString(xmlFile, newKey..".fieldWork #lastValidTipDistance", string.format("%.1f",Utils.getNoNil(self.cp.lastValidTipDistance,0)))
	setXMLBool(xmlFile, newKey..".fieldWork #hasSavedPosition", self.cp.generationPosition.hasSavedPosition)
	setXMLString(xmlFile, newKey..".fieldWork #savedPositionX", string.format("%.1f",Utils.getNoNil(self.cp.generationPosition.x,0)))
	setXMLString(xmlFile, newKey..".fieldWork #savedPositionZ", string.format("%.1f",Utils.getNoNil(self.cp.generationPosition.z,0)))
	setXMLString(xmlFile, newKey..".fieldWork #savedFieldNum", string.format("%.1f",Utils.getNoNil(self.cp.generationPosition.fieldNum,0)))

	
	self.cp.settings:saveToXML(xmlFile, newKey)

end

---Is this one still used as cp.isTurning isn't getting set to true ??

-- This is to prevent the selfPropelledPotatoHarvester from turning off while turning
function courseplay.setIsTurnedOn(self, originalFunction, isTurnedOn, noEventSend)
	if self.typeName and self.typeName == "selfPropelledPotatoHarvester" then
		if self.getIsCourseplayDriving and self:getIsCourseplayDriving() and self.cp.isTurning and not isTurnedOn then
			isTurnedOn = true;
		end;
	end;

	originalFunction(self, isTurnedOn, noEventSend);
end;
TurnOnVehicle.setIsTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.setIsTurnedOn, courseplay.setIsTurnedOn);

-- Workaround: onEndWorkAreaProcessing seems to cause Cutter to call stopAIVehicle when
-- driving on an already worked field, or a field where the fruit type is different than the one being processed.
-- This changes that behavior.
function courseplay:getAllowCutterAIFruitRequirements(superFunc)
	return superFunc(self) and not self:getIsCourseplayDriving()
end
Cutter.getAllowCutterAIFruitRequirements = Utils.overwrittenFunction(Cutter.getAllowCutterAIFruitRequirements, courseplay.getAllowCutterAIFruitRequirements)

-- Workaround: onEndWorkAreaProcessing seems to cause Cutter to call stopAIVehicle when
-- driving on an already worked field. This will suppress that call as long as Courseplay is driving
function courseplay:stopAIVehicle(superFunc, reason, noEventSend)
	if superFunc ~= nil and not self:getIsCourseplayDriving() then
		superFunc(self, reason, noEventSend)
	end
end
AIVehicle.stopAIVehicle = Utils.overwrittenFunction(AIVehicle.stopAIVehicle, courseplay.stopAIVehicle)


function courseplay:onSetBrokenAIVehicle(superFunc)
	if self:getIsCourseplayDriving() then
		if g_server ~= nil then 
			courseplay.onStopCpAIDriver(self,AIVehicle.STOP_REASON_UNKOWN)
		end
	else 
		superFunc(self)
	end
end
AIVehicle.onSetBroken = Utils.overwrittenFunction(AIVehicle.onSetBroken, courseplay.onSetBrokenAIVehicle)

---These two AIVehicle function are overwritten for multiplayer compatibility, 
---a better way would probably be to overwrite AIVehicle:startAIVehicle() 
---and AIVehicle:stopAIVehicle(). For MP they could then be overloaded with
---a boolean to make sure we set a CP driver and not a giants helper or we would need to make sure 
---courseplay:getIsCourseplayDriving() is set on the client before any other calls.
function courseplay:onWriteStreamAIVehicle(superFunc,streamId, connection)
	if self:getIsCourseplayDriving() then 
		streamWriteBool(streamId,true)
		local spec = self.spec_aiVehicle
		streamWriteUInt8(streamId, spec.currentHelper.index)
		streamWriteUIntN(streamId, spec.startedFarmId, FarmManager.FARM_ID_SEND_NUM_BITS)
	else 
		streamWriteBool(streamId,false)
		superFunc(self,streamId, connection)
	end
end
AIVehicle.onWriteStream = Utils.overwrittenFunction(AIVehicle.onWriteStream, courseplay.onWriteStreamAIVehicle)

function courseplay:onReadStreamAIVehicle(superFunc,streamId, connection)
	if streamReadBool(streamId) then
		local helperIndex = streamReadUInt8(streamId)
		local farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
		courseplay.onStartCpAIDriver(self,helperIndex, true, farmId)
	else 
		superFunc(self,streamId, connection)
	end
end
AIVehicle.onReadStream = Utils.overwrittenFunction(AIVehicle.onReadStream, courseplay.onReadStreamAIVehicle)

---Disables fertilizing while sowing, if SowingMachineFertilizerEnabledSetting is false.
function courseplay.processSowingMachineArea(tool,originalFunction, superFunc, workArea, dt)
	local rootVehicle = tool:getRootVehicle()
	if courseplay:isAIDriverActive(rootVehicle) then
		if rootVehicle.cp.settings.sowingMachineFertilizerEnabled:is(false) then
			tool.spec_sprayer.workAreaParameters.sprayFillLevel = 0
		end
	end
	return originalFunction(tool, superFunc, workArea, dt)
end
FertilizingSowingMachine.processSowingMachineArea = Utils.overwrittenFunction(FertilizingSowingMachine.processSowingMachineArea, courseplay.processSowingMachineArea)


-- Tour dialog messes up the CP yes no dialogs.
function courseplay:showTourDialog()
	print('Tour dialog is disabled by Courseplay.')
end
TourIcons.showTourDialog = Utils.overwrittenFunction(TourIcons.showTourDialog, courseplay.showTourDialog)

-- TODO: make these part of AIDriver

function courseplay:setWaypointIndex(vehicle, number,isRecording)
	if vehicle.cp.waypointIndex ~= number then
		vehicle.cp.course.hasChangedTheWaypointIndex = true
		if isRecording then
			vehicle.cp.waypointIndex = number
		else
			vehicle.cp.waypointIndex = number
		end
		if vehicle.cp.waypointIndex > 1 then
			vehicle.cp.previousWaypointIndex = vehicle.cp.waypointIndex - 1;
		else
			vehicle.cp.previousWaypointIndex = 1;
		end;
	end;
end;

function courseplay:getIsCourseplayDriving()
	return self.cp.isDriving
end;

function courseplay:setIsCourseplayDriving(active)
	self.cp.isDriving = active
end;

--- Explicit interface function for other mods (like AutoDrive) to start the Courseplay driver (by vehicle:startCpDriver())
function courseplay:startCpDriver()
	courseplay.onStartCpAIDriver(self, nil, false, g_currentMission.player.farmId)
end

--- Explicit interface function for other mods (like AutoDrive) to stop the Courseplay driver (by vehicle:stopCpDriver())
function courseplay:stopCpDriver()
	courseplay.onStopCpAIDriver(self, AIVehicle.STOP_REASON_REGULAR)
end

--the same code as giants AIVehicle:startAIVehicle(helperIndex, noEventSend, startedFarmId), but customized for cp

--All the code that has to be run on Server and Client from the "start_stop" file has to get in here
function courseplay.onStartCpAIDriver(vehicle,helperIndex,noEventSend, startedFarmId)
	local spec = vehicle.spec_aiVehicle
    if not vehicle:getIsCourseplayDriving() then
        --giants code from AIVehicle:startAIVehicle()
		courseplay.debugVehicle(courseplay.DBG_AI_DRIVER,vehicle,'Started cp driver, farmID: %s, helperIndex: %s', tostring(startedFarmId),tostring(helperIndex))
		if helperIndex ~= nil then
            spec.currentHelper = g_helperManager:getHelperByIndex(helperIndex)
        else
            spec.currentHelper = g_helperManager:getRandomHelper()
        end
        g_helperManager:useHelper(spec.currentHelper)
		---Make sure the farmId is never: 0 == spectator farm id,
		---which could be the case when autodrive starts a CP driver.
		if startedFarmId ~= 0 then 
			spec.startedFarmId = startedFarmId
		end
		if g_server ~= nil then
            g_farmManager:updateFarmStats(startedFarmId, "workersHired", 1)
        end
        if noEventSend == nil or noEventSend == false then
            local event = AIVehicleSetStartedEventCP:new(vehicle, nil, true, spec.currentHelper, startedFarmId)
            if g_server ~= nil then
                g_server:broadcastEvent(event, nil, nil, vehicle)
            else
                g_client:getServerConnection():sendEvent(event)
            end
        end
        AIVehicle.numHirablesHired = AIVehicle.numHirablesHired + 1
        AIVehicle.hiredHirables[vehicle] = vehicle
        if vehicle.setRandomVehicleCharacter ~= nil then
            vehicle:setRandomVehicleCharacter()
        end
		local mapHotSpotText = courseplay.globalSettings.showMapHotspot:getMapHotspotText(vehicle)
		spec.mapAIHotspot = CpMapHotSpot.createMapHotSpot(vehicle,mapHotSpotText)
        g_currentMission:addMapHotspot(spec.mapAIHotspot)
        spec.isActive = true
        if g_server ~= nil then
            vehicle:updateAIImplementData()
        end
        if vehicle:getAINeedsTrafficCollisionBox() then
            local collisionRoot = g_i3DManager:loadSharedI3DFile(AIVehicle.TRAFFIC_COLLISION_BOX_FILENAME, g_currentMission.baseDirectory, false, true, false)
            if collisionRoot ~= nil and collisionRoot ~= 0 then
                local collision = getChildAt(collisionRoot, 0)
                link(getRootNode(), collision)
                spec.aiTrafficCollision = collision
                delete(collisionRoot)
            end
        end

		--cp code

		if vehicle.cp.coursePlayerNum == nil then
			vehicle.cp.coursePlayerNum = CpManager:addToTotalCoursePlayers(vehicle)
		end;
		
		--add to activeCoursePlayers
		CpManager:addToActiveCoursePlayers(vehicle)
		

		vehicle:setIsCourseplayDriving(true)
		vehicle.cp.distanceCheck = false

		courseplay:setIsRecording(vehicle, false);
		courseplay:setRecordingIsPaused(vehicle, false);
		if g_server then 
			courseplay:start(vehicle)
		end
		---Making sure the client hud gets correctly updated.
		vehicle.cp.driver:refreshHUD()
    end
end

--the same code as giants AIVehicle:stopAIVehicle(helperIndex, noEventSend, startedFarmId), but customized for cp

--All the code that has to be run on Server and Client from the "start_stop" file has to get in here
function courseplay.onStopCpAIDriver(vehicle, reason, noEventSend)
	local spec = vehicle.spec_aiVehicle
    if vehicle:getIsCourseplayDriving() then
        --giants code from AIVehicle:stopAIVehicle()
		courseplay.debugVehicle(courseplay.DBG_AI_DRIVER,vehicle,'Stopped cp driver')
		if noEventSend == nil or noEventSend == false then
            local event = AIVehicleSetStartedEventCP:new(vehicle, reason, false, nil, spec.startedFarmId)
            if g_server ~= nil then
                g_server:broadcastEvent(event, nil, nil, vehicle)
            else
                g_client:getServerConnection():sendEvent(event)
            end
        end
        g_helperManager:releaseHelper(spec.currentHelper)
        spec.currentHelper = nil
        if g_server ~= nil then
            g_farmManager:updateFarmStats(spec.startedFarmId, "workersHired", -1)
        end
        AIVehicle.numHirablesHired = math.max(AIVehicle.numHirablesHired - 1, 0)
        AIVehicle.hiredHirables[vehicle] = nil
        if vehicle.restoreVehicleCharacter ~= nil then
            vehicle:restoreVehicleCharacter()
        end

        CpMapHotSpot.deleteMapHotSpot(vehicle)

        vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF, true)
        if g_server ~= nil then
            WheelsUtil.updateWheelsPhysics(vehicle, 0, spec.lastSpeedReal*spec.movingDirection, 0, true, true)
        end
        spec.isActive = false
        spec.isTurning = false
        -- move the collision far under the ground
        if vehicle:getAINeedsTrafficCollisionBox() then
            setTranslation(spec.aiTrafficCollision, 0, -1000, 0)
        end
        if vehicle.brake ~= nil then
            vehicle:brake(1)
        end
		vehicle:requestActionEventUpdate()
		
		--cp code

		--remove any global info texts
		if g_server ~= nil then
			for refIdx,_ in pairs(CpManager.globalInfoText.msgReference) do
				if vehicle.cp.activeGlobalInfoTexts[refIdx] ~= nil then
					CpManager:setGlobalInfoText(vehicle, refIdx, true);
				end;
			end;
		end

		--remove from activeCoursePlayers
		CpManager:removeFromActiveCoursePlayers(vehicle);
		
		vehicle:setIsCourseplayDriving(false)

		vehicle.cp.distanceCheck = false 
		vehicle.cp.canDrive = true
		vehicle.cp.infoText = nil
		vehicle.cp.lastInfoText = nil
		courseplay:setIsRecording(vehicle, false);
		courseplay:setRecordingIsPaused(vehicle, false);
		if g_server then 
			courseplay:stop(vehicle)
		end
		---Making sure the client hud gets correctly updated.
		vehicle.cp.driver:refreshHUD()
    end
end

---vehicle is not attached to another one and vehicle has CourseplaySpec 
function courseplay.isEnabled(vehicle)
	local vehicle = vehicle
	return vehicle and vehicle.hasCourseplaySpec and not (vehicle.spec_attachable and vehicle.spec_attachable.attacherVehicle)
end

CpMapHotSpot = {}
---Creates a mapHotSpot, for reference AIVehicle:startAIVehicle(helperIndex, noEventSend, startedFarmId)
function CpMapHotSpot.createMapHotSpot(vehicle,text)
	---Gets the mode button uvs
	local rawUvs = courseplay.hud:getModeUvs() 
	local uvsSize = courseplay.hud:getIconSpriteSize()
	local imagePath = courseplay.hud:getIconSpritePath()
	local uvs = courseplay.utils:getUvs(rawUvs[vehicle.cp.mode], uvsSize.x,uvsSize.y)

	local hotspotX, _, hotspotZ = getWorldTranslation(vehicle.rootNode)
	local _, textSize = getNormalizedScreenValues(0, 9)
	local _, textOffsetY = getNormalizedScreenValues(0, 5)
	local width, height = getNormalizedScreenValues(18, 18)
	local color = courseplay.utils:rgbToNormal(255, 113,  16, 1) --orange

	local mapAIHotspot = MapHotspot:new("cpHelper", MapHotspot.CATEGORY_AI)
	mapAIHotspot:setSize(width, height)
	mapAIHotspot:setLinkedNode(vehicle.components[1].node)
	mapAIHotspot:setText(text)
	mapAIHotspot:setImage(imagePath, uvs,color)
	mapAIHotspot:setBackgroundImage()
	mapAIHotspot:setTextOptions(textSize, nil, textOffsetY, {1, 1, 1, 1}, Overlay.ALIGN_VERTICAL_MIDDLE)
	mapAIHotspot:setHasDetails(false)
	return mapAIHotspot
end

function CpMapHotSpot.deleteMapHotSpot(vehicle)
	local spec = vehicle.spec_aiVehicle
	if spec and spec.mapAIHotspot ~= nil then		
		g_currentMission:removeMapHotspot(spec.mapAIHotspot)
		spec.mapAIHotspot:delete()
		spec.mapAIHotspot = nil
	end
end


-- do not remove this comment
-- vim: set noexpandtab:
