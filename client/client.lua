DRIVING_VEHICLE, VEHICLE_INSIDE = nil, nil

local _fueling = false
local _lowtick = 0
local _engineShutoff = false

local pumpModels = {
	`prop_gas_pump_1a`,
	`prop_gas_pump_1b`,
	`prop_gas_pump_1c`,
	`prop_gas_pump_1d`,
	`prop_vintage_pump`,
	`prop_gas_pump_old2`,
	`prop_gas_pump_old3`,
	486135101, -- LTD Grove Gabz
}

CreateThread(function()
	CreateFuelStationPolyzones()

	for k, v in ipairs(pumpModels) do
		plsr.Targeting:AddObject(v, "gas-pump", {
				{
					text = "Refill Petrol Can",
					icon = "gas-pump",
					textFunc = function()
						local current = GetAmmoInPedWeapon(PlayerPedId(), `WEAPON_PETROLCAN`)
						local pct = current / 4500
						return string.format(
							"Refill Petrol Can ($%s)",
							math.ceil(CalculateFuelCost(0, math.floor(100 - (pct * 100))))
						)
					end,
					event = "Fuel:Client:FillCan",
					minDist = 3.0,
					isEnabled = function()
						local isArmed, hash = GetCurrentPedWeapon(PlayerPedId())
						local current = GetAmmoInPedWeapon(PlayerPedId(), `WEAPON_PETROLCAN`)
						local pct = current / 4500
						local cCost = CalculateFuelCost(0, math.floor(100 - (pct * 100)))
						if cCost then
							local cost = math.ceil(cCost)
							return (
								isArmed
								and hash == `WEAPON_PETROLCAN`
								and GetAmmoInPedWeapon(PlayerPedId(), `WEAPON_PETROLCAN`) < 4500
								and plsr.State.character.Cash >= cost
							)
						end
					end,
				},
			}, 3.0)
	end
end)

function CreateFuelStationPolyzones()
	for k, v in ipairs(Config.FuelStations) do
		plsr.Polyzone.Create:Box("fuel_" .. k, v.center, v.length, v.width, {
			heading = v.heading,
			minZ = v.minZ,
			maxZ = v.maxZ,
		}, {
			fuel = true,
			restricted = v.restricted,
			id = k,
		})
	end
end

AddEventHandler("Characters:Client:Spawn", function()
	if not Config.EnableBlips then return end
	for k, v in ipairs(Config.FuelStations) do
		if not v.restricted and v.blip ~= false then
			plsr.Blips:Add('fuel-station-' .. k, 'Fuel Station', v.center, 361, 64, 0.4)
		end
	end
end)

AddEventHandler("Fuel:Client:FillCan", function()
	local current = GetAmmoInPedWeapon(PlayerPedId(), `WEAPON_PETROLCAN`)
	local pct = current / 4500

	plsr.Progress:Progress({
		name = "fill_petrol_can",
		duration = math.min(math.ceil(10 - (10 * pct)), 2) * 10000,
		label = "Filling Petrol Can",
		canCancel = true,
		disarm = false,
		controlDisables = {
			disableMovement = true,
			disableCarMovement = true,
			disableMouse = false,
			disableCombat = true,
		},
		animation = nil,
	}, function(cancelled)
		if not cancelled then
			plsr.Callbacks:ServerCallback("Fuel:FillCan", {
				current = current,
				pct = pct,
			}, function(s)
				if s then
					SetPedAmmo(PlayerPedId(), `WEAPON_PETROLCAN`, 5000)
				end
			end)
		end
	end)
end)

RegisterNetEvent("Characters:Client:Logout", function()
	DRIVING_VEHICLE = nil
	VEHICLE_INSIDE = nil
end)

AddEventHandler("Vehicles:Client:BecameDriver", function(veh, seat, class)
	DRIVING_VEHICLE = veh
	local vehState = plsr.State.Entity(veh)
	if vehState.VIN and vehState.Fuel ~= nil and class ~= 13 then
		TriggerEvent("Vehicles:Client:Fuel", vehState.Fuel, false)
		CreateThread(function()
			while plsr.State.flags.loggedIn and DRIVING_VEHICLE do
				if GetPedInVehicleSeat(DRIVING_VEHICLE, -1) == PlayerPedId() then
					RunFuelTick(DRIVING_VEHICLE)
				end
				Wait(3000)
			end
		end)
	else
		TriggerEvent("Vehicles:Client:Fuel", 0, true)
	end
end)

AddEventHandler("Vehicles:Client:EnterVehicle", function(veh)
	VEHICLE_INSIDE = veh

	CreateThread(function()
		Wait(500)
		while VEHICLE_INSIDE and not DRIVING_VEHICLE do
			if DoesEntityExist(VEHICLE_INSIDE) then
				local vehEntity = plsr.State.Entity(VEHICLE_INSIDE)
				if vehEntity and type(vehEntity.Fuel) == "number" then
					TriggerEvent("Vehicles:Client:Fuel", vehEntity.Fuel)
				end
			end
			Wait(3000)
		end
	end)
end)

AddEventHandler("Vehicles:Client:ExitVehicle", function()
	DRIVING_VEHICLE = nil
	VEHICLE_INSIDE = nil
end)

AddEventHandler("Vehicles:Client:SwitchVehicleSeat", function(veh, seat)
	if seat ~= -1 then
		DRIVING_VEHICLE = nil
	end
end)

function RunFuelTick(veh)
	if veh and IsVehicleEngineOn(veh) then
		local vehState = plsr.State.Entity(veh)
		if type(vehState.Fuel) == "number" then
			local vehRPM = plsr.Utils:Round(GetVehicleCurrentRpm(veh), 1)
			local classUsage = Config.Classes[GetVehicleClass(veh)] or 1.0

			local consumption = ((Config.Usage * Config.FuelUsage[vehRPM]) * classUsage) / 10

			if GetVehiclePetrolTankHealth(veh) <= 650 then
				consumption = consumption + 3.0
			end

			local newVal = plsr.Utils:Round(vehState.Fuel - consumption, 2)

			if newVal <= 0.0 then
				newVal = 0.0
				plsr.Vehicles.Engine:Force(veh, false)
			elseif newVal <= 5.0 then
				if _lowtick >= 3 then
					_lowtick = 0
					LowFuelEffects(veh)
				else
					_lowtick = _lowtick + 1
				end
			end

			TriggerEvent("Vehicles:Client:Fuel", newVal)
			vehState.Fuel = newVal
		end
	end
end

function LowFuelEffects(veh)
	if _engineShutoff then
		return
	end

	_engineShutoff = true
	Citizen.SetTimeout(2000, function()
		_engineShutoff = false
	end)

	CreateThread(function()
		while _engineShutoff do
			SetVehicleEngineOn(veh, false, true)
			Wait(1)
		end
	end)
end

AddEventHandler("Vehicles:Client:StartFueling", function(entityData, data)
	local entState = plsr.State.Entity(entityData.entity)
	entState.beingFueled = GetPlayerServerId(plsr.State.flags.PlayerID)

	local fuelData = plsr.Vehicles.Fuel:CanBeFueled(entityData.entity)
	if not fuelData then
		return
	end

	if not fuelData.needsFuel then
		plsr.Notification:Error("Vehicle Does Not Need Refueling")
		return
	end

	if data.bank then
		local p = promise.new()
		plsr.Callbacks:ServerCallback("Fuel:CheckBank", fuelData, function(res)
			p:resolve(res)
		end)
		local canAfford = Citizen.Await(p)

		if not canAfford then
			plsr.Notification:Error("Insufficient Bank Balance")
			return
		end
	else
		if plsr.State.character.Cash < fuelData.cost then
			plsr.Notification:Error("Not Enough Cash to Refuel")
			return
		end
	end

	local secondsElapsed = 0
	local time = math.min(math.ceil(fuelData.requiredFuel / 2), 40)
	TaskTurnPedToFaceEntity(PlayerPedId(), entityData.entity, 3000)
	Wait(2000)
	plsr.Animations.Emotes:Play("fuel", false, nil, true)
	plsr.Progress:ProgressWithStartAndTick({
		name = "idle",
		duration = time * 1000,
		label = "Refueling Vehicle",
		canCancel = true,
		tickrate = 1000,
		ignoreModifier = true,
		controlDisables = {
			disableMovement = true,
			disableCarMovement = true,
			disableMouse = false,
			disableCombat = true,
		},
		animation = {},
		prop = {},
		disarm = true,
	}, function()
		_fueling = true
	end, function()
		secondsElapsed = secondsElapsed + 1

		local entState = plsr.State.Entity(entityData.entity)
		if entState.beingFueled ~= nil and entState.beingFueled ~= GetPlayerServerId(plsr.State.flags.PlayerID) then
			plsr.Progress:Cancel()
		end

		local playerCoords = GetEntityCoords(PlayerPedId())
		local vehicleCoords = GetEntityCoords(entityData.entity)
		if
			not plsr.State.flags.loggedIn
			or not DoesEntityExist(entityData.entity)
			or IsEntityDead(entityData.entity)
			or #(playerCoords - vehicleCoords) > 5.0
		then
			plsr.Animations.Emotes:ForceCancel()
			plsr.Progress:Cancel()
			return
		end

		if GetIsVehicleEngineRunning(entityData.entity) then
			math.randomseed(GetGameTimer())
			local chance = math.random(0, 200)
			if chance == 69 then
				local _fuelFires = {}
				table.insert(_fuelFires, StartScriptFire(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z, 25, true))

				for i = 1, 5, 1 do
					local offsetX = math.random(-5, 5) + 0.0
					local offsetY = math.random(-5, 5) + 0.0
					local fireCoords = GetOffsetFromEntityInWorldCoords(nearPump, offsetX, offsetY, 0)
					table.insert(_fuelFires, StartScriptFire(fireCoords.x, fireCoords.y, fireCoords.z, 25, true))
				end

				-- For Good Measure 🙂
				if NetworkHasControlOfEntity(entityData.entity) then
					NetworkExplodeVehicle(entityData.entity, true, true, true)
				end

				plsr.Notification:Info("Nice One Champ")

				Citizen.SetTimeout(60000, function()
					for k, v in ipairs(_fuelFires) do
						RemoveScriptFire(v)
					end
					_fuelFires = nil
				end)

				plsr.Animations.Emotes:ForceCancel()
				plsr.Progress:Cancel()
				return
			end
		end
	end, function(wasCancelled)
		_fueling = false
		plsr.Animations.Emotes:ForceCancel()
		local fuelAmount = fuelData.requiredFuel
		if wasCancelled then
			fuelAmount = math.ceil(fuelData.requiredFuel * (secondsElapsed / time))
		end

		local entState = plsr.State.Entity(entityData.entity)
		entState.beingFueled = nil

		plsr.Callbacks:ServerCallback("Fuel:CompleteFueling", {
			vehNet = VehToNet(entityData.entity),
			vehClass = GetVehicleClass(entityData.entity),
			fuelAmount = fuelAmount,
			useBank = data.bank,
		}, function(success, amount)
			if success and amount then
				plsr.Notification:Success(string.format("Refueled Vehicle for $%d", amount))
			else
				plsr.Notification:Error("Error Refueling")
			end
		end)
	end)
end)

AddEventHandler("Vehicles:Client:StartJerryFueling", function(entityData)
	local vehicle = entityData.entity
	if DoesEntityExist(vehicle) and GetVehicleClass(vehicle) ~= 13 then
		local vehState = plsr.State.Entity(vehicle)
		if vehState.VIN and vehState.Fuel ~= nil then
			local requiredFuel = 100 - vehState.Fuel
			if requiredFuel and requiredFuel > 1 then
				local secondsElapsed = 0

				local hasWeapon, weapon = GetCurrentPedWeapon(PlayerPedId())
				local ammoAmount = GetPedAmmoByType(PlayerPedId(), `AMMO_PETROLCAN`)
				local fuelAmount = 50 * ammoAmount / 4500
				local fuck = fuelAmount
				local fuelAmountAfterUse = 0

				if not hasWeapon or weapon ~= `WEAPON_PETROLCAN` then
					return
				end

				if fuelAmount <= 0 then
					return plsr.Notification:Error("The Petrol Can Is Empty")
				end

				if requiredFuel < fuelAmount then
					fuelAmount = requiredFuel
					fuelAmountAfterUse = math.floor(fuelAmount - requiredFuel)
				end

				local time = math.ceil(fuelAmount / 2)

				plsr.Progress:ProgressWithStartAndTick({
					name = "idle",
					duration = time * 1000,
					label = "Refueling Vehicle",
					canCancel = true,
					tickrate = 1000,
					ignoreModifier = true,
					controlDisables = {
						disableMovement = true,
						disableCarMovement = true,
						disableMouse = false,
						disableCombat = true,
					},
					animation = {
						animDict = "weapons@misc@jerrycan@",
						anim = "fire",
						flags = 49,
					},
					-- prop = {
					-- 	model = "prop_jerrycan_01a",
					-- 	bone = 60309,
					-- 	coords = { x = 0.0, y = 0.1, z = 0.5 },
					-- 	rotation = { x = 364.0, y = 180.0, z = 90.0 },
					-- },
					disarm = false,
				}, function()
					_fueling = true
				end, function()
					secondsElapsed = secondsElapsed + 1

					local playerCoords = GetEntityCoords(PlayerPedId())
					local vehicleCoords = GetEntityCoords(entityData.entity)

					local hasWeapon, weapon = GetCurrentPedWeapon(PlayerPedId())

					if
						not plsr.State.flags.loggedIn
						or not hasWeapon
						or weapon ~= `WEAPON_PETROLCAN`
						or not DoesEntityExist(entityData.entity)
						or IsEntityDead(entityData.entity)
						or #(playerCoords - vehicleCoords) > 5.0
					then
						plsr.Progress:Cancel()
						return
					end

					if GetIsVehicleEngineRunning(entityData.entity) then
						math.randomseed(GetGameTimer())
						local chance = math.random(0, 200)
						if chance == 69 then
							local _fuelFires = {}
							table.insert(
								_fuelFires,
								StartScriptFire(vehicleCoords.x, vehicleCoords.y, vehicleCoords.z, 25, true)
							)

							for i = 1, 5, 1 do
								local offsetX = math.random(-5, 5) + 0.0
								local offsetY = math.random(-5, 5) + 0.0
								local fireCoords = GetOffsetFromEntityInWorldCoords(nearPump, offsetX, offsetY, 0)
								table.insert(
									_fuelFires,
									StartScriptFire(fireCoords.x, fireCoords.y, fireCoords.z, 25, true)
								)
							end

							-- For Good Measure 🙂
							if NetworkHasControlOfEntity(entityData.entity) then
								NetworkExplodeVehicle(entityData.entity, true, true, true)
							end

							plsr.Notification:Info("Nice One Champ")

							Citizen.SetTimeout(60000, function()
								for k, v in ipairs(_fuelFires) do
									RemoveScriptFire(v)
								end
								_fuelFires = nil
							end)

							plsr.Progress:Cancel()
							return
						end
					end
				end, function(wasCancelled)
					_fueling = false
					if wasCancelled then
						fuelAmount = math.ceil(fuelAmount * (secondsElapsed / time))
						fuelAmountAfterUse = math.floor(fuck - fuelAmount)
					end

					SetPedAmmoByType(PlayerPedId(), `AMMO_PETROLCAN`, (fuelAmountAfterUse / 50 * 4500))

					plsr.Callbacks:ServerCallback("Fuel:CompleteJerryFueling", {
						vehNet = VehToNet(entityData.entity),
						newAmount = math.floor(vehState.Fuel + fuelAmount + 0.0),
					}, function(success)
						if success then
							plsr.Notification:Success("Refueled Vehicle")
						else
							plsr.Notification:Error("Error Refueling")
						end
					end)
				end)
			else
				plsr.Notification:Error("Vehicle Does Not Need Refueling")
			end
		end
	end
end)

-- TODO: Add Fuel Can
