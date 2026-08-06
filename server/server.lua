local threading = false
local bankAcc = nil
local depositData = {
	amount = 0,
	transactions = 0,
}

CreateThread(function()
	RegisterCallbacks()

	if not threading then
		CreateThread(function()
			while true do
				Wait(1000 * 60 * 10)
				if depositData.amount > 0 then
					plsr.Logger:Trace(
						"Fuel",
						string.format("Depositing ^2$%s^7 To ^3%s^7", math.abs(depositData.amount), bankAcc)
					)
					plsr.Banking.Balance:Deposit(bankAcc, math.abs(depositData.amount), {
						type = "deposit",
						title = "Fuel Services",
						description = string.format(
							"Payment For Fuel Services For %s Vehicles",
							depositData.transactions
						),
						data = {},
					}, true)
					depositData = {
						amount = 0,
						transactions = 0,
					}
				end
			end
		end)
		threading = true
	end

	Wait(2000)
	local f = plsr.Banking.Accounts:GetOrganization("dgang")
	if f then
		bankAcc = f.Account
	else
		plsr.Logger:Warn("Fuel", "Organization bank account for 'dgang' not ready yet (normal on first server start before pulsar_finance seeds accounts), skipping until next restart")
	end
end)

function RegisterCallbacks()
	plsr.Callbacks:RegisterServerCallback("Fuel:CheckBank", function(source, data, cb)
		local char = plsr.Fetch:CharacterSource(source)
		if char and data?.cost then
			cb(plsr.Banking.Balance:Has(char:GetData("BankAccount"), data.cost))
		else
			cb(false)
		end
	end)

	plsr.Callbacks:RegisterServerCallback("Fuel:CompleteFueling", function(source, data, cb)
		local char = plsr.Fetch:CharacterSource(source)
		if char and data and data.vehNet and type(data.vehClass) == "number" and type(data.fuelAmount) == "number" then
			local veh = NetworkGetEntityFromNetworkId(data.vehNet)
			if veh and DoesEntityExist(veh) then
				local vehState = plsr.State.Entity(veh)
				local totalCost = CalculateFuelCost(data.vehClass, data.fuelAmount)

				if vehState and totalCost then
					local paymentSuccess = false
					if data.useBank then
						paymentSuccess = plsr.Banking.Balance:Charge(char:GetData("BankAccount"), math.abs(totalCost), {
							type = 'bill',
							title = 'Fuel Purchase',
							description = 'Fuel Purchase',
							data = {
								vehicle = vehState.VIN,
								fuel = data.fuelAmount,
							}
						})

						if paymentSuccess then
							plsr.Phone.Notification:Add(source, string.format("Fuel Purchase of $%s Successful", math.ceil(totalCost)), false, os.time(), 3000, "bank", {})
						end
					else
						paymentSuccess = plsr.Wallet:Modify(source, -math.abs(totalCost), true)
					end

					if paymentSuccess then
						-- TODO: Incorporate the shop bank accounts where possible so money
						-- is sent to those accounts instead of a static one
						depositData.amount += math.abs(totalCost)
						depositData.transactions += 1
	
						vehState.Fuel = math.min(math.ceil(vehState.Fuel + data.fuelAmount), 100)
						cb(true, totalCost)
						return
					end
				end
			end
		end
		cb(false)
	end)

	plsr.Callbacks:RegisterServerCallback("Fuel:CompleteJerryFueling", function(source, data, cb)
		local char = plsr.Fetch:CharacterSource(source)
		if char and data and data.vehNet and type(data.newAmount) == "number" then
			local veh = NetworkGetEntityFromNetworkId(data.vehNet)
			if veh and DoesEntityExist(veh) then
				local vehState = plsr.State.Entity(veh)

				if vehState then
					vehState.Fuel = math.min(data.newAmount, 100)
					cb(true)
					return
				end
			end
		end
		cb(false)
	end)

	plsr.Callbacks:RegisterServerCallback("Fuel:FillCan", function(source, data, cb)
		local totalCost = CalculateFuelCost(0, math.floor(100 - (data.pct * 100)))
		cb(totalCost and plsr.Wallet:Modify(source, -math.abs(totalCost), true))
	end)
end
