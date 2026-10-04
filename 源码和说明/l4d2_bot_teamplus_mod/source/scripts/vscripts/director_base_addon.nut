// Valve's addon loader runs this entry for each mounted addon.
if (!("BTPMod" in getroottable()))
    IncludeScript("bot_teamplus/core", getroottable());
::BTPMod.Start();
