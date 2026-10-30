-- Kraken Agent Bridge (formerly Claude Bridge). Any ruleset. Lets an AI agent
-- (any MCP client, or anything that can send HTTP to 127.0.0.1) read and drive
-- this campaign. Runs on the GM (role "host") and on a player client on the
-- same machine (role "client"); each polls with its role.
--
-- Fantasy Grounds cannot listen for connections, so this script asks the
-- local bridge daemon for work: it keeps one request open to /poll, runs the
-- command it gets back, sends the result to /result, and polls again.
-- The daemon only listens on 127.0.0.1.
--
-- The Lua sandbox has no loadstring or _G, so commands are a fixed set.
-- "call" reaches functions only in the packages listed in tPackages (or
-- added with AgentBridge.registerPackage; the old name ClaudeBridge still works).

local VERSION = "1.1.0";
local BASE = "http://127.0.0.1:47111";
local CHUNK = 12000;

local _nGeneration = 0;
local _bRunning = false;
-- When the daemon last answered (os.time). Fantasy Grounds gives no callback
-- when a request cannot connect, so a poll that fails (daemon not running
-- yet) ends the loop; nudge() restarts it on the next chat message or window
-- opening once the daemon has been silent longer than a held poll lasts.
local _nLastReply = 0;
local STALE = 40;
local tPackages = {};
-- Values an agent keeps inside FGU between commands (id -> value), and
-- database subscriptions (id -> { path, events, handlers }).
local _tHandles = {};
local _nHandle = 0;
local _tSubs = {};
local _nSub = 0;
-- The results of the batch being run, for {"$ref": "2.result.1"} arguments.
local _tBatch = nil;

--
-- Setup
--

-- File.getCampaignFolder and similar are host-only; on a client they raise.
local function safeCall(fn)
	if not fn then
		return "";
	end
	local bOK, v = pcall(fn);
	if bOK and v then
		return v;
	end
	return "";
end

local function getRole()
	return Session.IsHost and "host" or "client";
end

-- The channel the daemon gave this copy: its role, or "host2".. for a second
-- GM copy on the machine (another campaign), so both stay connected.
local _sChannel = nil;
local function getChannel()
	return _sChannel or getRole();
end

function onInit()
	Comm.registerSlashHandler("agentbridge", onSlash, "Reconnect the Kraken Agent Bridge");
	Comm.registerSlashHandler("claudebridge", onSlash, "Reconnect the Kraken Agent Bridge (old name)");
	registerDefaultPackages();
	if ChatManager and ChatManager.registerReceiveMessageCallback then
		ChatManager.registerReceiveMessageCallback(function(msg) nudge(); onChatReceived(msg); end);
	end
	-- A window opening also restarts a dead loop. Subscribe through FGU's event
	-- list: replacing Interface.onWindowOpened and calling the old handler ran
	-- the ruleset's own handler twice (in AD&D 2E its window manager then closed
	-- every record window as it opened, Characters included).
	if Interface.addKeyedEventHandler then
		Interface.addKeyedEventHandler("onWindowOpened", "", function() nudge(); end);
	end
	start();
end

-- Restart a loop that died on a failed request (see _nLastReply).
function nudge()
	if _bRunning and (os.time() - _nLastReply) > STALE then
		start();
	end
end

function registerPackage(sName, tPackage)
	if (sName or "") ~= "" and tPackage then
		tPackages[sName] = tPackage;
	end
end

-- Discover public entry points without reading protected ruleset source.
function listPackageFunctions(sName)
	local names = {};
	if type(tPackages[sName]) ~= "table" then return names; end
	for name, value in pairs(tPackages[sName] or {}) do
		if type(value) == "function" then table.insert(names, name); end
	end
	table.sort(names);
	return names;
end

-- What CoreRPG's vision code works out for a tracker entry's token: the
-- map's distance per square and each vision's type and range in squares.
function inspectTokenVision(nodeCT)
	local token = CombatManager.getTokenFromCT(nodeCT);
	if not token then return { error = "no token" }; end
	local r = VisionManager.getTokenVisionInfo(token, nodeCT);
	return { distanceunits = r.distanceunits, defaultrange = r.defaultrange, rangemax = r.rangemax,
		rangemod = r.rangemod, defaultvision = r.defaultvision, visions = r.tCurrVisionData };
end

-- Packages any agent can call: Fantasy Grounds' own API and CoreRPG, then
-- packages of common rulesets and of Kraken's extensions, each registered only
-- when it is loaded (an absent one is nil and is skipped). Anything else: have
-- your extension call AgentBridge.registerPackage("Name", Name).
function registerDefaultPackages()
	local t = {
		-- Fantasy Grounds API
		DB = DB, Interface = Interface, Comm = Comm, File = File, Session = Session,
		User = User, Utility = Utility, Module = Module, Input = Input,
		-- CoreRPG
		ActorManager = ActorManager, ActionsManager = ActionsManager, ActorHealthManager = ActorHealthManager,
		ActorCommonManager = ActorCommonManager,
		ActionHealthD20 = ActionHealthD20, ActionDamageD20 = ActionDamageD20, ActionCore = ActionCore,
		CombatManager = CombatManager, CombatRecordManager = CombatRecordManager, TargetingManager = TargetingManager,
		OOBManager = OOBManager, Comm = Comm,
		EffectManager = EffectManager, ChatManager = ChatManager, OptionsManager = OptionsManager,
		GameManager = GameManager, ModifierStack = ModifierStack, CharManager = CharManager,
		NPCManager = NPCManager, ItemManager = ItemManager, WindowManager = WindowManager,
		DiceManager = DiceManager, StringManager = StringManager, RecordDataManager = RecordDataManager,
		LibraryData = LibraryData, TokenManager = TokenManager, PartyManager = PartyManager,
		TableManager = TableManager, RecordManager = RecordManager, RecordAssetManager = RecordAssetManager,
		CurrencyManager = CurrencyManager,
		CalendarManager = CalendarManager,
		VisionManager = VisionManager, ImageManager = ImageManager,
		-- SiegeCore (nil when another ruleset is loaded)
		SiegeMath = SiegeMath, DataCommon = DataCommon, OptionsSiege = OptionsSiege, SiegeRules = SiegeRules,
		SiegeChar = SiegeChar, ActorManagerSiege = ActorManagerSiege, EffectManagerSiege = EffectManagerSiege,
		ActionSiege = ActionSiege, ActionAttack = ActionAttack, ActionDamage = ActionDamage,
		ActionSpellResistance = ActionSpellResistance,
		SiegePowerResolution = SiegePowerResolution, SiegePowerActions = SiegePowerActions,
		SiegeNegativeRecovery = SiegeNegativeRecovery, SiegeLoad = SiegeLoad, SiegeLight = SiegeLight,
		ActionInit = ActionInit, ActionHP = ActionHP, SiegePower = SiegePower, SiegeGame = SiegeGame, SiegeTranslate = SiegeTranslate, SiegeRecordAlias = SiegeRecordAlias, SiegeTranslatePower = SiegeTranslatePower, LibraryDataSiege = LibraryDataSiege, SiegeTest = SiegeTest,
		-- Character wizards (nil when not loaded)
		CharWizard35E = CharWizard35E,
		CharWizard2E = CharWizard2E,
		Kraken35EHalfCasterFix = Kraken35EHalfCasterFix,
		KrakenSpellSlots = KrakenSpellSlots,
		KrakenAutoload = KrakenAutoload,
		SpellManager = SpellManager, KrakenFeatures = KrakenFeatures, KrakenDecal = KrakenDecal, KrakenWeaponFeats = KrakenWeaponFeats, KrakenMonk = KrakenMonk, KrakenSpells = KrakenSpells, KrakenSaves = KrakenSaves, KrakenClassActions = KrakenClassActions, KrakenXP = KrakenXP, CampaignDataManager = CampaignDataManager, CombatManager2 = CombatManager2, ActionSave = ActionSave, ActionHeal = ActionHeal, ActionSpell = ActionSpell, ActionCast = ActionCast, ActionSkill = ActionSkill, ActionAbility = ActionAbility, ActionEffect = ActionEffect, ActionSpellSave = ActionSpellSave, ActionHealD20 = ActionHealD20,
		ChatIdentityManager = ChatIdentityManager, KrakenGMIcon = KrakenGMIcon,
		AgentBridge = AgentBridge, ClaudeBridge = ClaudeBridge, AgentAssistant = AgentAssistant,
	};
	for k, v in pairs(t) do
		registerPackage(k, v);
	end
end

-- /agentbridge [start|stop|status|permissions reset|help]; no word reconnects.
function onSlash(_, sParams)
	local sWord = StringManager.trim(sParams or ""):lower();
	if sWord == "stop" then
		stop();
	elseif sWord == "status" then
		local nAge = os.time() - _nLastReply;
		local nSubs, nHandles = 0, 0;
		for _ in pairs(_tSubs) do nSubs = nSubs + 1; end
		for _ in pairs(_tHandles) do nHandles = nHandles + 1; end
		ChatManager.SystemMessage(string.format("Agent bridge %s: %s, channel %s, last reply from the server %ds ago, %d subscriptions, %d handles.",
			VERSION, _bRunning and "running" or "paused", getChannel(), nAge, nSubs, nHandles));
		if AgentAssistant and AgentAssistant.statusText then
			ChatManager.SystemMessage(AgentAssistant.statusText());
		end
	elseif sWord == "permissions reset" then
		if AgentAssistant and AgentAssistant.resetDecisions then
			AgentAssistant.resetDecisions();
		end
	elseif sWord == "help" then
		ChatManager.SystemMessage("/agentbridge - reconnect | /agentbridge stop | /agentbridge status | /agentbridge permissions reset\r"
			.. "@ai <question> - ask the AI in chat (answer goes to you and the GM) | /ai <question> - private question (the GM only)");
	else
		start();
		ChatManager.SystemMessage("Agent bridge: reconnecting to local server.");
	end
end

-- The first request of a session is what Fantasy Grounds shows in its
-- "allow this URL?" prompt, so it is the short poll. Campaign details go to
-- /hello after the first poll comes back, when the URL is already allowed.
local _bHelloSent = false;

-- This instance's id (a table address: unique per Fantasy Grounds process).
-- The daemon sends a role's commands only to the instance that sent the
-- latest /hello for it, so a second GM instance on the machine (another
-- campaign) never picks up commands meant for this one.
local _sInstance = nil;

function start()
	if not _sInstance then
		_sInstance = tostring({}):gsub("%W", "");
	end
	_sChannel = nil;
	_nGeneration = _nGeneration + 1;
	_bRunning = true;
	_bHelloSent = false;
	_nLastReply = os.time();
	poll(_nGeneration, true);
end

-- Invalidate outstanding callbacks without closing the campaign or server.
function stop()
	_nGeneration = _nGeneration + 1;
	_bRunning = false;
	ChatManager.SystemMessage("Agent bridge: paused.");
end

function sendHello()
	_bHelloSent = true;
	local nGeneration = _nGeneration;
	post("/hello", {
		version = VERSION,
		role = getRole(),
		user = Session.UserName,
		ruleset = Session.RulesetName,
		campaign_folder = safeCall(File.getCampaignFolder),
		data_folder = safeCall(File.getDataFolder),
		generation = _nGeneration,
		instance = _sInstance,
	}, function(_, sResponse)
		if nGeneration ~= _nGeneration or not _bRunning then return; end
		local sChannel = (sResponse or ""):match("^ok%s*(%S*)$");
		if sChannel then
			_sChannel = (sChannel ~= "") and sChannel or getRole();
			local sWhere = BASE:gsub("^https?://", ""):gsub("^127%.0%.0%.1", "localhost");
			if _sChannel == getRole() then
				ChatManager.SystemMessage("Agent bridge: connected (" .. _sChannel .. ", " .. sWhere .. ").");
			else
				ChatManager.SystemMessage("Agent bridge: connected (" .. _sChannel .. ", " .. sWhere .. "): another GM copy on this computer already has host, so agents address this one as " .. _sChannel .. ".");
			end
		else
			_bHelloSent = false;
		end
	end);
end

--
-- JSON out
--

local function jsonString(s)
	s = tostring(s);
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t");
	s = s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", c:byte()); end);
	-- Non-ASCII as \u escapes: openURL rejects some raw UTF-8 ("A–Z"), and
	-- result chunks could otherwise split a character.
	s = s:gsub("[\192-\247][\128-\191]*", function(c)
		local b1, n = c:byte(1), #c;
		local cp;
		if b1 < 224 and n == 2 then
			cp = (b1 - 192) * 64 + (c:byte(2) - 128);
		elseif b1 < 240 and n == 3 then
			cp = (b1 - 224) * 4096 + (c:byte(2) - 128) * 64 + (c:byte(3) - 128);
		elseif n == 4 then
			cp = (b1 - 240) * 262144 + (c:byte(2) - 128) * 4096 + (c:byte(3) - 128) * 64 + (c:byte(4) - 128);
		else
			return "\\ufffd";
		end
		if cp >= 65536 then
			cp = cp - 65536;
			return string.format("\\u%04x\\u%04x", 55296 + math.floor(cp / 1024), 56320 + cp % 1024);
		end
		return string.format("\\u%04x", cp);
	end);
	s = s:gsub("[\128-\255]", "\\ufffd");
	return "\"" .. s .. "\"";
end

local function isArray(t)
	local n = 0;
	for k, _ in pairs(t) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false;
		end
		n = n + 1;
	end
	for i = 1, n do
		if t[i] == nil then
			return false;
		end
	end
	return true;
end

function toJSON(v, nDepth)
	nDepth = nDepth or 0;
	local sType = type(v);
	if v == nil then
		return "null";
	elseif sType == "boolean" then
		return v and "true" or "false";
	elseif sType == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null";
		end
		return tostring(v);
	elseif sType == "string" then
		return jsonString(v);
	elseif sType == "databasenode" then
		return "{\"$node\":" .. jsonString(DB.getPath(v)) .. "}";
	elseif sType == "table" then
		if nDepth > 6 then
			return jsonString("<table>");
		end
		local tParts = {};
		local bEmpty = true;
		for _ in pairs(v) do
			bEmpty = false;
			break;
		end
		if bEmpty then
			return "{}";
		end
		if isArray(v) then
			for i = 1, #v do
				table.insert(tParts, toJSON(v[i], nDepth + 1));
			end
			return "[" .. table.concat(tParts, ",") .. "]";
		end
		for k, vItem in pairs(v) do
			if type(vItem) ~= "function" then
				table.insert(tParts, jsonString(k) .. ":" .. toJSON(vItem, nDepth + 1));
			end
		end
		return "{" .. table.concat(tParts, ",") .. "}";
	elseif sType == "userdata" then
		local bOK, sPath = pcall(DB.getPath, v);
		if bOK and sPath then
			return "{\"$node\":" .. jsonString(sPath) .. "}";
		end
		return jsonString("<userdata>");
	end
	return jsonString("<" .. sType .. ">");
end

--
-- Transport
--

function post(sPath, t, fCallback)
	Interface.openURL(BASE .. sPath .. "?d=" .. Utility.encodeURL(toJSON(t)), fCallback);
end

function poll(nGeneration, bHandshake)
	Interface.openURL(BASE .. "/poll?r=" .. getChannel() .. "&g=" .. nGeneration .. "&i=" .. (_sInstance or "") .. (bHandshake and "&h=1" or ""), function(_, sResponse)
		onPollReply(nGeneration, sResponse);
	end);
end

-- A reply to an older poll (before /agentbridge restarted the loop) still
-- runs its command, so nothing queued is lost, but does not poll again.
function onPollReply(nGeneration, sResponse)
	if not _bRunning then return; end
	_nLastReply = os.time();
	if nGeneration == _nGeneration and not _bHelloSent then
		sendHello();
	end
	if (sResponse or "") ~= "" then
		local tCommand = Utility.decodeJSON(sResponse);
		if type(tCommand) == "table" and tCommand.id then
			local tResult = runCommand(tCommand);
			sendResult(tCommand.id, tResult);
		end
	end
	if nGeneration == _nGeneration then
		poll(nGeneration);
	end
end

function sendResult(sID, tResult)
	local sJSON = toJSON(tResult);
	local nParts = math.max(1, math.ceil(#sJSON / CHUNK));
	for i = 1, nParts do
		local sChunk = sJSON:sub((i - 1) * CHUNK + 1, i * CHUNK);
		Interface.openURL(string.format("%s/result?id=%s&part=%d&of=%d&d=%s",
			BASE, Utility.encodeURL(tostring(sID)), i, nParts, Utility.encodeURL(sChunk)), nil);
	end
end

--
-- Argument decoding. JSON objects with one of these keys become FG values:
--   {"$node": "path"}  -> databasenode       {"$actor": "path"} -> rActor
--   {"$nil": true}     -> nil
--   {"$handle": "h3"}  -> a value kept with keep=true (any Lua value: table, node, actor)
--   {"$ref": "2.result.1"} -> inside a batch: a value from step 2's result (raw Lua, not JSON)
--

-- "2.result.1" -> step 2's result, then its field "result", then index 1.
local function resolveRef(sRef)
	if not _tBatch then
		error("$ref is only valid inside fgu_batch");
	end
	local v = nil;
	local bFirst = true;
	for sPart in tostring(sRef):gmatch("[^%.]+") do
		local k = tonumber(sPart) or sPart;
		if bFirst then
			v = _tBatch[k];
			bFirst = false;
		elseif type(v) == "table" then
			v = v[k];
		else
			error("$ref " .. tostring(sRef) .. ": nothing at " .. sPart);
		end
	end
	return v;
end

local function decodeArg(v)
	if type(v) ~= "table" then
		return v;
	end
	if v["$handle"] then
		local h = _tHandles[v["$handle"]];
		if not h then
			error("no handle " .. tostring(v["$handle"]) .. " (released, or FGU reloaded)");
		end
		return h.value;
	elseif v["$ref"] then
		return resolveRef(v["$ref"]);
	elseif v["$node"] then
		return DB.findNode(v["$node"]);
	elseif v["$shortcut"] then
		local link = v["$shortcut"];
		return {
			getType = function() return "shortcut"; end,
			isType = function(sType) return sType == "shortcut"; end,
			getShortcutData = function() return link.class, link.path; end,
			getDatabaseNode = function() return DB.findNode(link.path); end,
			getDescription = function() return DB.getValue(link.path .. ".name", ""); end,
		};
	elseif v["$actor"] then
		return ActorManager.resolveActor(v["$actor"]);
	elseif v["$nil"] then
		return nil;
	end
	local t = {};
	for k, vItem in pairs(v) do
		t[k] = decodeArg(vItem);
	end
	return t;
end

local function decodeArgs(tArgs)
	local tOut = {};
	local n = 0;
	for i, v in ipairs(tArgs or {}) do
		tOut[i] = decodeArg(v);
		n = i;
	end
	return tOut, n;
end

-- The sandbox has no unpack or table.unpack.
local function fUnpack(t, i, n)
	i = i or 1;
	n = n or #t;
	if i > n then
		return;
	end
	return t[i], fUnpack(t, i + 1, n);
end

--
-- Database
--

-- The combat tracker is public in FGU, but a player's table only shows the
-- entries that are visible to them and no numbers for foes. For a player's
-- @ai question: hidden entries are left out, and so are the hit point and
-- defence fields of entries that are not friends of the party.
local tFoeFields = { "^hp", "hp$", "^wound", "wounds$", "^ac$", "^ac[_%.]", "^defen", "^hd$", "^hitdice", "^nonlethal",
	"^temphp", "^deathsave", "^injur", "^damage", "^fatigue", "^stress" };
function hiddenFromPlayer(node, sUser)
	local sPath = DB.getPath(node) or "";
	local sEntry = sPath:match("^(combattracker%.list%.[^%.]+)");
	if not sEntry then
		return false;
	end
	local nodeEntry = DB.findNode(sEntry);
	if not nodeEntry or isOwnedBy(sEntry, sUser) then
		return false;
	end
	if DB.getValue(nodeEntry, "tokenvis", 1) == 0 then
		return true;
	end
	if DB.getValue(nodeEntry, "friendfoe", "") == "friend" or sPath == sEntry then
		return false;
	end
	local sField = sPath:sub(#sEntry + 2):match("^([^%.]+)") or "";
	sField = sField:lower();
	for _, sPat in ipairs(tFoeFields) do
		if sField:match(sPat) then
			return true;
		end
	end
	return false;
end

local function nodeToTable(node, nDepth, tBudget)
	local tOut = {};
	for sName, nodeChild in pairs(DB.getChildren(node)) do
		if tBudget.n <= 0 then
			tOut["..."] = "truncated";
			break;
		end
		-- tBudget.user: a player's question; leave out what their table hides.
		if not (tBudget.user and hiddenFromPlayer(nodeChild, tBudget.user)) then
			tBudget.n = tBudget.n - 1;
			local sType = DB.getType(nodeChild);
			if sType == "node" then
				if nDepth > 1 then
					tOut[sName] = nodeToTable(nodeChild, nDepth - 1, tBudget);
				else
					tOut[sName] = { ["$children"] = DB.getChildCount(nodeChild) };
				end
			elseif sType == "number" or sType == "string" or sType == "formattedtext" then
				tOut[sName] = DB.getValue(nodeChild);
			elseif sType == "dice" then
				tOut[sName] = { ["$dice"] = DiceManager.convertDiceToString(DB.getValue(nodeChild) or {}) };
			elseif sType == "windowreference" then
				local sClass, sRecord = DB.getValue(nodeChild);
				tOut[sName] = { ["$link"] = { class = sClass or "", record = sRecord or "" } };
			else
				tOut[sName] = { ["$type"] = tostring(sType) };
			end
		end
	end
	return tOut;
end

local tCommands = {};

-- Handles: with keep=true a call's tables, nodes and other non-JSON values
-- stay inside FGU; the reply lists their ids for {"$handle": id} arguments.
local function describeValue(v)
	local sType = type(v);
	if sType == "databasenode" or sType == "userdata" then
		local bOK, sPath = pcall(DB.getPath, v);
		if bOK and sPath then
			return "node " .. sPath;
		end
	elseif sType == "table" then
		local n = 0;
		for _ in pairs(v) do n = n + 1; end
		return "table (" .. n .. " fields)";
	end
	return sType;
end

function keepValue(v)
	_nHandle = _nHandle + 1;
	local sID = "h" .. _nHandle;
	_tHandles[sID] = { value = v, kind = describeValue(v), time = os.time() };
	return sID;
end

function keepResult(tResult, a)
	local tOut = { result = tResult };
	if a.keep then
		tOut.handles = {};
		for i = 1, #tResult + 1 do
			local v = tResult[i];
			if v ~= nil and type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" then
				tOut.handles[tostring(i)] = keepValue(v);
			end
		end
	end
	return tOut;
end

function tCommands.ping()
	return {
		version = VERSION,
		ruleset = Session.RulesetName,
		host = Session.IsHost,
		role = getRole(),
		user = Session.UserName,
		campaign_folder = safeCall(File.getCampaignFolder),
		packages = (function()
			local t = {};
			for k, _ in pairs(tPackages) do
				table.insert(t, k);
			end
			table.sort(t);
			return t;
		end)(),
	};
end

function tCommands.db_get(a, tScope)
	local node = DB.findNode(a.path or "");
	if not node then
		return { exists = false };
	end
	local sType = DB.getType(node);
	if sType ~= "node" then
		return { exists = true, type = sType, value = DB.getValue(node) };
	end
	local tBudget = { n = tonumber(a.max) or 500, user = (tScope and tScope.kind == "player") and tScope.user or nil };
	return { exists = true, type = "node", value = nodeToTable(node, tonumber(a.depth) or 2, tBudget) };
end

function tCommands.db_list(a, tScope)
	local node = DB.findNode(a.path or "");
	if not node then
		return { exists = false };
	end
	local sUser = (tScope and tScope.kind == "player") and tScope.user or nil;
	local t = {};
	for sName, nodeChild in pairs(DB.getChildren(node)) do
		if not (sUser and hiddenFromPlayer(nodeChild, sUser)) then
			table.insert(t, { name = sName, type = DB.getType(nodeChild), label = DB.getValue(nodeChild, "name", "") });
		end
	end
	return { exists = true, children = t };
end

-- An existing number, string or formatted-text field keeps its type (FGU
-- refuses a mismatch), and the value is converted to it.
function tCommands.db_set(a)
	local sType = a.type or "string";
	local v = a.value;
	local node = DB.findNode(a.path or "");
	if node then
		local sHave = DB.getType(node);
		if sHave ~= sType and (sHave == "number" or sHave == "string" or sHave == "formattedtext") then
			sType = sHave;
		end
	end
	if sType == "number" then
		local n = tonumber(v);
		if n == nil then
			return { error = tostring(a.path) .. " is a number field; " .. tostring(v) .. " is not a number" };
		end
		v = n;
	elseif sType == "string" or sType == "formattedtext" then
		v = tostring(v == nil and "" or v);
	end
	DB.setValue(a.path, sType, v);
	return { value = DB.getValue(a.path), type = sType };
end

function tCommands.db_delete(a)
	local node = DB.findNode(a.path or "");
	if node then
		DB.deleteNode(node);
	end
	return { deleted = (node ~= nil) };
end

function tCommands.db_create_child(a)
	local nodeParent = DB.createNode(a.path);
	local node;
	if (a.name or "") ~= "" then
		node = DB.createChild(nodeParent, a.name, a.type);
	else
		node = DB.createChild(nodeParent);
	end
	return { path = DB.getPath(node) };
end

--
-- Windows
--

local function findWindow(a)
	local w = Interface.findWindow(a.class or "", a.path or "");
	if not w then
		return nil, "window not open: " .. tostring(a.class) .. " " .. tostring(a.path);
	end
	for _, sName in ipairs(a.sub or {}) do
		local c = w[sName];
		if not c or not c.subwindow then
			return nil, "no subwindow control: " .. tostring(sName);
		end
		w = c.subwindow;
	end
	local function selectListRow(wParent, sControl, nRow)
		if type(sControl) ~= "string" or sControl == "" then
			return nil, "row index requires list_control";
		end
		local cList = wParent[sControl];
		if not cList or type(cList.getWindows) ~= "function" then
			return nil, "not a window list: " .. sControl;
		end
		local bOK, tRows = pcall(cList.getWindows);
		local nIndex = tonumber(nRow);
		if not bOK or type(tRows) ~= "table" or not nIndex or nIndex % 1 ~= 0 or not tRows[nIndex] then
			return nil, "list row index not found: " .. tostring(nRow);
		end
		return tRows[nIndex];
	end
	for _, tStep in ipairs(a.list_path or {}) do
		local wRow, sErr = selectListRow(w, tStep.list_control, tStep.row_index);
		if not wRow then
			return nil, sErr;
		end
		w = wRow;
	end
	if a.row_index ~= nil then
		local wRow, sErr = selectListRow(w, a.list_control, a.row_index);
		if not wRow then
			return nil, sErr;
		end
		w = wRow;
	end
	if (a.row or "") ~= "" then
		local function findRow(wParent, sRowPath, nDepth)
			if not wParent or nDepth > 8 then
				return nil;
			end
			for _, c in ipairs(wParent.getControls()) do
				if c.subwindow then
					local wFound = findRow(c.subwindow, sRowPath, nDepth + 1);
					if wFound then
						return wFound;
					end
				end
				if type(c.getWindows) == "function" then
					local bOK, tRows = pcall(c.getWindows);
					if bOK and type(tRows) == "table" then
						for _, wRow in ipairs(tRows) do
							local node = wRow.getDatabaseNode();
							if node and DB.getPath(node) == sRowPath then
								return wRow;
							end
						local wFound = findRow(wRow, sRowPath, nDepth + 1);
							if wFound then
								return wFound;
							end
						end
					end
				end
			end
		end
		local wRow = findRow(w, a.row, 0);
		if not wRow then
			return nil, "list row not found: " .. a.row;
		end
		w = wRow;
	end
	return w;
end

local function describeControl(c)
	local t = { name = c.getName() };
	local bOK, v = pcall(function() return c.isVisible(); end);
	if bOK then
		t.visible = v;
	end
	bOK, v = pcall(function() return c.getValue(); end);
	if bOK and type(v) ~= "table" and type(v) ~= "userdata" then
		t.value = v;
	end
	if c.subwindow ~= nil then
		t.subwindow = c.subwindow and c.subwindow.getClass() or false;
	end
	if type(c.getWindows) == "function" then
		local bRowsOK, tWindows = pcall(c.getWindows);
		if bRowsOK and type(tWindows) == "table" then
			local tRows = {};
			t.row_count = #tWindows;
			for i, wRow in ipairs(tWindows) do
				if i > 200 then
					break;
				end
				local node = wRow.getDatabaseNode();
				if node then
					table.insert(tRows, { path = DB.getPath(node), class = wRow.getClass() });
				end
			end
			if #tRows > 0 then
				t.rows = tRows;
			end
		end
	end
	return t;
end

function tCommands.window_open(a)
	local w = Interface.openWindow(a.class, a.path or "");
	if not w then
		return { opened = false };
	end
	return { opened = true, class = w.getClass(), path = DB.getPath(w.getDatabaseNode()) };
end

function tCommands.window_close(a)
	local w = Interface.findWindow(a.class or "", a.path or "");
	if w then
		w.close();
	end
	return { closed = (w ~= nil) };
end

function tCommands.window_list()
	local t = {};
	for _, w in ipairs(Interface.getWindows()) do
		local node = w.getDatabaseNode();
		table.insert(t, { class = w.getClass(), path = node and DB.getPath(node) or "" });
	end
	return { windows = t };
end

function tCommands.window_read(a)
	local w, sErr = findWindow(a);
	if not w then
		return { error = sErr };
	end
	local t = {};
	for _, c in ipairs(w.getControls()) do
		table.insert(t, describeControl(c));
	end
	return { class = w.getClass(), controls = t };
end

function tCommands.window_set(a)
	local w, sErr = findWindow(a);
	if not w then
		return { error = sErr };
	end
	local c = w[a.control];
	if not c then
		return { error = "no control: " .. tostring(a.control) };
	end
	c.setValue(a.value);
	return describeControl(c);
end

-- Which of the named functions a window (or one of its controls) defines,
-- without calling any of them (for rulesets whose source cannot be read).
function tCommands.window_has(a)
	local w, sErr = findWindow(a);
	if not w then
		return { error = sErr };
	end
	local target = w;
	if (a.control or "") ~= "" then
		target = w[a.control];
		if not target then
			return { error = "no control: " .. tostring(a.control) };
		end
	end
	local t = {};
	for _, sFn in ipairs(a.fns or {}) do
		local bOK, v = pcall(function() return target[sFn]; end);
		if bOK and v ~= nil then
			t[sFn] = type(v);
		end
	end
	return { has = t };
end

-- Calls a function defined on a control (a.control set) or on the window.
function tCommands.window_call(a)
	local w, sErr = findWindow(a);
	if not w then
		return { error = sErr };
	end
	local target = w;
	if (a.control or "") ~= "" then
		target = w[a.control];
		if not target then
			return { error = "no control: " .. tostring(a.control) };
		end
	end
	local fn = target[a.fn];
	if type(fn) ~= "function" then
		return { error = "no function: " .. tostring(a.fn) };
	end
	local tArgs, n = decodeArgs(a.args);
	return keepResult({ fn(fUnpack(tArgs, 1, n)) }, a);
end

--
-- Package calls and chat
--

function tCommands.call(a)
	local tPackage = tPackages[a.package or ""];
	if not tPackage then
		return { error = "package not registered: " .. tostring(a.package) };
	end
	local fn = tPackage[a.fn or ""];
	if type(fn) ~= "function" then
		return { error = "no function " .. tostring(a.package) .. "." .. tostring(a.fn) };
	end
	local tArgs, n = decodeArgs(a.args);
	return keepResult({ fn(fUnpack(tArgs, 1, n)) }, a);
end

function tCommands.get(a)
	local tPackage = tPackages[a.package or ""];
	if not tPackage then
		return { error = "package not registered: " .. tostring(a.package) };
	end
	-- Package tables can't be listed with pairs() in FGU, so a.fns asks
	-- which of the given names exist (and their type) without calling them.
	if type(a.fns) == "table" then
		local t = {};
		for _, sName in ipairs(a.fns) do
			local bOK, v = pcall(function() return tPackage[sName]; end);
			if bOK and v ~= nil then
				t[sName] = type(v);
			end
		end
		return { has = t };
	end
	local v = tPackage[a.field or ""];
	return { value = v, type = type(v) };
end

function tCommands.chat(a)
	ChatManager.SystemMessage(tostring(a.text or ""));
	return { sent = true };
end

--
-- Handles
--

function tCommands.handles()
	local t = {};
	for sID, h in pairs(_tHandles) do
		table.insert(t, { id = sID, kind = h.kind, age = os.time() - h.time });
	end
	table.sort(t, function(x, y) return (tonumber(x.id:sub(2)) or 0) < (tonumber(y.id:sub(2)) or 0); end);
	return { handles = t };
end

-- a.ids: ids to release; none (or a.all) releases every handle.
function tCommands.release(a)
	local n = 0;
	if type(a.ids) == "table" and #a.ids > 0 and not a.all then
		for _, sID in ipairs(a.ids) do
			if _tHandles[sID] then
				_tHandles[sID] = nil;
				n = n + 1;
			end
		end
	else
		for sID in pairs(_tHandles) do
			_tHandles[sID] = nil;
			n = n + 1;
		end
	end
	return { released = n };
end

-- a.value: kept as a handle (decoded first, so {"$node": path} keeps the node).
function tCommands.keep(a)
	return { handle = keepValue(decodeArg(a.value)) };
end

--
-- Batches: steps run in order in one round trip; a step's arguments can use
-- earlier results with {"$ref": "<step>.<field>..."}. Stops at the first
-- failed step unless continue_on_error. keep=true on a step keeps its values.
--

local MAX_BATCH = 100;

function tCommands.batch(a, tScope)
	local tSteps = a.steps or {};
	if #tSteps > MAX_BATCH then
		return { error = "a batch takes at most " .. MAX_BATCH .. " steps (got " .. #tSteps .. ")" };
	end
	local tOuter = _tBatch;
	local tRaw = {};
	local tOut = {};
	_tBatch = tRaw;
	local nFailed = nil;
	for i, tStep in ipairs(tSteps) do
		local tResult = runOne(tStep.cmd, tStep.args or {}, tScope);
		tRaw[i] = tResult.data;
		table.insert(tOut, tResult);
		if not tResult.ok then
			nFailed = nFailed or i;
			if not a.continue_on_error then
				break;
			end
		end
	end
	_tBatch = tOuter;
	return { steps = tOut, ran = #tOut, of = #tSteps, failed_step = nFailed };
end

--
-- Events. FGU pushes them to the daemon (GET /event); agents read them with
-- fgu_events. Database subscriptions use DB.addHandler, so paths may use FGU's
-- wildcards ("charsheet.*.hp.wounds", "combattracker.list.*").
--

local tEventNames = { update = "onUpdate", childadded = "onChildAdded", childdeleted = "onChildDeleted",
	delete = "onDelete", add = "onAdd", childupdate = "onChildUpdate", integritychange = "onIntegrityChange" };
local _nEventsSent = 0;
local _nEventWindow = 0;
local _nDropped = 0;
-- More than this many events in one second are counted, not sent, so a
-- subscription to something busy cannot swamp FGU with requests.
local MAX_EVENTS_PER_SECOND = 40;

function pushEvent(tEvent)
	if not _bRunning then return; end
	local nNow = os.time();
	if nNow ~= _nEventWindow then
		_nEventWindow = nNow;
		_nEventsSent = 0;
		if _nDropped > 0 then
			post("/event", { channel = getChannel(), instance = _sInstance, type = "dropped", count = _nDropped, time = nNow });
			_nDropped = 0;
			_nEventsSent = 1;
		end
	end
	if _nEventsSent >= MAX_EVENTS_PER_SECOND then
		_nDropped = _nDropped + 1;
		return;
	end
	_nEventsSent = _nEventsSent + 1;
	tEvent.channel = getChannel();
	tEvent.instance = _sInstance;
	tEvent.time = nNow;
	post("/event", tEvent);
end

local function nodePath(v)
	local bOK, sPath = pcall(DB.getPath, v);
	return bOK and sPath or nil;
end

local function valueOf(node)
	local bOK, sType = pcall(DB.getType, node);
	if bOK and (sType == "number" or sType == "string") then
		return DB.getValue(node);
	end
	return nil;
end

-- a.path, a.events (default {"update"}); a.values=true adds the new value of
-- number and string fields to update events.
function tCommands.subscribe(a)
	local sPath = a.path or "";
	if sPath == "" then
		return { error = "path is required" };
	end
	local tSub = { path = sPath, events = {}, handlers = {} };
	local tWanted = {};
	for _, sEvent in ipairs(a.events or { "update" }) do
		local sName = tostring(sEvent or ""):lower();
		if not tEventNames[sName] then
			return { error = "unknown event " .. tostring(sEvent) .. " (update, childadded, childdeleted, childupdate, delete, add, integritychange)" };
		end
		table.insert(tWanted, sName);
	end
	_nSub = _nSub + 1;
	local sID = "s" .. _nSub;
	for _, sName in ipairs(tWanted) do
		local sHandler = tEventNames[sName];
		local fn = function(node, nodeChild)
			local t = { type = "db", sub = sID, event = sName, path = nodePath(node) or sPath };
			if nodeChild and type(nodeChild) ~= "boolean" then
				t.child = nodePath(nodeChild);
			end
			if a.values and sName == "update" then
				t.value = valueOf(node);
			end
			pushEvent(t);
		end;
		DB.addHandler(sPath, sHandler, fn);
		table.insert(tSub.events, sName);
		tSub.handlers[sHandler] = fn;
	end
	_tSubs[sID] = tSub;
	return { id = sID, path = sPath, events = tSub.events };
end

function tCommands.unsubscribe(a)
	local n = 0;
	for sID, tSub in pairs(_tSubs) do
		if a.all or sID == a.id then
			for sHandler, fn in pairs(tSub.handlers) do
				pcall(DB.removeHandler, tSub.path, sHandler, fn);
			end
			_tSubs[sID] = nil;
			n = n + 1;
		end
	end
	return { removed = n };
end

-- Chat messages as events (a.on=false stops). Secret messages (whispers and
-- the GM's private rolls) are left out unless a.private=true.
local _bChatEvents = false;
local _bChatPrivate = false;
function tCommands.chat_events(a)
	_bChatEvents = (a.on ~= false);
	_bChatPrivate = (a.private == true);
	return { chat = _bChatEvents, private = _bChatPrivate };
end

function tCommands.subscriptions()
	local t = {};
	for sID, tSub in pairs(_tSubs) do
		table.insert(t, { id = sID, path = tSub.path, events = tSub.events });
	end
	return { subscriptions = t, chat = _bChatEvents };
end

function onChatReceived(msg)
	if not _bChatEvents or type(msg) ~= "table" then
		return;
	end
	if msg.secret and not _bChatPrivate then
		return;
	end
	local t = { type = "chat", sender = msg.sender or "", text = msg.text or "", mode = msg.mode or "",
		secret = msg.secret and true or false };
	if type(msg.dice) == "table" and #msg.dice > 0 then
		local nTotal = msg.diemodifier or 0;
		for _, d in ipairs(msg.dice) do
			nTotal = nTotal + (tonumber(d.result) or 0);
		end
		t.total = nTotal;
	end
	pushEvent(t);
end

-- Other scripts (the chat assistant) add their own commands here.
function addCommand(sName, fn)
	tCommands[sName] = fn;
end

--
-- Scope. Commands sent for an @ai question carry the asker's scope
-- ({kind = "player"|"gm", user = ...}). Without a scope a command has full
-- access (an agent the GM runs). A player scope reads only what that player
-- could see in their own copy of FGU and changes nothing directly; a GM scope
-- reads anything. Changes in either go through an approved plan (propose).
--

local tReadOnly = { ping = true, db_get = true, db_list = true, handles = true, release = true, keep = true,
	subscriptions = true, window_list = true, window_read = true, window_has = true, get = true };
local tAssistant = { reply = true, propose = true, plan_status = true, queries = true, query_context = true };
local tGMReadFns = { "^get", "^is", "^has", "^find", "^resolve", "^lookup", "^list", "^count", "^convert",
	"^encode", "^decode", "^parse", "^check", "^can", "^describe", "^inspect" };

local function moduleOf(sPath)
	return (sPath or ""):match("@(.+)$");
end

-- What a player sees in their own copy of FGU: what they own, what is public
-- or shared with them, and books the GM lets players open.
function isVisibleTo(sPath, sUser)
	local sModule = moduleOf(sPath);
	if sModule then
		local bOK, tInfo = pcall(Module.getModuleInfo, sModule);
		if not bOK or type(tInfo) ~= "table" then
			return false;
		end
		local sPerm = tostring(tInfo.permission or "");
		return sPerm == "allow" or sPerm == "autoload";
	end
	local node = DB.findNode(sPath or "");
	while node do
		if DB.getOwner(node) == sUser then
			return true;
		end
		local bPub, vPub = pcall(DB.isPublic, node);
		if bPub and vPub then
			return true;
		end
		local bHold, tHolders = pcall(DB.getHolders, node);
		if bHold and type(tHolders) == "table" then
			for _, sHolder in ipairs(tHolders) do
				if sHolder == sUser then
					return true;
				end
			end
		end
		node = DB.getParent(node);
	end
	return false;
end

-- A path the user owns: the node or one above it is owned by them.
function isOwnedBy(sPath, sUser)
	if (sUser or "") == "" or moduleOf(sPath) then
		return false;
	end
	local node = DB.findNode(sPath or "");
	if not node then
		-- Not created yet: check the nearest existing parent.
		local sParent = (sPath or ""):match("^(.+)%.[^%.]+$");
		return sParent and isOwnedBy(sParent, sUser) or false;
	end
	while node do
		if DB.getOwner(node) == sUser then
			return true;
		end
		node = DB.getParent(node);
	end
	return false;
end

local function checkScope(sCmd, a, tScope)
	if not tScope or tAssistant[sCmd] or sCmd == "batch" then
		return nil;
	end
	if tScope.kind == "gm" then
		if tReadOnly[sCmd] or sCmd == "chat_events" or sCmd == "subscribe" or sCmd == "unsubscribe" then
			return nil;
		end
		if sCmd == "call" then
			for _, sPat in ipairs(tGMReadFns) do
				if (a.fn or ""):match(sPat) then
					return nil;
				end
			end
		end
		return "an @ai question cannot change the campaign directly; send the changes with fgu_propose so the GM can approve them";
	end
	-- player
	if sCmd == "db_get" or sCmd == "db_list" then
		local node = DB.findNode(a.path or "");
		if node and hiddenFromPlayer(node, tScope.user) then
			return "hidden from " .. tostring(tScope.user) .. ": " .. tostring(a.path);
		end
		if isVisibleTo(a.path, tScope.user) then
			return nil;
		end
		return "not visible to " .. tostring(tScope.user) .. ": " .. tostring(a.path);
	end
	if sCmd == "ping" or sCmd == "handles" or sCmd == "release" then
		return nil;
	end
	return "a player's @ai question can only read what that player can see; changes to their own character go through fgu_propose";
end

-- Runs one command (a polled command, a batch step or a plan step).
function runOne(sCmd, tArgs, tScope)
	local fn = tCommands[sCmd or ""];
	if not fn then
		return { ok = false, error = "unknown command: " .. tostring(sCmd) };
	end
	local sDenied = checkScope(sCmd, tArgs or {}, tScope);
	if sDenied then
		return { ok = false, error = sDenied, denied = true };
	end
	local bOK, vResult = pcall(fn, tArgs or {}, tScope);
	if not bOK then
		return { ok = false, error = tostring(vResult) };
	end
	if sCmd == "batch" and type(vResult) == "table" and vResult.failed_step then
		return { ok = false, error = "step " .. vResult.failed_step .. " failed", data = vResult };
	end
	-- Commands report problems as { error = ... } (window not open, no such
	-- function...): that is a failure, so a batch or plan stops there.
	if type(vResult) == "table" and type(vResult.error) == "string" then
		return { ok = false, error = vResult.error, data = vResult };
	end
	return { ok = true, data = vResult };
end

function runCommand(tCommand)
	local tScope = tCommand.scope;
	if type(tScope) ~= "table" or (tScope.kind ~= "player" and tScope.kind ~= "gm") then
		tScope = nil;
	end
	return runOne(tCommand.cmd, tCommand.args or {}, tScope);
end
