--!strict
-- Developer product receipt processing (pure logic, dependencies injected for tests).
--
-- Guarantees:
--  * Never grants twice: the PurchaseId is stored in the player's profile together with the grant,
--    and a receipt whose id is already stored is only re-saved, never re-granted.
--  * Never loses a purchase: we answer "Granted" only after the profile (grant + id) is saved.
--    Any failure answers "NotProcessedYet", so Roblox retries later (or refunds).

local ProfileSchema = require(script.Parent.ProfileSchema)

export type Receipt = {
	PlayerId: number,
	ProductId: number,
	PurchaseId: string,
	CurrencySpent: number?,
}

export type Context = { Profile: { Data: ProfileSchema.Data }, Player: any }

export type Deps = {
	getContext: (userId: number) -> Context?,
	productKeyForId: (productId: number) -> string?,
	grant: (ctx: Context, productKey: string, receipt: Receipt) -> boolean,
	save: (ctx: Context) -> boolean,
	now: () -> number,
	maxStoredIds: number,
	log: ((message: string) -> ())?,
}

local ReceiptLogic = {}

ReceiptLogic.Granted = "Granted"
ReceiptLogic.NotProcessedYet = "NotProcessedYet"

function ReceiptLogic.Process(receipt: Receipt, deps: Deps): string
	local ctx = deps.getContext(receipt.PlayerId)
	if not ctx then
		return ReceiptLogic.NotProcessedYet -- player not here (yet): Roblox retries when they join
	end
	local data = ctx.Profile.Data
	local purchaseId = tostring(receipt.PurchaseId)

	if data.Purchases[purchaseId] then
		-- Already granted earlier; make sure it is persisted before confirming.
		if deps.save(ctx) then
			return ReceiptLogic.Granted
		end
		return ReceiptLogic.NotProcessedYet
	end

	local productKey = deps.productKeyForId(receipt.ProductId)
	if not productKey then
		if deps.log then
			deps.log("Unknown product id " .. tostring(receipt.ProductId))
		end
		return ReceiptLogic.NotProcessedYet
	end

	local ok, granted = pcall(deps.grant, ctx, productKey, receipt)
	if not ok or not granted then
		if deps.log then
			deps.log("Grant failed for " .. productKey .. ": " .. tostring(granted))
		end
		return ReceiptLogic.NotProcessedYet
	end

	ProfileSchema.RecordPurchase(data, purchaseId, deps.now(), deps.maxStoredIds)
	data.Stats.RobuxSpent += receipt.CurrencySpent or 0

	if deps.save(ctx) then
		return ReceiptLogic.Granted
	end
	return ReceiptLogic.NotProcessedYet
end

return ReceiptLogic
