# Open Cloud: Assets API

Checked against Roblox's OpenAPI spec (`https://create.roblox.com/docs/cloud/openapi.json`) and the usage guide (`/docs/cloud/guides/usage-assets`). Base URL `https://apis.roblox.com` (`ROBLOX_OPEN_CLOUD_URL` overrides it for tests), header `x-api-key`.

## Permissions
| API system (key UI) | Operations | Needed for |
| --- | --- | --- |
| assets | Read | polling operations, reading assets (`asset:read`) |
| assets | Write | creating and updating assets (`asset:write`) |
| asset-permissions | Write | `grant`: let a universe use an asset (`asset-permissions:write`) |

A group-owned asset needs a key created under the group by someone allowed to manage its assets. Keys auto-expire when not used or updated for 60 days (re-enable them on the API Keys page); a set expiration date disables them on that date.

## Endpoints
| Action | Request | Result |
| --- | --- | --- |
| Create | `POST /assets/v1/assets`, multipart: `request` (JSON) + `fileContent` (file with its content type) | Operation |
| Update content | `PATCH /assets/v1/assets/{assetId}`, same form, `request.assetId` set | Operation (new version) |
| Poll | `GET /assets/v1/operations/{operationId}` | `{done, response | error}` |
| Get | `GET /assets/v1/assets/{assetId}` | Asset |
| Versions | `GET /assets/v1/assets/{assetId}/versions`, `POST .../versions:rollback` | |
| Archive / restore | `POST /assets/v1/assets/{assetId}:archive` / `:restore` | |
| Grant use | `PATCH /asset-permissions-api/v1/assets/permissions`, JSON `{subjectType: "Universe", subjectId, action: "Use", requests: [{assetId, grantToDependencies}]}` | `{errors}` |
| Key info | `POST /api-keys/v1/introspect`, JSON `{apiKey}` (no header) | name, `authorizedUserId`, scopes, enabled, expired, `expirationTimeUtc` |

`request` for create:
```json
{
  "assetType": "Model",
  "displayName": "LowPolyTree",
  "description": "Low-poly pine for the forest kit",
  "creationContext": { "creator": { "userId": 123 }, "expectedPrice": 0 }
}
```
`creator` takes `userId` or `groupId`. `expectedPrice` is the highest upload fee accepted in Robux: if the real fee is higher the request fails with 400 instead of charging.

Create and update return an Operation `{ "path": "operations/{id}", "done": false }`; poll until `done`, then `response.assetId`, `response.revisionId` (version) and `response.moderationResult.moderationState` (`MODERATION_STATE_APPROVED`, `_REVIEWING`, `_REJECTED`), or `error.message`.

Rate limits per key owner: 120 create/update/get per minute, 300 operation polls per minute, 100 version/archive calls per minute.

## Supported files (one file per call, up to 20 MB)
| Asset type | Files | Content type | Notes |
| --- | --- | --- | --- |
| Model | `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx` | `model/fbx`, `model/gltf+json`, `model/gltf-binary`, `model/x-rbxm` | becomes a Model with MeshParts, stored as a package; only FBX content can be updated |
| Decal / Image | `.png`, `.jpeg`, `.bmp`, `.tga` | `image/png`, `image/jpeg`, `image/bmp`, `image/tga` | under 8000x8000; can't be updated |
| Audio | `.mp3`, `.ogg`, `.wav`, `.flac` | `audio/mpeg`, `audio/ogg`, `audio/wav`, `audio/flac` | up to 7 minutes; 100 uploads a month ID-verified, 10 without |
| Video | `.mp4`, `.mov` | `video/mp4`, `video/mov` | up to 5 minutes, 4096x2160, 3.75 GB, 20 a day (13+, ID-verified) |
| Animation | `.rbxm`, `.rbxmx` | `model/x-rbxm` | exported from Studio |

`.obj` is not on the list: convert to GLB/FBX, or import it with Studio's 3D Importer. A `.gltf` that refers to separate `.bin`/texture files can't be uploaded alone: export glTF Binary.

## In Studio and in game
- Uploaded models show up in Toolbox > Inventory > My Packages (Creations > Group Packages for groups) and load with `InsertService:LoadAsset(id)`, which returns a Model container: parent its children.
- `LoadAsset` works in Studio (command bar, plugins, MCP) and on game servers for assets the experience's creator owns.
- Images: use `rbxassetid://<id>` in properties. A Decal upload gives a decal ID; Studio turns it into the image ID when pasted into a texture property; for scripts use the image ID (shown in Studio after pasting) or upload with `--type Image`.
- Moderation can take a while: assets in review may fail to load until approved.
