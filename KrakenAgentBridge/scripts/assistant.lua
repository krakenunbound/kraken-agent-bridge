-- Kraken Agent Bridge: the chat assistant. Anyone at the table types
--   @ai <question>   (the question shows in chat; the answer is whispered to
--                     the asker and the GM)
--   /ai <question>   (private: nothing shows in chat; same answer routing)
-- The question goes to the GM's copy, which hands it to the agent listener
-- (fgu_listener.py) as an event. The agent reads what the asker is allowed
-- to see, answers with fgu_reply, and sends any changes as one plan
-- (fgu_propose) that the asker (their own character) or the GM approves in
-- a Yes/No window before anything changes.
--
-- GM commands: /ai public [n] (repeat answer n, or the last one, to
-- everyone), /ai send [n] (pass an answer held for the GM on to the asker),
-- /ai list, /agentbridge permissions reset.

local OOB_QUERY = "kab_query";
local OOB_ASK = "kab_plan_ask";
local OOB_ANSWER = "kab_plan_answer";
local MAX_PLAN = 50;

local _tQueries = {};
local _nQuery = 0;
local _sLastAnswered = nil;
local _tPlans = {};
local _nPlan = 0;
-- Plans waiting for this copy's Yes/No window, oldest first.
local _tAskQueue = {};
local _tShowing = nil;

function onInit()
	Comm.registerSlashHandler("ai", onSlashAI, "[question] - ask the AI privately | public [n] | send [n] | list");
	if ChatManager and ChatManager.registerDeliverMessageCallback then
		ChatManager.registerDeliverMessageCallback(onDeliverMessage);
	end
	OOBManager.registerOOBMsgHandler(OOB_QUERY, onQueryOOB);
	OOBManager.registerOOBMsgHandler(OOB_ASK, onAskOOB);
	OOBManager.registerOOBMsgHandler(OOB_ANSWER, onAnswerOOB);
	AgentBridge.addCommand("queries", cmdQueries);
	AgentBridge.addCommand("query_context", cmdQueryContext);
	AgentBridge.addCommand("reply", cmdReply);
	AgentBridge.addCommand("propose", cmdPropose);
	AgentBridge.addCommand("plan_status", cmdPlanStatus);
end

--
-- Asking
--

-- "@ai what does prone do?" (also "@AI:", "@ai,"). Returns the question.
local function matchAt(sText)
	local s = (sText or ""):match("^%s*@[aA][iI][%s:,]+(.*)$");
	if s and StringManager.trim(s) ~= "" then
		return StringManager.trim(s);
	end
	return nil;
end

function onDeliverMessage(msg)
	if type(msg) ~= "table" or (msg.type or "") ~= "" then
		return;
	end
	local sQuestion = matchAt(msg.text);
	if sQuestion then
		submit(sQuestion, false, msg.sActorNode);
	end
	-- The question itself still goes to chat as normal.
end

function onSlashAI(_, sParams)
	local sParams = StringManager.trim(sParams or "");
	local sWord, sRest = sParams:match("^(%S+)%s*(.*)$");
	sWord = (sWord or ""):lower();
	if Session.IsHost and (sWord == "public" or sWord == "send") and (sRest == "" or sRest:match("^%d+$")) then
		forward(sWord, sRest);
		return;
	end
	if Session.IsHost and sWord == "list" and sRest == "" then
		ChatManager.SystemMessage(statusText(true));
		return;
	end
	if sParams == "" then
		ChatManager.SystemMessage("Usage: /ai [question] (private) or @ai [question] in chat. GM: /ai public [n], /ai send [n], /ai list.");
		return;
	end
	ChatManager.SystemMessage("You asked the AI (private): " .. sParams);
	local sActor = nil;
	if not Session.IsHost and User.getCurrentIdentity then
		local sIdentity = User.getCurrentIdentity();
		if (sIdentity or "") ~= "" then
			sActor = "charsheet." .. sIdentity;
		end
	end
	submit(sParams, true, sActor);
end

function submit(sQuestion, bPrivate, sActor)
	if Session.IsHost then
		addQuery(Session.UserName, sQuestion, bPrivate, sActor, true);
	else
		Comm.deliverOOBMessage({ type = OOB_QUERY, user = Session.UserName, text = sQuestion,
			private = bPrivate and "1" or "", actor = sActor or "" }, "");
	end
end

function onQueryOOB(msg)
	if not Session.IsHost then
		return;
	end
	addQuery(msg.user or "", msg.text or "", msg.private == "1", (msg.actor or "") ~= "" and msg.actor or nil, false);
end

function addQuery(sUser, sQuestion, bPrivate, sActor, bGM)
	_nQuery = _nQuery + 1;
	local sID = tostring(_nQuery) .. "-" .. tostring(os.time());
	-- A player's actor must be one of their own characters.
	if not bGM and sActor and not AgentBridge.isOwnedBy(sActor, sUser) then
		sActor = nil;
	end
	local tQuery = { id = sID, n = _nQuery, user = sUser, kind = bGM and "gm" or "player", text = sQuestion,
		private = bPrivate, actor = sActor, time = os.time(), status = "new" };
	_tQueries[sID] = tQuery;
	AgentBridge.pushEvent({ type = "query", id = sID, n = _nQuery, user = sUser, kind = tQuery.kind,
		text = sQuestion, private = bPrivate, actor = sActor });
	if not bGM and bPrivate then
		ChatManager.SystemMessage("AI question " .. _nQuery .. " from " .. sUser .. " (private): " .. sQuestion);
	end
end

--
-- Answering
--

local function sendAI(sText, vTo)
	local msg = { font = "systemfont", sender = "AI", text = sText };
	if vTo == "all" then
		Comm.deliverChatMessage(msg);
	elseif vTo == "gm" then
		Comm.addChatMessage(msg);
	else
		Comm.addChatMessage(msg);
		if (vTo or "") ~= "" then
			Comm.deliverChatMessage(msg, vTo);
		end
	end
end

local function findQuery(v)
	if v == nil or v == "" then
		return _tQueries[_sLastAnswered or ""];
	end
	if _tQueries[v] then
		return _tQueries[v];
	end
	for _, q in pairs(_tQueries) do
		if tostring(q.n) == tostring(v) then
			return q;
		end
	end
	return nil;
end

function forward(sHow, sN)
	local q = findQuery(sN);
	if not q or not q.answer then
		ChatManager.SystemMessage("No AI answer " .. (sN ~= "" and sN or "yet") .. ".");
		return;
	end
	if sHow == "public" then
		sendAI(q.answer, "all");
		q.status = "public";
	else
		if q.kind == "gm" then
			ChatManager.SystemMessage("Answer " .. q.n .. " was for you.");
			return;
		end
		Comm.deliverChatMessage({ font = "systemfont", sender = "AI", text = q.answer }, q.user);
		ChatManager.SystemMessage("Answer " .. q.n .. " sent to " .. q.user .. ".");
		q.status = "answered";
	end
end

function statusText(bList)
	local nOpen, nAll = 0, 0;
	local tLines = {};
	for _, q in pairs(_tQueries) do
		nAll = nAll + 1;
		if q.status == "new" then
			nOpen = nOpen + 1;
		end
		if bList then
			table.insert(tLines, { n = q.n, s = string.format("%d. %s (%s%s): %s", q.n, q.user, q.status,
				q.private and ", private" or "", q.text) });
		end
	end
	local nPlans = 0;
	for _, p in pairs(_tPlans) do
		if p.status == "waiting" then
			nPlans = nPlans + 1;
		end
	end
	local s = string.format("AI questions: %d, %d unanswered; plans waiting for approval: %d.", nAll, nOpen, nPlans);
	if bList then
		table.sort(tLines, function(a, b) return a.n < b.n; end);
		for _, t in ipairs(tLines) do
			s = s .. "\r" .. t.s;
		end
	end
	return s;
end

local function queryOut(q)
	return { id = q.id, n = q.n, user = q.user, kind = q.kind, text = q.text, private = q.private,
		actor = q.actor, status = q.status, answer = q.answer, age = os.time() - q.time };
end

-- a.status: only queries with this status ("new" for unanswered).
function cmdQueries(a)
	local t = {};
	for _, q in pairs(_tQueries) do
		if (a.status or "") == "" or q.status == a.status then
			table.insert(t, queryOut(q));
		end
	end
	table.sort(t, function(x, y) return x.n < y.n; end);
	return { queries = t };
end

-- Who asked and what they may see: their characters, the books they can
-- open, and whether the question was private.
function cmdQueryContext(a)
	local q = findQuery(a.id);
	if not q then
		return { error = "no query " .. tostring(a.id) };
	end
	local tChars = {};
	for _, node in pairs(DB.getChildren("charsheet")) do
		local sOwner = DB.getOwner(node);
		if q.kind == "gm" or sOwner == q.user then
			table.insert(tChars, { path = DB.getPath(node), name = DB.getValue(node, "name", ""), owner = sOwner });
		end
	end
	local tBooks = {};
	for _, sModule in ipairs(Module.getModules()) do
		local tInfo = Module.getModuleInfo(sModule);
		if tInfo and tInfo.loaded then
			local sPerm = tostring(tInfo.permission or "");
			if q.kind == "gm" or sPerm == "allow" or sPerm == "autoload" then
				table.insert(tBooks, { name = sModule, title = tInfo.displayname, players = sPerm });
			end
		end
	end
	return { query = queryOut(q), characters = tChars, modules = tBooks, ruleset = Session.RulesetName,
		rules = (q.kind == "player") and "Read only what this player can see (the bridge enforces it). Answer with fgu_reply. Changes to their own character go in one fgu_propose plan; they approve it."
			or "Full read access. Answer with fgu_reply. Any change goes in one fgu_propose plan for the GM to approve." };
end

-- a.id (query, default: the newest unanswered), a.text, a.public (everyone
-- sees it), a.gm_only (held for the GM: spoilers or anything the asker should
-- not see; the GM can pass it on with /ai send).
function cmdReply(a, tScope)
	local q = findQuery(a.id);
	if not q and (a.id or "") == "" then
		local nBest = nil;
		for _, v in pairs(_tQueries) do
			if v.status == "new" and (not nBest or v.n > nBest.n) then
				nBest = v;
			end
		end
		q = nBest;
	end
	local sText = tostring(a.text or "");
	if sText == "" then
		return { error = "text is required" };
	end
	if not q then
		sendAI(sText, "gm");
		return { sent = "gm" };
	end
	if tScope and tScope.query and tostring(tScope.query) ~= q.id then
		return { error = "this agent run answers query " .. tostring(tScope.query) .. " only" };
	end
	q.answer = sText;
	_sLastAnswered = q.id;
	local sTo;
	if a.gm_only then
		sendAI("[for the GM; /ai send " .. q.n .. " passes it on, /ai public " .. q.n .. " shows everyone] " .. sText, "gm");
		q.status = "held";
		sTo = "gm";
	elseif a.public then
		sendAI(sText, "all");
		q.status = "public";
		sTo = "all";
	else
		sendAI(sText, q.kind == "gm" and "gm" or q.user);
		q.status = "answered";
		sTo = q.kind == "gm" and "gm" or ("gm and " .. q.user);
	end
	AgentBridge.pushEvent({ type = "answered", id = q.id, to = sTo });
	return { sent = sTo, query = q.id, n = q.n };
end

--
-- Plans: every change an @ai question makes goes in one plan the approver
-- sees in full (up to 50 steps), then runs in order. A step is
-- {cmd = "db_set"|"db_create_child"|"db_delete"|"call"|"window_set"|..., args = {...},
--  summary = "what it does, in words"}.
--

local tPlayerCmds = { db_set = true, db_create_child = true, db_delete = true, call = true };

local function argPaths(v, t)
	if type(v) == "table" then
		if v["$node"] then
			table.insert(t, v["$node"]);
		elseif v["$actor"] then
			table.insert(t, v["$actor"]);
		else
			for _, vItem in pairs(v) do
				argPaths(vItem, t);
			end
		end
	elseif type(v) == "string" and v:find("%.") and DB.findNode(v) then
		table.insert(t, v);
	end
	return t;
end

-- Why a player may not run this step, or nil.
local function playerStepProblem(tStep, sUser)
	if not tPlayerCmds[tStep.cmd or ""] then
		return "a player's plan can only change their own character's records";
	end
	if tStep.cmd == "call" then
		local a = tStep.args or {};
		if a.package == "DB" or a.package == "Interface" or a.package == "Comm" or a.package == "File" then
			return "use db_set/db_create_child/db_delete for record changes";
		end
		local tPaths = argPaths(a.args, {});
		if #tPaths == 0 then
			return "a call in a player's plan must name their character's records ($node or $actor)";
		end
		for _, sPath in ipairs(tPaths) do
			if not AgentBridge.isOwnedBy(sPath, sUser) then
				return "not " .. sUser .. "'s: " .. sPath;
			end
		end
		return nil;
	end
	local sPath = (tStep.args or {}).path or "";
	if not AgentBridge.isOwnedBy(sPath, sUser) then
		return "not " .. sUser .. "'s: " .. sPath;
	end
	return nil;
end

-- "db_set:charsheet", "call:EffectManager.addEffect": the kind of change a
-- remembered Yes/No covers.
local function stepCategory(tStep)
	local a = tStep.args or {};
	if tStep.cmd == "call" then
		return "call:" .. tostring(a.package) .. "." .. tostring(a.fn);
	end
	local sRoot = tostring(a.path or a.class or ""):match("^([^%.@]+)") or "";
	return tostring(tStep.cmd) .. ":" .. sRoot;
end

local function decisions()
	if not CampaignRegistry then
		return {};
	end
	CampaignRegistry.kab_decisions = CampaignRegistry.kab_decisions or {};
	return CampaignRegistry.kab_decisions;
end

function resetDecisions()
	if CampaignRegistry then
		CampaignRegistry.kab_decisions = {};
	end
	ChatManager.SystemMessage("Agent bridge: saved AI Yes/No decisions cleared for this campaign.");
end

local function decisionKey(p, tStep)
	return (p.user or "") .. "|" .. stepCategory(tStep);
end

local function planText(p)
	local tLines = {};
	table.insert(tLines, p.title ~= "" and p.title or "Changes the AI wants to make");
	if p.question then
		table.insert(tLines, "For: " .. p.who .. ": \"" .. p.question .. "\"");
	end
	table.insert(tLines, "");
	for i, tStep in ipairs(p.steps) do
		local a = tStep.args or {};
		local sTarget = a.path or (a.package and (a.package .. "." .. tostring(a.fn))) or a.class or "";
		table.insert(tLines, string.format("%d. %s", i, tStep.summary or tStep.cmd));
		table.insert(tLines, "    " .. tostring(tStep.cmd) .. " " .. tostring(sTarget));
	end
	table.insert(tLines, "");
	table.insert(tLines, "Yes runs every step in order. Always / Never also remember the answer for these kinds of change.");
	return table.concat(tLines, "\n");
end

-- a.query, a.title, a.steps. Returns the plan id and its status: "waiting"
-- (window shown), "executed"/"failed" (remembered Yes), "denied".
function cmdPropose(a, tScope)
	local tSteps = a.steps or a.changes or {};
	if #tSteps == 0 then
		return { error = "a plan needs steps" };
	end
	if #tSteps > MAX_PLAN then
		return { error = "a plan takes at most " .. MAX_PLAN .. " steps; split the work" };
	end
	local q = findQuery(a.query or (tScope and tScope.query));
	local sUser = (tScope and tScope.kind == "player") and tScope.user or nil;
	if sUser then
		for i, tStep in ipairs(tSteps) do
			local sProblem = playerStepProblem(tStep, sUser);
			if sProblem then
				return { error = "step " .. i .. ": " .. sProblem .. ". Nothing was proposed. Propose again with only the steps on "
					.. sUser .. "'s own records, and tell them the rest is the GM's call." };
			end
		end
	end
	_nPlan = _nPlan + 1;
	local p = { id = "p" .. _nPlan, title = tostring(a.title or ""), steps = tSteps, user = sUser,
		who = q and q.user or (sUser or Session.UserName), question = q and q.text or nil,
		query = q and q.id or nil, status = "waiting", time = os.time() };
	_tPlans[p.id] = p;

	-- Remembered answers: any No denies, all Yes approves.
	local tSaved = decisions();
	local bAllYes = true;
	for _, tStep in ipairs(tSteps) do
		local v = tSaved[decisionKey(p, tStep)];
		if v == "no" then
			p.status = "denied";
			p.reason = "remembered No for " .. stepCategory(tStep);
			return planOut(p);
		elseif v ~= "yes" then
			bAllYes = false;
		end
	end
	if bAllYes then
		executePlan(p, "remembered Yes");
		return planOut(p);
	end

	-- The asking player approves changes to their own character on their
	-- own copy when they are connected; otherwise, and for everything else, the GM.
	local bPlayerOnline = false;
	if sUser then
		for _, sActive in ipairs(User.getActiveUsers()) do
			if sActive == sUser then
				bPlayerOnline = true;
			end
		end
	end
	if sUser and bPlayerOnline then
		p.approver = sUser;
		Comm.deliverOOBMessage({ type = OOB_ASK, plan = p.id, text = planText(p) }, sUser);
	else
		p.approver = "GM";
		showAsk({ plan = p.id, text = planText(p), local_host = true });
	end
	return planOut(p);
end

function planOut(p)
	return { plan = p.id, status = p.status, approver = p.approver, reason = p.reason, results = p.results,
		failed_step = p.failed_step };
end

function cmdPlanStatus(a)
	local p = _tPlans[a.plan or ""];
	if not p then
		return { error = "no plan " .. tostring(a.plan) };
	end
	return planOut(p);
end

function executePlan(p, sWhy)
	p.status = "running";
	p.reason = sWhy;
	p.results = {};
	for i, tStep in ipairs(p.steps) do
		-- Check again: the character may have changed hands since the plan was made.
		if p.user then
			local sProblem = playerStepProblem(tStep, p.user);
			if sProblem then
				table.insert(p.results, { ok = false, error = sProblem });
				p.failed_step = i;
				break;
			end
		end
		local tResult = AgentBridge.runOne(tStep.cmd, tStep.args or {}, nil);
		table.insert(p.results, tResult);
		if not tResult.ok then
			p.failed_step = i;
			break;
		end
	end
	p.status = p.failed_step and "failed" or "executed";
	local sMsg;
	if p.failed_step == 1 then
		sMsg = "AI plan " .. p.id .. ": step 1 failed, so nothing was changed.";
	elseif p.failed_step then
		sMsg = "AI plan " .. p.id .. ": step " .. p.failed_step .. " failed; steps 1 to " .. (p.failed_step - 1) .. " were applied.";
	else
		sMsg = "AI plan " .. p.id .. ": " .. #p.steps .. " change(s) applied.";
	end
	if p.failed_step and p.results[p.failed_step] then
		sMsg = sMsg .. " (" .. tostring(p.results[p.failed_step].error) .. ")";
	end
	ChatManager.SystemMessage(sMsg);
	if p.user then
		Comm.deliverChatMessage({ font = "systemfont", sender = "AI", text = sMsg }, p.user);
	end
	AgentBridge.pushEvent({ type = "plan", plan = p.id, status = p.status, failed_step = p.failed_step });
end

-- sAnswer: "yes", "no", "always", "never"; sFrom: the answering user (nil = GM).
function resolvePlan(sPlan, sAnswer, sFrom)
	local p = _tPlans[sPlan or ""];
	if not p or p.status ~= "waiting" then
		return;
	end
	if sFrom and sFrom ~= p.approver then
		return;
	end
	if sAnswer == "always" or sAnswer == "never" then
		local tSaved = decisions();
		for _, tStep in ipairs(p.steps) do
			tSaved[decisionKey(p, tStep)] = (sAnswer == "always") and "yes" or "no";
		end
	end
	if sAnswer == "yes" or sAnswer == "always" then
		executePlan(p, "approved by " .. (sFrom or "the GM"));
	else
		p.status = "denied";
		p.reason = "denied by " .. (sFrom or "the GM");
		AgentBridge.pushEvent({ type = "plan", plan = p.id, status = p.status });
	end
end

function onAnswerOOB(msg)
	if Session.IsHost then
		resolvePlan(msg.plan, msg.answer, msg.user or "");
	end
end

--
-- The Yes/No window (on whichever copy approves)
--

function onAskOOB(msg)
	if not Session.IsHost then
		showAsk({ plan = msg.plan, text = msg.text });
	end
end

function showAsk(t)
	table.insert(_tAskQueue, t);
	if not _tShowing then
		showNext();
	end
end

function showNext()
	_tShowing = table.remove(_tAskQueue, 1);
	if not _tShowing then
		return;
	end
	local w = Interface.openWindow("kab_approval", "");
	if w then
		w.plan.setValue(_tShowing.text or "");
		local nLeft = #_tAskQueue;
		w.title.setValue("AI wants to make changes" .. (nLeft > 0 and (" (" .. nLeft .. " more waiting)") or ""));
	end
end

-- Called by the window's buttons.
function answerShown(sAnswer)
	local t = _tShowing;
	_tShowing = nil;
	if t then
		if Session.IsHost then
			resolvePlan(t.plan, sAnswer, nil);
		else
			Comm.deliverOOBMessage({ type = OOB_ANSWER, plan = t.plan, answer = sAnswer, user = Session.UserName }, "");
		end
	end
	local w = Interface.findWindow("kab_approval", "");
	if w then
		pcall(w.close);
	end
	showNext();
end

-- The window was closed without an answer: that is a No.
function onApprovalClosed()
	if _tShowing then
		answerShown("no");
	end
end
