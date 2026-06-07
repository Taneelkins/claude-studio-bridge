--!strict
-- Holds the plugin object so non-entry modules can use plugin settings as
-- cross-DataModel storage (edit <-> play communication). Set once by Main.

local PluginRef: { plugin: Plugin? } = { plugin = nil }

return PluginRef
