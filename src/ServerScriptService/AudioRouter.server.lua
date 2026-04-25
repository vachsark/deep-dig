-- AudioRouter.server.lua — creates the PlaySound RemoteEvent.
-- Place in: ServerScriptService/AudioRouter (Script)
--
-- Server scripts fire `Remotes.PlaySound:FireClient(player, "key")` or
-- `:FireAllClients("key")` to trigger named sounds. The client-side
-- StarterGui/AudioPlayer.client.lua maps keys to Roblox asset IDs and plays.
--
-- The keys server scripts use today (search for `-- SOUND HOOK:`):
--   block_break       — every dig click
--   item_found        — sparkle chime on any item find
--   rare_reveal       — dramatic boom on Rare+ finds
--   sell_coins        — coin clink on sell
--   upgrade_whoosh    — power-up on tool upgrade
--   event_alarm       — world event triggered (FireAllClients)
--   resurface_fanfare — prestige cinematic (FireAllClients)
--
-- Asset IDs are owned by the client so designers can swap them without a
-- server restart. Server stays decoupled from the asset registry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

if not Remotes:FindFirstChild("PlaySound") then
	local PlaySound = Instance.new("RemoteEvent")
	PlaySound.Name = "PlaySound"
	PlaySound.Parent = Remotes
end

print("[DeepDig] AudioRouter loaded")
