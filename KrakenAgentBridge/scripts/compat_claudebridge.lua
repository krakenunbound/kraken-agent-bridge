-- The bridge's former name. Kraken Agent Bridge was "Claude Bridge" (0.x);
-- extensions written for it call ClaudeBridge.registerPackage, which still works.
-- Don't enable the old Claude Bridge extension in the same campaign: both would
-- poll the daemon and both define this package.

function registerPackage(sName, tPackage)
	return AgentBridge.registerPackage(sName, tPackage);
end

function listPackageFunctions(sName)
	return AgentBridge.listPackageFunctions(sName);
end

function inspectTokenVision(nodeCT)
	return AgentBridge.inspectTokenVision(nodeCT);
end
