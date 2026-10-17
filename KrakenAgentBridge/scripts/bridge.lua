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

local VERSION = "1.0.3";
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
		ChatManager.registerReceiveMessageCallback(nudge);
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
		TableManager = TableManager,
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
		AgentBridge = AgentBridge, ClaudeBridge = ClaudeBridge,
	};
	for k, v in pairs(t) do
		registerPackage(k, v);
	end
end

function onSlash()
	start();
	ChatManager.SystemMessage("Agent bridge: reconnecting to local server.");
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
--

local function decodeArg(v)
	if type(v) ~= "table" then
		return v;
	end
	if v["$node"] then
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

local function nodeToTable(node, nDepth, tBudget)
	local tOut = {};
	for sName, nodeChild in pairs(DB.getChildren(node)) do
		if tBudget.n <= 0 then
			tOut["..."] = "truncated";
			break;
		end
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
	return tOut;
end

local tCommands = {};

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

function tCommands.db_get(a)
	local node = DB.findNode(a.path or "");
	if not node then
		return { exists = false };
	end
	local sType = DB.getType(node);
	if sType ~= "node" then
		return { exists = true, type = sType, value = DB.getValue(node) };
	end
	local tBudget = { n = tonumber(a.max) or 500 };
	return { exists = true, type = "node", value = nodeToTable(node, tonumber(a.depth) or 2, tBudget) };
end

function tCommands.db_list(a)
	local node = DB.findNode(a.path or "");
	if not node then
		return { exists = false };
	end
	local t = {};
	for sName, nodeChild in pairs(DB.getChildren(node)) do
		table.insert(t, { name = sName, type = DB.getType(nodeChild), label = DB.getValue(nodeChild, "name", "") });
	end
	return { exists = true, children = t };
end

function tCommands.db_set(a)
	DB.setValue(a.path, a.type or "string", a.value);
	return { value = DB.getValue(a.path) };
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
	return { result = { fn(fUnpack(tArgs, 1, n)) } };
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
	return { result = { fn(fUnpack(tArgs, 1, n)) } };
end

function tCommands.get(a)
	local tPackage = tPackages[a.package or ""];
	if not tPackage then
		return { error = "package not registered: " .. tostring(a.package) };
	end
	return { value = tPackage[a.field or ""] };
end

function tCommands.chat(a)
	ChatManager.SystemMessage(tostring(a.text or ""));
	return { sent = true };
end

function runCommand(tCommand)
	local fn = tCommands[tCommand.cmd or ""];
	if not fn then
		return { ok = false, error = "unknown command: " .. tostring(tCommand.cmd) };
	end
	local bOK, vResult = pcall(fn, tCommand.args or {});
	if not bOK then
		return { ok = false, error = tostring(vResult) };
	end
	return { ok = true, data = vResult };
end
