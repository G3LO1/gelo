# Open Cloud: game passes and developer products

Checked against Roblox's OpenAPI spec (`https://create.roblox.com/docs/cloud/openapi.json`). Both APIs are **Beta**: if a call starts failing with 404/400 after working before, re-check the spec before changing `monetize.py`.

Base URL `https://apis.roblox.com` (override with `ROBLOX_OPEN_CLOUD_URL`, used by the tests). Auth header `x-api-key: <key>`.

## API key
Creator Hub > All tools > Open Cloud > API Keys > Create API Key. Permissions are per API system and per experience:

| API system (UI) | Operations | Scope (OAuth name) |
| --- | --- | --- |
| `game-passes` | read, write | `game-pass:read`, `game-pass:write` |
| `developer-products` | read, write | `developer-product:read`, `developer-product:write` |

The experience must be in the key's list. A group-owned experience needs a key created under the group (the group's API Keys page) by someone with the permission. Optional IP allowlist (`0.0.0.0/0` = any) and expiration date; an expired, disabled or revoked key gives 401.

## Endpoints

| Action | Method and path | Success |
| --- | --- | --- |
| Create pass | `POST /game-passes/v1/universes/{universeId}/game-passes` | 200 + pass |
| Update pass | `PATCH /game-passes/v1/universes/{universeId}/game-passes/{gamePassId}` | 204 |
| Get pass | `GET /game-passes/v1/universes/{universeId}/game-passes/{gamePassId}/creator` | 200 |
| List passes | `GET /game-passes/v1/universes/{universeId}/game-passes/creator?pageSize=&pageToken=` | 200 `{gamePasses, nextPageToken}` |
| Create product | `POST /developer-products/v2/universes/{universeId}/developer-products` | 200 + product |
| Update product | `PATCH /developer-products/v2/universes/{universeId}/developer-products/{productId}` | 204 |
| Get product | `GET /developer-products/v2/universes/{universeId}/developer-products/{productId}/creator` | 200 |
| List products | `GET /developer-products/v2/universes/{universeId}/developer-products/creator?pageSize=&pageToken=` | 200 `{developerProducts, nextPageToken}` |

There is no delete: take an item off sale with `isForSale=false`.

### Request body (POST and PATCH): `multipart/form-data`
| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | required on POST |
| `description` | string | |
| `price` | int64 | default price in Robux |
| `isForSale` | boolean | `true` / `false` |
| `isManagedPricingEnabled` | boolean | Roblox price optimization (replaces the deprecated `isRegionalPricingEnabled`; don't send both) |
| `imageFile` | file | icon; `monetize.py` always sends a 512x512 PNG |

PATCH changes only the fields that are sent.

### Response fields
- Pass: `gamePassId`, `name`, `description`, `isForSale`, `iconAssetId`, `priceInformation.defaultPriceInRobux`, `isManagedPricingEnabled`, timestamps.
- Product: `productId`, `name`, `description`, `isForSale`, `iconImageAssetId`, `universeId`, `priceInformation.defaultPriceInRobux`, `isManagedPricingEnabled`, `isImmutable`, timestamps.
- The icon is shown in game with `rbxassetid://<iconAssetId>`; the ID changes on every new upload.

## Rate limits (per API key owner)
Writes: passes 5/s, products 3/s. Reads: 10/s. `monetize.py` spaces writes accordingly and retries 429 and 5xx with `Retry-After` or exponential backoff (up to 6 attempts).

## Errors
| Status | Usual cause |
| --- | --- |
| 400 | invalid field: price out of range, name moderated or too long, image not accepted |
| 401 | key wrong, expired, revoked or disabled |
| 403 | key lacks the permission, the experience isn't on the key, or the IP allowlist blocks the machine |
| 404 | wrong universe ID (place ID used by mistake) or the item was deleted |
| 409 | conflict, e.g. duplicate name: run sync again, it adopts the existing item by name |

## In the game (MarketplaceService)
- Products are granted only in `MarketplaceService.ProcessReceipt` (one callback per game, on the server), idempotent by `PurchaseId`; the template's `PurchaseService` does this.
- Passes: `UserOwnsGamePassAsync(userId, passId)` on join, `PromptGamePassPurchaseFinished` for purchases in the session.
- Prompts from the client: `PromptProductPurchase(player, productId)`, `PromptGamePassPurchase(player, passId)`.
- Prices for UI: `GetProductInfoAsync(id, Enum.InfoType.Product | Enum.InfoType.GamePass).PriceInRobux` (`GetProductInfo` is deprecated). Prices vary per player with managed/regional pricing, so never hard-code them.
- Studio test purchases are free and still go through `ProcessReceipt`; new IDs reach live servers after the place is published (old servers keep the old module until they shut down).
