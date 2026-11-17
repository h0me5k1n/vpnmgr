'use strict';

var assert = require('assert');
var fs = require('fs');
var vm = require('vm');

var jqueryState = {ajax:null,text:{},shown:{},properties:{}};
var consoleSnapshots = [];
var consoleLevels = [];
var loadingState = {showArguments:[],hideCalls:0,visible:false};
var domNodes = {};
function fakeNode(tagName,id){
	var node = {tagName:String(tagName || 'div').toUpperCase(),id:id || '',style:{},children:[],parentNode:null,textContent:'',appendChild:function(child){
		if(child.parentNode && child.parentNode.removeChild) child.parentNode.removeChild(child);
		this.children.push(child); child.parentNode = this; return child;
	},removeChild:function(child){
		var index = this.children.indexOf(child); if(index != -1) this.children.splice(index,1); child.parentNode = null; return child;
	}};
	if(node.id) domNodes[node.id] = node;
	if(node.tagName == 'TABLE') node.insertRow = function(){
		var row = fakeNode('tr'); row.insertCell = function(){ return this.appendChild(fakeNode('td')); };
		this.appendChild(row); return row;
	};
	return node;
}
var htmlNode = fakeNode('html','html');
var bodyNode = fakeNode('body','body');
var recoveryHome = fakeNode('div','vpnmgr_recovery_placeholder');
var recoveryControls = fakeNode('div','vpnmgr_recovery_controls'); recoveryHome.appendChild(recoveryControls);
var recoveryNotice = fakeNode('span','vpnmgr_recovery_notice'); recoveryControls.appendChild(recoveryNotice);
var continueButton = fakeNode('button','btnContinueApply'); recoveryControls.appendChild(continueButton);
var reloadButton = fakeNode('button','btnReloadSettings'); recoveryControls.appendChild(reloadButton);
var loadingTable = fakeNode('table','loadingBlock');
var proceedingMain = fakeNode('span','proceeding_main_txt');
var proceedingDetail = fakeNode('span','proceeding_txt');
var loadingMask = fakeNode('div','Loading');
bodyNode.appendChild(recoveryHome);
function jQueryStub(selector){
	return {
		prop:function(name,value){ jqueryState.properties[String(selector)+':'+name] = value; return this; },
		text:function(value){ jqueryState.text[String(selector)] = value; var node = domNodes[String(selector).replace(/^#/,'')]; if(node) node.textContent = value; return this; },
		hide:function(){ jqueryState.shown[String(selector)] = false; var node = domNodes[String(selector).replace(/^#/,'')]; if(node) node.style.display = 'none'; return this; },
		show:function(){ jqueryState.shown[String(selector)] = true; var node = domNodes[String(selector).replace(/^#/,'')]; if(node) node.style.display = ''; return this; },
		serializeArray:function(){
			if(selector === context.document.formScriptActions) return context.document.formScriptActions.fields || [];
			return [];
		},
		val:function(){ return ''; },
		addClass:function(){ return this; },
		removeClass:function(){ return this; },
		html:function(value){ jqueryState.text[String(selector)] = value; return this; }
	};
}
jQueryStub.fn = {};
jQueryStub.ajax = function(options){
	if(jqueryState.ajax) return jqueryState.ajax(options);
	throw new Error('Unexpected AJAX request: '+options.url);
};
jQueryStub.each = function(items,callback){
	for(var i=0; i<items.length; i++) callback(i,items[i]);
};

var formElements = [];
var context = {
	jQuery:jQueryStub,
	document:{form:{elements:formElements},formScriptActions:{elements:[],fields:[{name:'productid',value:'router'},{name:'action_script',value:''}]},documentElement:htmlNode,body:bodyNode,createElement:function(tag){return fakeNode(tag);},getElementById:function(id){return domNodes[id] || null;},getElementsByTagName:function(){return []; }},
	window:{location:{pathname:'/vpnmgr.asp'},pageXOffset:17,pageYOffset:29,scrollTo:function(x,y){context.lastScroll=[x,y];}},
	location:{reload:function(){context.reloadCount=(context.reloadCount || 0)+1;}},
	setTimeout:function(callback,delay){ context.queuedTimer = callback; context.queuedDelay = delay; return 1; },
	clearTimeout:function(){},
	alert:function(message){ context.lastAlert = message; },
	console:{log:function(prefix,snapshot){consoleLevels.push('log');consoleSnapshots.push(JSON.parse(snapshot));},info:function(prefix,snapshot){consoleLevels.push('info');consoleSnapshots.push(JSON.parse(snapshot));},error:function(prefix,snapshot){consoleLevels.push('error');consoleSnapshots.push(JSON.parse(snapshot));}},
	showLoading:function(){loadingState.showArguments.push(arguments.length);loadingState.visible=true;loadingMask.style.display='block';loadingMask.style.visibility='visible';htmlNode.style.overflow='hidden';proceedingMain.textContent='Please wait,';},
	hideLoading:function(){loadingState.hideCalls++;loadingState.visible=false;loadingMask.style.display='none';loadingMask.style.visibility='hidden';htmlNode.style.overflow='';},
	show_menu:function(){},
	showhide:function(){},
	custom_settings:{vpnmgr_version_local:'test-version',vpnmgr_version_server:'test-server',unrelated_setting:'keep-me'},
	providerCountries:{},
	vpnmgr_providers:[],
	Math:Math,
	Date:Date
};
vm.createContext(context);
vm.runInContext(fs.readFileSync('vpnmgr_www.js','utf8'),context,{filename:'vpnmgr_www.js'});

function addElement(name,value,type,checked,disabled){
	var item = {name:name,value:value,type:type || 'text',checked:!!checked,disabled:!!disabled};
	formElements.push(item);
	return item;
}

function applyResponse(request,state,merged,statuses){
	var clients = [];
	for(var i=1; i<=5; i++) clients.push({slot:i,status:statuses && statuses[i-1] || 'applied',connection:statuses && statuses[i-1] == 'unmanaged' ? 'not_requested' : 'connected'});
	return {request:request,state:state,merged:merged,clients:clients,message:state == 'done' ? 'complete' : state == 'running' ? 'running' : 'expired'};
}

function testRequestIdsAndRuntimeContract(){
	var first = context.NewRuntimeRequestId();
	var second = context.NewRuntimeRequestId();
	assert.match(first,/^\d{19}$/);
	assert.match(second,/^\d{19}$/);
	assert.notStrictEqual(first,second);

	context.vpnmgr_configState = 'loaded';
	context.vpnmgr_initComplete = true;
	var runtimePost;
	var detectionRequest;
	jqueryState.ajax = function(options){ if(options.url == '/start_apply.htm') runtimePost = options; else detectionRequest = options; };
	context.DetectRuntime();
	assert.strictEqual(runtimePost.url,'/start_apply.htm');
	assert.strictEqual(runtimePost.type,'POST');
	assert.strictEqual(runtimePost.dataType,'text','firmware JavaScript responses must not execute');
	assert.strictEqual(runtimePost.data.filter(function(field){return field.name == 'action_script';})[0].value,'start_vpnmgrruntime_'+context.vpnmgr_lastRequestId);
	assert.strictEqual(runtimePost.data.filter(function(field){return field.name == 'amng_custom';}).length,0,'runtime control post must not merge settings');
	runtimePost.success('redirect response text must remain inert');
	assert.strictEqual(detectionRequest,undefined,'runtime status is not read immediately after posting its event');
	assert.strictEqual(context.queuedDelay,2000,'the first runtime status read waits for the normal poll interval');
	context.queuedTimer();
	assert.strictEqual(detectionRequest.url,'/ext/vpnmgr/runtime/detection_'+context.vpnmgr_lastRequestId+'.json');
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'2.6.12',number:'261200',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'known');
	assert.ok(jqueryState.text['#vpnmgr_runtime_status'].indexOf('modern') != -1);

	context.DetectRuntime();
	runtimePost.success('');
	context.queuedTimer();
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'',number:'',family:'legacy',status:'unknown'});
	assert.strictEqual(context.vpnmgr_runtimeState,'unknown');
	assert.ok(jqueryState.text['#vpnmgr_runtime_status'].indexOf('legacy fallback') != -1);

	context.DetectRuntime();
	runtimePost.success('');
	context.queuedTimer();
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'',number:'',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'failed');
	context.DetectRuntime();
	runtimePost.success('');
	context.queuedTimer();
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'2.6.12',number:'261200',family:'modern',status:'unknown'});
	assert.strictEqual(context.vpnmgr_runtimeState,'failed','unknown runtime status must explicitly use the legacy family');
	context.DetectRuntime();
	runtimePost.error();
	assert.strictEqual(context.vpnmgr_runtimeState,'loading','a transport error still polls the event status');
	assert.strictEqual(jqueryState.properties['#btnSaveConfig:disabled'],true);
	assert.strictEqual(context.queuedDelay,2000,'a lost control acknowledgement also observes the first-poll delay');
	context.queuedTimer();
	assert.strictEqual(detectionRequest.url.indexOf('/ext/vpnmgr/runtime/detection_'),0,'polling continues after a lost acknowledgement');
}

function testRuntime404RetryAndCorrelation(){
	var logStart = consoleSnapshots.length;
	var calls = [];
	var detectionCount = 0;
	var runtimePost;
	var matchingId;
	jqueryState.ajax = function(options){
		calls.push(options);
		if(options.url == '/start_apply.htm') runtimePost = options;
		else{
			detectionCount++;
			if(detectionCount == 1) options.error({status:404});
			else options.success({request:matchingId,state:'done',version:'2.6.12',number:'261200',family:'modern',status:'detected'});
		}
	};
	context.DetectRuntime();
	matchingId = context.vpnmgr_lastRequestId;
	assert.strictEqual(calls[0].url,'/start_apply.htm','runtime event must be posted before status is read');
	assert.strictEqual(calls[0].dataType,'text');
	runtimePost.success('firmware redirect remains inert text');
	assert.strictEqual(detectionCount,0,'the first result read is deferred');
	assert.strictEqual(context.queuedDelay,2000);
	context.queuedTimer();
	assert.strictEqual(detectionCount,1);
	assert.strictEqual(context.vpnmgr_runtimeState,'loading','initial asynchronous 404 must be retried');
	assert.ok(consoleSnapshots.slice(logStart).some(function(entry){return entry.area == 'runtime' && entry.event == 'pending';}),'a not-yet-created result is pending');
	var pendingIndex = consoleSnapshots.findIndex(function(entry,index){return index >= logStart && entry.area == 'runtime' && entry.event == 'pending';});
	assert.strictEqual(consoleLevels[pendingIndex],'info','an expected early 404 is a console notice');
	assert.strictEqual(consoleSnapshots.slice(logStart).some(function(entry){return entry.area == 'runtime' && entry.event == 'request_failed';}),false,'expected early 404 is not reported as a failed check');
	assert.strictEqual(typeof context.queuedTimer,'function');
	context.queuedTimer();
	assert.strictEqual(detectionCount,2);
	assert.strictEqual(context.vpnmgr_runtimeState,'known','matching delayed status should complete the check');
	assert.ok(consoleSnapshots.slice(logStart).some(function(entry){return entry.area == 'runtime' && entry.event == 'detected' && entry.version == '2.6.12' && entry.family == 'modern';}),'diagnostics record the final runtime result');
	assert.strictEqual(calls.filter(function(call){return call.url == '/start_apply.htm';}).length,1,'status retries must not repost the runtime event');
}

function testRuntimeInitialDelayHonorsOriginalDeadline(){
	var calls = [];
	jqueryState.ajax = function(options){calls.push(options);};
	context.DetectRuntime();
	var pending = context.vpnmgr_runtimePending;
	var startedAt = pending.startedAt;
	calls[0].success('');
	assert.strictEqual(pending.startedAt,startedAt,'the initial delay does not reset the request deadline');
	pending.startedAt = new Date().getTime()-120001;
	context.queuedTimer();
	assert.strictEqual(calls.length,1,'an expired initial wait cannot issue a status GET or repost the event');
	assert.strictEqual(context.vpnmgr_runtimeState,'failed');
	assert.strictEqual(context.vpnmgr_runtimePending,null);
	assert.strictEqual(jqueryState.properties['#btnSaveConfig:disabled'],true,'a timed-out runtime check still blocks Save');
}

function testStaleRuntimeResponseIgnored(){
	var calls = [];
	jqueryState.ajax = function(options){ calls.push(options); };
	context.DetectRuntime();
	var oldPost = calls[0];
	oldPost.success('');
	var oldTimer = context.queuedTimer;
	context.DetectRuntime();
	var currentPost = calls[1];
	var currentId = context.vpnmgr_lastRequestId;
	oldTimer();
	assert.strictEqual(calls.length,2,'a timer for a replaced runtime request cannot issue a GET');
	currentPost.success('');
	var currentTimer = context.queuedTimer;
	currentTimer();
	var currentStatus = calls[2];
	currentStatus.success({request:currentId,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'known');

	calls.length = 0;
	context.DetectRuntime();
	var oldId = context.vpnmgr_lastRequestId;
	oldPost = calls[0];
	oldPost.success('');
	context.queuedTimer();
	var oldStatus = calls[1];
	context.DetectRuntime();
	currentPost = calls[2];
	var currentId = context.vpnmgr_lastRequestId;
	currentPost.success('');
	oldStatus.success({request:oldId,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'loading','a stale response must not satisfy the newer check');
	context.queuedTimer();
	currentStatus = calls[3];
	currentStatus.success({request:currentId,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'known');
}

function testFreshPayloadAndAllSlots(){
	formElements.length = 0;
	for(var slot=1; slot<=5; slot++){
		addElement('vpnmgr_vpn'+slot+'_managed','true','radio',true);
		addElement('vpnmgr_vpn'+slot+'_provider','PIA','radio',true);
		addElement('vpnmgr_vpn'+slot+'_usn','user-'+slot,'text',false,slot == 2);
		addElement('vpnmgr_vpn'+slot+'_pwd','secret-'+slot,'password');
		addElement('vpnmgr_vpn'+slot+'_customsettings','false','radio',true);
		addElement('vpnmgr_vpn'+slot+'_type','Standard','radio',true);
		addElement('vpnmgr_vpn'+slot+'_protocol','UDP','radio',true);
		addElement('vpnmgr_vpn'+slot+'_countryname','Country '+slot,'select');
		addElement('vpnmgr_vpn'+slot+'_cityname','City '+slot,'select');
		addElement('vpnmgr_vpn'+slot+'_schenabled','false','radio',true);
		var days = [addElement('vpnmgr_vpn'+slot+'_schdays','Mon','checkbox',slot == 1)];
		formElements['vpnmgr_vpn'+slot+'_schdays'] = days;
		addElement('vpnmgr_vpn'+slot+'_schhours','*','text');
		addElement('vpnmgr_vpn'+slot+'_schmins','0','text');
	}
	context.custom_settings = {vpnmgr_version_local:'v1',unrelated_setting:'preserved'};
	var first = context.BuildCustomSettingsPayload('1234567890123456789');
	assert.strictEqual(first.vpnmgr_vpn1_usn,'user-1');
	assert.strictEqual(first.vpnmgr_vpn2_usn,'user-2','disabled managed values must remain in the payload');
	assert.strictEqual(first.vpnmgr_vpn1_schdays,'Mon');
	assert.strictEqual(first.vpnmgr_vpn2_schdays,'');
	assert.strictEqual(first.vpnmgr_vpn5_cityname,'City 5');
	assert.strictEqual(first.unrelated_setting,'preserved');
	assert.strictEqual(first.vpnmgr_request_id,'1234567890123456789');
	formElements[2].value = 'edited-after-first-save';
	var second = context.BuildCustomSettingsPayload('9876543210987654321');
	assert.strictEqual(first.vpnmgr_vpn1_usn,'user-1','earlier snapshots must not mutate');
	assert.strictEqual(second.vpnmgr_vpn1_usn,'edited-after-first-save','retry must capture current form values');
	assert.strictEqual(context.custom_settings.vpnmgr_vpn1_usn,undefined,'source settings must not be mutated');
	assert.strictEqual(second.other_form_value,undefined,'only document.form controls are serialized');
	formElements[1].value = 'NordVPN';
	context.window.vpnmgr_settings = [['vpn1_provider','nordvpn'],['vpn1_countryname','Country 1'],['vpn1_cityname','City 1'],['vpn1_countryid','440'],['vpn1_cityid','918']];
	var unavailableProvider = context.BuildCustomSettingsPayload('2222222222222222222');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_countryname,'Country 1');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_cityname,'City 1');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_countryid,'440','missing provider data must retain the saved country ID');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_cityid,'918','missing provider data must retain the saved city ID');
	context.window.vpnmgr_settings = [['vpn1_provider','nordvpn'],['vpn1_countryname','Australia'],['vpn1_cityname','Melbourne'],['vpn1_countryid','13'],['vpn1_cityid','999']];
	context.providerCountries.nordvpn = [{id:'13',name:'Australia',cities:[{id:'100',name:'Sydney'}]}];
	formElements[1].value = 'NordVPN';
	formElements[7].value = 'Australia';
	formElements[8].value = 'Melbourne';
	var retainedCity = context.BuildCustomSettingsPayload('3333333333333333333');
	assert.strictEqual(retainedCity.vpnmgr_vpn1_countryid,'13');
	assert.strictEqual(retainedCity.vpnmgr_vpn1_cityid,'999','unchanged unavailable city retains its saved ID');
	formElements[8].value = 'Sydney';
	var changedCity = context.BuildCustomSettingsPayload('4444444444444444444');
	assert.strictEqual(changedCity.vpnmgr_vpn1_cityid,'100','a catalogue selection uses its current city ID');
	formElements[8].value = 'Perth';
	var changedToUnlistedCity = context.BuildCustomSettingsPayload('5555555555555555555');
	assert.strictEqual(changedToUnlistedCity.vpnmgr_vpn1_cityid,0,'changed unavailable city must not inherit old ID');
	formElements[7].value = 'Germany';
	var changedCountry = context.BuildCustomSettingsPayload('6666666666666666666');
	assert.strictEqual(changedCountry.vpnmgr_vpn1_countryid,0);
	assert.strictEqual(changedCountry.vpnmgr_vpn1_cityid,0,'changed country must not inherit old city ID');
	formElements[1].value = 'PIA';
	formElements[7].value = 'Australia';
	formElements[8].value = 'Melbourne';
	var changedProvider = context.BuildCustomSettingsPayload('7777777777777777777');
	assert.strictEqual(changedProvider.vpnmgr_vpn1_countryid,0);
	assert.strictEqual(changedProvider.vpnmgr_vpn1_cityid,0,'changed provider must not inherit NordVPN IDs');
	context.providerCountries.nordvpn = [];
	formElements[1].value = 'NordVPN';
	var noCatalogue = context.BuildCustomSettingsPayload('8888888888888888888');
	assert.strictEqual(noCatalogue.vpnmgr_vpn1_countryid,'13');
	assert.strictEqual(noCatalogue.vpnmgr_vpn1_cityid,'999','unchanged values survive a missing catalogue');
	var saveButton = addElement('button','Save','button');
	var pending = {};
	context.vpnmgr_pendingApply = pending;
	context.FreezeConfigControls(pending);
	assert.strictEqual(formElements[15].disabled,true,'configuration controls freeze while captured values are applying');
	assert.strictEqual(saveButton.disabled,false,'non-configuration controls remain usable');
	context.FinishApplyFailure(pending,'Reservation busy.');
	assert.strictEqual(formElements[15].disabled,true,'an initially disabled field must restore disabled');
	assert.strictEqual(formElements[3].disabled,false,'an initially enabled configuration field must restore enabled');
	assert.strictEqual(saveButton.disabled,false);
}

function testStatusCorrelationAndLateCompletion(){
	var pending = {requestId:'1234567890123456789',phase:'apply',polling:true,startedAt:new Date().getTime()};
	context.vpnmgr_pendingApply = pending;
	var calls = [];
	jqueryState.ajax = function(options){
		calls.push(options);
		options.success(applyResponse('different-id','done',true));
	};
	context.PollApplyStatus(pending);
	assert.strictEqual(context.vpnmgr_pendingApply,pending,'stale status must not complete another request');
	assert.ok(context.vpnmgr_lastApplyDiagnostic.indexOf('stale') != -1);

	var malformed = applyResponse(pending.requestId,'done',true);
	malformed.clients.pop();
	assert.strictEqual(context.ApplyResponseValid(malformed),false);
	var incompleteDone = applyResponse(pending.requestId,'done',true);
	incompleteDone.clients[0].status = 'pending';
	assert.strictEqual(context.ApplyResponseValid(incompleteDone),false);
	var coerciveSlot = applyResponse(pending.requestId,'running',true);
	coerciveSlot.clients[0].slot = {toString:null,valueOf:null};
	assert.strictEqual(context.ApplyResponseValid(coerciveSlot),false,'slot values are exact numeric enums and are never coerced');
	var nonArrayClients = applyResponse(pending.requestId,'running',true);
	nonArrayClients.clients = {0:nonArrayClients.clients[0],1:nonArrayClients.clients[1],2:nonArrayClients.clients[2],3:nonArrayClients.clients[3],4:nonArrayClients.clients[4],length:5};
	assert.strictEqual(context.ApplyResponseValid(nonArrayClients),false,'client collection must be an array');

	context.vpnmgr_pendingApply = pending;
	pending.polling = true;
	pending.startedAt = new Date().getTime()-121000;
	calls.length = 0;
	context.PollApplyStatus(pending);
	assert.strictEqual(pending.polling,false);
	assert.strictEqual(calls.length,0,'timeout should stop polling without resubmitting');
	assert.strictEqual(jqueryState.shown['#btnContinueApply'],true);

	jqueryState.ajax = function(options){
		calls.push(options);
		if(options.url == '/start_apply.htm'){
			var action = options.data.filter(function(field){return field.name == 'action_script';})[0];
			if(action.value.indexOf('start_vpnmgrapply_') == 0) throw new Error('late continuation must not resubmit settings');
			options.success('runtime check control response text');
		}
		if(options.url.indexOf('/runtime/apply_') != -1) options.success(applyResponse(pending.requestId,'done',true));
		else if(options.url.indexOf('/runtime/detection_') != -1){
			var requestId = options.url.match(/detection_(\d+)\.json/)[1];
			options.success({request:requestId,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
		}
	};
	context.StartApplyOverlay();
	context.ContinueApplyChecking();
	context.queuedTimer();
	assert.strictEqual(context.vpnmgr_pendingApply,pending,'confirmed success remains pending during its display dwell');
	assert.strictEqual(pending.progressPercent,100,'confirmed success reaches 100 percent before cleanup');
	assert.strictEqual(loadingState.visible,true,'success overlay remains visible during its display dwell');
	assert.strictEqual(context.queuedDelay,500,'confirmed success uses the fixed display dwell');
	context.queuedTimer();
	assert.strictEqual(proceedingMain.textContent,'Complete','the native main line shows Complete after the 100 percent dwell');
	assert.strictEqual(proceedingDetail.textContent,'','the native detail line clears during Complete');
	assert.strictEqual(context.vpnmgr_pendingApply,pending,'the request remains active during the Complete dwell');
	assert.strictEqual(loadingState.visible,true,'the overlay remains visible during the Complete dwell');
	assert.strictEqual(context.queuedDelay,500,'Complete remains visible for its own 500 ms dwell');
	context.queuedTimer();
	assert.strictEqual(context.vpnmgr_pendingApply,null,'late completion should finish the original request');
	assert.strictEqual(calls.filter(function(call){return call.url == '/start_apply.htm' && call.data.filter(function(field){return field.name == 'action_script';})[0].value.indexOf('start_vpnmgrapply_') == 0;}).length,0);
	assert.ok(context.vpnmgr_lastApplyDiagnostic.indexOf('Settings saved') != -1);
}

function testBackendProgressRequiresMatchingResolvedOutcomes(){
	var pending = {requestId:'2323232323232323232',phase:'apply',polling:true,startedAt:new Date().getTime(),progressUnits:0,progressPercent:0};
	context.vpnmgr_pendingApply = pending;
	context.StartApplyOverlay();
	assert.ok(proceedingDetail.textContent.indexOf('0%') != -1,'new apply starts at zero');
	var response;
	jqueryState.ajax = function(options){ options.success(response); };
	function poll(data){ response = data; context.PollApplyStatus(pending); }
	poll(applyResponse(pending.requestId,'running',false,['applied','applied','applied','applied','applied']));
	assert.strictEqual(pending.progressPercent,0,'client outcomes before settings merge do not advance progress');
	var first = applyResponse(pending.requestId,'running',true,['pending','pending','pending','pending','pending']);
	poll(first);
	assert.strictEqual(pending.progressPercent,14,'merged settings complete the first of seven units');
	assert.ok(proceedingDetail.textContent.indexOf('14%') != -1);
	var second = applyResponse(pending.requestId,'running',true,['applied','pending','pending','pending','pending']);
	poll(second);
	assert.strictEqual(pending.progressPercent,28,'one resolved client advances one unit');
	var third = applyResponse(pending.requestId,'running',true,['applied','failed','pending','pending','pending']);
	poll(third);
	assert.strictEqual(pending.progressPercent,42,'failed client outcome still completes its attempt');
	poll(applyResponse('different-request','running',true,['applied','applied','applied','applied','applied']));
	assert.strictEqual(pending.progressPercent,42,'stale response cannot advance progress');
	var malformed = applyResponse(pending.requestId,'running',true,['applied','applied','applied','applied','applied']);
	malformed.clients.pop();
	poll(malformed);
	assert.strictEqual(pending.progressPercent,42,'malformed response cannot advance progress');
	var regressed = applyResponse(pending.requestId,'running',true,['pending','pending','pending','pending','pending']);
	poll(regressed);
	assert.strictEqual(pending.progressPercent,42,'older matching snapshots cannot regress per-request progress');
	var unmerged = applyResponse(pending.requestId,'running',false,['applied','applied','applied','applied','applied']);
	poll(unmerged);
	assert.strictEqual(pending.progressPercent,42,'client outcomes do not count before settings merge');
	var allResolvedRunning = applyResponse(pending.requestId,'running',true,['applied','failed','unmanaged','applied','applied']);
	poll(allResolvedRunning);
	assert.strictEqual(pending.progressPercent,85,'all resolved attempts remain below terminal success while running');
	assert.ok(proceedingDetail.textContent.indexOf('85%') != -1);
	pending.startedAt = 0;
	context.PollApplyStatus(pending);
	assert.strictEqual(pending.progressPercent,85,'elapsed timeout does not change backend progress');
	assert.ok(proceedingDetail.textContent.indexOf('85%') != -1,'timeout recovery keeps the last percentage visible');
	context.ContinueApplyChecking();
	assert.ok(proceedingDetail.textContent.indexOf('85%') != -1,'same-request recovery preserves the percentage');
	context.FinishApplyFailure(pending,'Progress test cleanup.');

	var partial = {requestId:'2424242424242424242',phase:'apply',polling:true,progressUnits:0,progressPercent:0};
	context.vpnmgr_pendingApply = partial;
	context.StartApplyOverlay();
	var failedResult = applyResponse(partial.requestId,'done',true,['applied','failed','unmanaged','applied','applied']);
	failedResult.clients[1].connection = 'failed';
	context.FinishApplyResult(partial,failedResult);
	assert.strictEqual(partial.progressPercent,85,'partial terminal result never reaches 100 percent');

	var uncertain = {requestId:'2626262626262626262',phase:'apply',polling:true,progressUnits:0,progressPercent:0};
	context.vpnmgr_pendingApply = uncertain;
	context.StartApplyOverlay();
	var uncertainResult = applyResponse(uncertain.requestId,'done',true);
	uncertainResult.clients[0].connection = 'unknown';
	context.FinishApplyResult(uncertain,uncertainResult);
	assert.strictEqual(uncertain.progressPercent,85,'uncertain connection outcome never reaches 100 percent');
	assert.strictEqual(context.vpnmgr_pendingApply,null,'uncertain result is released immediately without the success dwell');
	assert.strictEqual(loadingState.visible,false,'uncertain result closes the overlay immediately');
	assert.notStrictEqual(proceedingMain.textContent,'Complete','uncertain result never shows Complete');

	var success = {requestId:'2525252525252525252',phase:'apply',polling:true,progressUnits:0,progressPercent:0};
	context.vpnmgr_pendingApply = success;
	context.StartApplyOverlay();
	var successfulResult = applyResponse(success.requestId,'done',true,['applied','unmanaged','applied','applied','applied']);
	successfulResult.clients[0].connection = 'verified_stopped';
	context.FinishApplyResult(success,successfulResult);
	assert.strictEqual(success.progressPercent,100,'verified_stopped is an authoritative successful terminal outcome');
	assert.strictEqual(context.vpnmgr_pendingApply,success,'successful request remains active until the display timer fires');
	assert.strictEqual(proceedingDetail.textContent,'100% Applying Settings','verified success displays completion copy at 100 percent');
	context.queuedTimer();
	assert.strictEqual(proceedingMain.textContent,'Complete','success transitions to Complete after 500 ms');
	assert.strictEqual(context.vpnmgr_pendingApply,success,'request remains pending through the Complete dwell');
	context.queuedTimer();
	assert.strictEqual(context.vpnmgr_pendingApply,null,'success cleanup runs after the display timer');
}

function testPrepareGateAndNoncePost(){
	var requestId = '1111111111111111111';
	var pending = {requestId:requestId,payload:{vpnmgr_request_id:requestId},fields:[{name:'action_script',value:'start_vpnmgrapply_'+requestId},{name:'amng_custom',value:JSON.stringify({vpnmgr_request_id:requestId})}],phase:'prepare',polling:true,startedAt:new Date().getTime()};
	context.vpnmgr_pendingApply = pending;
	var calls = [];
	jqueryState.ajax = function(options){
		calls.push(options);
		if(options.url.indexOf('/runtime/apply_') != -1 && calls.length == 1){
			options.success({request:requestId,state:'busy'});
		}
		else if(options.url.indexOf('/runtime/apply_') != -1){
			options.success(applyResponse(requestId,'running',true));
		}
		else if(options.url == '/start_apply.htm'){
			assert.strictEqual(options.type,'POST');
			assert.strictEqual(options.dataType,'text','firmware JavaScript responses must not execute');
			var action = options.data.filter(function(field){return field.name == 'action_script';})[0];
			var custom = options.data.filter(function(field){return field.name == 'amng_custom';})[0];
			assert.strictEqual(action.value,'start_vpnmgrapply_'+requestId);
			assert.strictEqual(JSON.parse(custom.value).vpnmgr_request_id,requestId);
			options.success('');
		}
	};
	context.PollApplyStatus(pending);
	assert.strictEqual(calls.length,1,'a busy reservation must not submit settings');
	assert.strictEqual(context.vpnmgr_pendingApply,null,'busy reservation should terminate without apply POST');

	pending = {requestId:requestId,payload:{vpnmgr_request_id:requestId},fields:[{name:'action_script',value:'start_vpnmgrapply_'+requestId},{name:'amng_custom',value:JSON.stringify({vpnmgr_request_id:requestId})}],phase:'prepare',polling:true,startedAt:new Date().getTime()};
	context.vpnmgr_pendingApply = pending;
	calls.length = 0;
	jqueryState.ajax = function(options){
		calls.push(options);
		if(options.url.indexOf('/runtime/apply_') != -1 && calls.length == 1) options.success({request:requestId,state:'ready'});
		else if(options.url == '/start_apply.htm'){
			assert.strictEqual(options.type,'POST');
			assert.strictEqual(options.dataType,'text');
			var action = options.data.filter(function(field){return field.name == 'action_script';})[0];
			var custom = options.data.filter(function(field){return field.name == 'amng_custom';})[0];
			assert.strictEqual(action.value,'start_vpnmgrapply_'+requestId);
			assert.strictEqual(JSON.parse(custom.value).vpnmgr_request_id,requestId);
			options.success('');
		}
		else if(options.url.indexOf('/runtime/apply_') != -1) options.success(applyResponse(requestId,'running',true));
	};
	context.PollApplyStatus(pending);
	assert.strictEqual(calls[0].url,'/ext/vpnmgr/runtime/apply_'+requestId+'.json');
	assert.strictEqual(calls[1].url,'/start_apply.htm','settings POST must follow matching ready status');
	assert.strictEqual(calls.length,2,'apply result read waits for the asynchronous backend');
	assert.strictEqual(context.queuedDelay,2000);
	context.queuedTimer();
	assert.strictEqual(calls[2].url,'/ext/vpnmgr/runtime/apply_'+requestId+'.json');
}

function testRecoveryAfterLostSettingsPost(){
	formElements.length = 0;
	var frozenPassword = addElement('vpnmgr_vpn1_pwd','keep-this-value','password',false,false);
	var pending = {requestId:'1212121212121212121',payload:{vpnmgr_request_id:'1212121212121212121'},fields:[{name:'action_script',value:'start_vpnmgrapply_1212121212121212121'},{name:'amng_custom',value:'{"vpnmgr_request_id":"1212121212121212121"}'}],phase:'apply',polling:false};
	context.vpnmgr_pendingApply = pending;
	context.FreezeConfigControls(pending);
	var applyPosts = 0, recoverPosts = 0, statusReads = 0, recoveryApplied = false;
	jqueryState.ajax = function(options){
		if(options.url == '/start_apply.htm'){
			var action = options.data.filter(function(field){return field.name == 'action_script';})[0].value;
			if(action.indexOf('start_vpnmgrapply_') == 0){ applyPosts++; options.error(); return; }
			if(action.indexOf('start_vpnmgrrecover_') == 0){
				recoverPosts++;
				assert.strictEqual(action,'start_vpnmgrrecover_'+pending.requestId,'recovery must stay correlated to the reservation');
				assert.strictEqual(options.dataType,'text');
				assert.strictEqual(options.data.filter(function(field){return field.name == 'amng_custom';}).length,0,'recovery must not resend settings');
				recoveryApplied = true;
				options.success('inert redirect text');
				return;
			}
			if(action.indexOf('start_vpnmgrruntime_') == 0){ options.success(''); return; }
		}
		if(options.url.indexOf('/runtime/apply_') != -1){
			statusReads++;
			if(recoveryApplied){
				var expired = applyResponse(pending.requestId,'failed',false,['pending','pending','pending','pending','pending']);
				expired.message = 'expired';
				options.success(expired);
			}
			else options.success({request:pending.requestId,state:'ready'});
			return;
		}
		if(options.url.indexOf('/runtime/detection_') != -1){
			var id = options.url.match(/detection_(\d+)\.json/)[1];
			options.success({request:id,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
		}
	};
	context.PostPreparedApply(pending);
	assert.strictEqual(applyPosts,1,'the lost settings POST is attempted once');
	assert.strictEqual(statusReads,0,'lost acknowledgement still defers the first status read');
	context.queuedTimer();
	assert.strictEqual(statusReads,1,'the ready reservation is recognized after POST loss');
	assert.ok(context.vpnmgr_lastApplyDiagnostic.indexOf('remains reserved') != -1,'ready state explains uncertainty without a malformed-response message');
	pending.startedAt = 0;
	context.PollApplyStatus(pending);
	assert.strictEqual(pending.timedOut,true);
	assert.strictEqual(frozenPassword.disabled,true);
	assert.strictEqual(jqueryState.shown['#btnReloadSettings'],true,'timeout offers reload as an explicit escape');
	context.ContinueApplyChecking();
	assert.strictEqual(recoverPosts,1);
	context.queuedTimer();
	assert.strictEqual(context.vpnmgr_pendingApply,null,'expired reservation is terminal and releases the form');
	assert.strictEqual(frozenPassword.disabled,false,'original form state is restored');
	assert.strictEqual(frozenPassword.value,'keep-this-value','recovery never repopulates old values');
	assert.strictEqual(applyPosts,1,'recovery never resubmits the settings payload');
	assert.ok(context.vpnmgr_lastApplyDiagnostic.indexOf('expired') != -1);
}

function testRecoveryLossAndLateApplyAreUncertainSafe(){
	function setupPending(requestId){
		formElements.length = 0;
		var field = addElement('vpnmgr_vpn1_pwd','pending-value','password',false,false);
		var pending = {requestId:requestId,payload:{vpnmgr_request_id:requestId},fields:[],phase:'apply',polling:false,timedOut:true};
		context.vpnmgr_pendingApply = pending;
		context.FreezeConfigControls(pending);
		return {pending:pending,field:field};
	}

	var lostRecovery = setupPending('1313131313131313131');
	var applies = 0, recovers = 0;
	jqueryState.ajax = function(options){
		if(options.url == '/start_apply.htm'){
			var action = options.data.filter(function(field){return field.name == 'action_script';})[0].value;
			if(action.indexOf('start_vpnmgrrecover_') == 0){ recovers++; options.error(); return; }
			if(action.indexOf('start_vpnmgrapply_') == 0) applies++;
		}
		if(options.url.indexOf('/runtime/apply_') != -1) options.success({request:lostRecovery.pending.requestId,state:'ready'});
	};
	context.ContinueApplyChecking();
	assert.strictEqual(recovers,1);
	context.queuedTimer();
	assert.strictEqual(applies,0);
	assert.strictEqual(context.vpnmgr_pendingApply,lostRecovery.pending,'lost recovery acknowledgement leaves status uncertain');
	assert.strictEqual(lostRecovery.field.disabled,true,'controls stay frozen while recovery is uncertain');
	assert.strictEqual(jqueryState.shown['#btnContinueApply'],false,'polling resumes after recovery POST loss');

	['running','done'].forEach(function(initialState){
		var current = setupPending(initialState == 'running' ? '1414141414141414141':'1515151515151515151');
		var statusState = initialState;
		var recoveryState = '';
		var applyCount = 0;
		jqueryState.ajax = function(options){
			if(options.url == '/start_apply.htm'){
				var action = options.data.filter(function(field){return field.name == 'action_script';})[0].value;
				if(action.indexOf('start_vpnmgrapply_') == 0) applyCount++;
				if(action.indexOf('start_vpnmgrrecover_') == 0){ recoveryState = statusState; options.success(''); }
				else if(action.indexOf('start_vpnmgrruntime_') == 0) options.success('');
				return;
			}
			if(options.url.indexOf('/runtime/apply_') != -1){
				if(statusState == 'running') options.success(applyResponse(current.pending.requestId,'running',true));
				else options.success(applyResponse(current.pending.requestId,'done',true));
				return;
			}
			if(options.url.indexOf('/runtime/detection_') != -1){
				var id = options.url.match(/detection_(\d+)\.json/)[1];
				options.success({request:id,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
			}
		};
		context.ContinueApplyChecking();
		assert.strictEqual(recoveryState,initialState,'recovery leaves running/done backend state unchanged');
		context.queuedTimer();
		if(initialState == 'running'){
			assert.strictEqual(context.vpnmgr_pendingApply,current.pending,'recovery does not cancel a running application');
			statusState = 'done';
			context.queuedTimer();
		}
		assert.strictEqual(context.vpnmgr_pendingApply,current.pending,'confirmed completion stays active during its display dwell');
		assert.strictEqual(current.field.disabled,true,'the form stays locked during the success dwell');
		context.queuedTimer();
		assert.strictEqual(proceedingMain.textContent,'Complete','late confirmed apply shows Complete in the native overlay');
		assert.strictEqual(context.vpnmgr_pendingApply,current.pending,'the request stays active during Complete');
		context.queuedTimer();
		assert.strictEqual(context.vpnmgr_pendingApply,null,'late applied delivery is accepted as authoritative completion');
		assert.strictEqual(current.field.disabled,false);
		assert.strictEqual(applyCount,0,'recovery and late polling never repost settings');
	});
}

function testPartialApplyResult(){
	var pending = {requestId:'9876543210987654321',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = pending;
	jqueryState.ajax = function(options){
		if(options.url == '/start_apply.htm') options.success('');
		else if(options.url.indexOf('/runtime/detection_') != -1){
			var requestId = options.url.match(/detection_(\d+)\.json/)[1];
			options.success({request:requestId,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
		}
	};
	var data = applyResponse(pending.requestId,'done',true,['applied','failed','unmanaged','applied','applied']);
	data.clients[1].connection = 'failed';
	context.FinishApplyResult(pending,data);
	assert.ok(context.lastAlert.indexOf('VPN Client 2') != -1);
	assert.strictEqual(loadingState.visible,false,'terminal failure hides the apply overlay');
}

function testVerifiedStoppedConnectionStatus(){
	var pending = {requestId:'1616161616161616161',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = pending;
	var data = applyResponse(pending.requestId,'done',true);
	data.clients[0].connection = 'verified_stopped';
	assert.strictEqual(context.ApplyResponseValid(data),true);
	context.LogApplyStatus(pending,'status',data);
	jqueryState.ajax = function(options){
		if(options.url == '/start_apply.htm') options.success('');
		else if(options.url.indexOf('/runtime/detection_') != -1){
			var id = options.url.match(/detection_(\d+)\.json/)[1];
			options.success({request:id,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
		}
	};
	context.lastAlert = undefined;
	context.FinishApplyResult(pending,data);
	assert.strictEqual(context.lastAlert,undefined,'verified stopped is a successful outcome');
	assert.strictEqual(context.vpnmgr_pendingApply,pending,'verified stopped remains active until the display dwell ends');
	context.queuedTimer();
	assert.strictEqual(proceedingMain.textContent,'Complete','verified stopped displays the native Complete phase');
	assert.strictEqual(context.vpnmgr_pendingApply,pending,'verified stopped remains active through Complete');
	context.queuedTimer();
	assert.strictEqual(context.vpnmgr_pendingApply,null,'verified stopped cleanup follows the display dwell');
	assert.ok(JSON.stringify(consoleSnapshots).indexOf('verified_stopped') != -1,'console reports the truthful verified-stopped state');
	assert.strictEqual(JSON.stringify(consoleSnapshots).indexOf('currently connected'),-1);
}

function testMalformedClientKeepsPollingReachable(){
	var pending = {requestId:'1717171717171717171',phase:'apply',polling:true,startedAt:new Date().getTime()};
	var malformed = applyResponse(pending.requestId,'running',true);
	malformed.clients[2] = null;
	assert.strictEqual(context.ApplyResponseValid(malformed),false,'null client entries are rejected');
	context.vpnmgr_pendingApply = pending;
	context.StartApplyOverlay();
	jqueryState.ajax = function(options){ options.success(malformed); };
	assert.doesNotThrow(function(){context.PollApplyStatus(pending);},'malformed client entries must not throw during status polling');
	assert.strictEqual(context.vpnmgr_pendingApply,pending,'malformed status stays pending');
	assert.strictEqual(pending.polling,true,'polling remains active after malformed status');
	assert.strictEqual(typeof context.queuedTimer,'function','the next status poll is scheduled');
	pending.startedAt = 0;
	context.queuedTimer();
	assert.strictEqual(pending.polling,false,'deadline remains reachable after malformed status');
	assert.strictEqual(pending.timedOut,true);
	assert.strictEqual(loadingState.visible,true,'timeout leaves the native overlay available for recovery');
	assert.strictEqual(jqueryState.shown['#btnContinueApply'],true);
	assert.strictEqual(jqueryState.shown['#btnReloadSettings'],true);
	context.FinishApplyFailure(pending,'Apply test cleanup.');
}

function testNativeOverlayCleanup(){
	jqueryState.ajax = function(options){
		if(options.url == '/start_apply.htm') options.success('inert redirect');
		else if(options.url.indexOf('/runtime/detection_') != -1){
			var id = options.url.match(/detection_(\d+)\.json/)[1];
			options.success({request:id,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
		}
	};
	var initialHideCount = loadingState.hideCalls;
	var initialReloadCount = context.reloadCount || 0;
	formElements.length = 0;
	var successField = addElement('vpnmgr_vpn1_pwd','locked-value','password',false,false);
	var success = {requestId:'1818181818181818181',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = success;
	context.FreezeConfigControls(success);
	context.lastAlert = undefined;
	htmlNode.style.overflow = 'scroll';
	context.StartApplyOverlay();
	assert.strictEqual(loadingState.visible,true);
	assert.strictEqual(htmlNode.style.overflow,'hidden');
	assert.strictEqual(loadingState.showArguments[loadingState.showArguments.length-1],0,'native firmware loading helper receives no countdown arguments');
	assert.ok(context.vpnmgr_recoveryRow && context.vpnmgr_recoveryRow.parentNode === loadingTable,'recovery controls are placed in a native loadingBlock table row');
	var done = applyResponse(success.requestId,'done',true,['unmanaged','unmanaged','unmanaged','unmanaged','unmanaged']);
	context.FinishApplyResult(success,done);
	var percentCallback = context.queuedTimer;
	context.FinishApplyResult(success,done);
	assert.strictEqual(context.queuedTimer,percentCallback,'duplicate terminal handling cannot schedule a second dwell');
	assert.strictEqual(success.progressPercent,100,'confirmed success fills the percentage bar before reload');
	assert.strictEqual(proceedingDetail.textContent,'100% Applying Settings','success text remains visible during the dwell');
	assert.strictEqual(context.vpnmgr_pendingApply,success,'the same request remains active during the dwell');
	assert.strictEqual(successField.disabled,true,'configuration remains locked during the dwell');
	assert.strictEqual(loadingState.visible,true,'successful completion keeps the native overlay visible');
	assert.strictEqual(context.queuedDelay,500,'100 percent is scheduled for a 500 ms dwell');
	assert.strictEqual(context.reloadCount || 0,initialReloadCount,'success does not reload before the scheduled callback');
	percentCallback();
	assert.strictEqual(proceedingMain.textContent,'Complete','the main native line changes to Complete');
	assert.strictEqual(proceedingDetail.textContent,'','Complete clears the detail native line');
	assert.strictEqual(context.vpnmgr_pendingApply,success,'the same request remains active during Complete');
	assert.strictEqual(successField.disabled,true,'configuration remains locked during Complete');
	assert.strictEqual(loadingState.visible,true,'the native overlay remains visible during Complete');
	assert.strictEqual(context.queuedDelay,500,'Complete is scheduled for a second 500 ms dwell');
	assert.strictEqual(context.reloadCount || 0,initialReloadCount,'navigation waits through both display phases');
	var completeCallback = context.queuedTimer;
	context.FinishApplyResult(success,done);
	assert.strictEqual(context.queuedTimer,completeCallback,'duplicate terminal handling cannot restart the Complete dwell');
	completeCallback();
	assert.strictEqual(loadingState.visible,false,'the delayed cleanup hides the native overlay');
	assert.strictEqual(loadingState.hideCalls,initialHideCount+1);
	assert.strictEqual(htmlNode.style.overflow,'scroll','original page scrolling is restored after the dwell');
	assert.deepStrictEqual(context.lastScroll,[17,29]);
	assert.strictEqual(recoveryControls.parentNode,recoveryHome,'static recovery controls return home after completion');
	assert.strictEqual(context.vpnmgr_pendingApply,null,'the request clears after delayed cleanup');
	assert.strictEqual(successField.disabled,false,'the form unlocks after delayed cleanup');
	assert.strictEqual(context.lastAlert,undefined,'success is silent');
	assert.strictEqual(context.reloadCount,initialReloadCount+1,'confirmed success reloads once after the dwell');

	var failure = {requestId:'1919191919191919191',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = failure;
	context.StartApplyOverlay();
	var failed = applyResponse(failure.requestId,'done',true,['applied','failed','unmanaged','applied','unmanaged']);
	failed.clients[1].connection = 'failed';
	context.FinishApplyResult(failure,failed);
	assert.strictEqual(loadingState.visible,false,'terminal failure hides the native overlay');
	assert.notStrictEqual(proceedingMain.textContent,'Complete','partial failure never displays Complete');
	assert.ok(context.lastAlert.indexOf('VPN Client 2') != -1,'terminal failure gives a concise user alert');
	assert.strictEqual(recoveryControls.parentNode,recoveryHome);
	assert.strictEqual(context.reloadCount,initialReloadCount+1,'partial failure preserves the page and edits');

	var originalHideLoading = context.hideLoading;
	var missingHide = {requestId:'2121212121212121212',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = missingHide;
	context.StartApplyOverlay();
	assert.strictEqual(loadingMask.style.visibility,'visible');
	context.hideLoading = undefined;
	context.FinishApplyFailure(missingHide,'Missing hide helper.');
	context.hideLoading = originalHideLoading;
	assert.strictEqual(loadingMask.style.visibility,'hidden','fallback cleanup closes the mask if hideLoading is missing');
}

function testDeferredSuccessCannotFinishNewerRequest(){
	var oldRequest = {requestId:'2727272727272727272',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = oldRequest;
	context.StartApplyOverlay();
	var success = applyResponse(oldRequest.requestId,'done',true,['unmanaged','unmanaged','unmanaged','unmanaged','unmanaged']);
	context.FinishApplyResult(oldRequest,success);
	var obsoleteCallback = context.queuedTimer;
	var reloads = context.reloadCount || 0;
	var newerRequest = {requestId:'2828282828282828282',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = newerRequest;
	obsoleteCallback();
	assert.strictEqual(context.vpnmgr_pendingApply,newerRequest,'obsolete success callback cannot clear a newer request');
	assert.strictEqual(loadingState.visible,true,'obsolete success callback cannot hide the newer request overlay');
	assert.notStrictEqual(proceedingMain.textContent,'Complete','obsolete 100 percent callback cannot advance to Complete');
	assert.strictEqual(context.reloadCount || 0,reloads,'obsolete success callback cannot reload over a newer request');
	context.FinishApplyFailure(newerRequest,'Guard test cleanup.');

	var completingRequest = {requestId:'2929292929292929292',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = completingRequest;
	context.StartApplyOverlay();
	context.FinishApplyResult(completingRequest,applyResponse(completingRequest.requestId,'done',true,['unmanaged','unmanaged','unmanaged','unmanaged','unmanaged']));
	context.queuedTimer();
	assert.strictEqual(proceedingMain.textContent,'Complete','the first valid timer advances to the Complete phase');
	assert.strictEqual(context.vpnmgr_pendingApply,completingRequest);
	var obsoleteCompleteCallback = context.queuedTimer;
	var newestRequest = {requestId:'3030303030303030303',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = newestRequest;
	var beforeCompleteReloads = context.reloadCount || 0;
	obsoleteCompleteCallback();
	assert.strictEqual(context.vpnmgr_pendingApply,newestRequest,'obsolete Complete callback cannot clear a newer request');
	assert.strictEqual(loadingState.visible,true,'obsolete Complete callback cannot hide the newer request overlay');
	assert.strictEqual(proceedingMain.textContent,'Complete','obsolete Complete callback cannot alter the current display');
	assert.strictEqual(context.reloadCount || 0,beforeCompleteReloads,'obsolete Complete callback cannot reload over a newer request');
	context.FinishApplyFailure(newestRequest,'Complete guard test cleanup.');
}

function testNativeStatusPollingPreserved(){
	var originalShow = context.showLoading;
	context.showLoading = function(){ context.window.stopFlag = 1; originalShow(); };
	for(var i=0; i<2; i++){
		context.window.stopFlag = i;
		context.StartApplyOverlay();
		assert.strictEqual(context.window.stopFlag,i,'native overlay preserves the existing firmware polling flag immediately');
		context.FinishApplyOverlay();
	}
	context.window.stopFlag = 0;
	context.showLoading = function(){ context.window.stopFlag = 1; throw new Error('fixture helper failure'); };
	assert.doesNotThrow(function(){context.StartApplyOverlay();});
	assert.strictEqual(context.window.stopFlag,0,'throwing native helper cannot stop firmware status/autologout polling');
	context.FinishApplyOverlay();
	delete context.window.stopFlag;
	context.showLoading = function(){ originalShow(); };
	context.StartApplyOverlay();
	assert.strictEqual(Object.prototype.hasOwnProperty.call(context.window,'stopFlag'),false,'absent firmware flags are left absent');
	context.FinishApplyOverlay();
	context.showLoading = originalShow;
}

function testAllowlistedConsoleSnapshotsAndDedupe(){
	var pending = {requestId:'2020202020202020202',phase:'apply'};
	var data = applyResponse(pending.requestId,'running',true);
	data.password = 'VM_SECRET_PASSWORD_413';
	data.amng_custom = 'VM_SECRET_SETTINGS_971';
	data.extra_response_field = 'VM_SECRET_RESPONSE_265';
	data.clients[0].credential = 'VM_SECRET_CLIENT_804';
	var start = consoleSnapshots.length;
	context.LogApplyStatus(pending,'status',data);
	var afterFirst = consoleSnapshots.length;
	assert.strictEqual(afterFirst,start+1,'validated status logs one summary snapshot');
	context.LogApplyStatus(pending,'status',data);
	assert.strictEqual(consoleSnapshots.length,afterFirst,'identical status snapshots are logged only once');
	var emitted = JSON.stringify(consoleSnapshots.slice(start));
	['VM_SECRET_PASSWORD_413','VM_SECRET_SETTINGS_971','VM_SECRET_RESPONSE_265','VM_SECRET_CLIENT_804'].forEach(function(secret){
		assert.strictEqual(emitted.indexOf(secret),-1,'console snapshot excludes '+secret);
	});
	var snapshot = JSON.parse(JSON.stringify(consoleSnapshots[afterFirst-1]));
	assert.deepStrictEqual(Object.keys(snapshot).sort(),['clients','event','merged','message','phase','request','state'].sort());
	assert.deepStrictEqual(Object.keys(snapshot.clients[0]).sort(),['connection','slot','status'].sort());
}

function testLoadedSettingsContract(){
	var rows = [];
	for(var slot=1; slot<=5; slot++){
		var values = {managed:'true',provider:'NordVPN',customsettings:'false',protocol:'UDP',type:'Standard',countryname:'',cityname:'',schenabled:'false',schhours:'0',schmins:'15',schdays:'*'};
		for(var key in values) rows.push(['vpn'+slot+'_'+key,values[key]]);
	}
	assert.strictEqual(context.LoadedSettingsValid(rows),true);
	assert.strictEqual(context.LoadedSettingsValid([['broken','looks like settings']]),false,'truncated settings must not enable Save');
	var protocol = rows.filter(function(row){return row[0] == 'vpn4_protocol';})[0];
	protocol[1] = 'tcp';
	assert.strictEqual(context.LoadedSettingsValid(rows),true,'existing protocol casing remains accepted');
	protocol[1] = 'invalid';
	assert.strictEqual(context.LoadedSettingsValid(rows),false);
}

function testApplyInitialReadAndPendingNotice(){
	var pending = {requestId:'1616161616161616161',polling:false};
	context.vpnmgr_pendingApply = pending;
	var reads = 0;
	jqueryState.ajax = function(options){ reads++; options.error({status:404}); };
	context.BeginApplyPolling(pending,'prepare');
	assert.strictEqual(reads,0,'reservation file is not read before the first polling interval');
	assert.strictEqual(context.queuedDelay,2000);
	var obsolete = context.queuedTimer;
	pending.phase = 'apply';
	obsolete();
	assert.strictEqual(reads,0,'an obsolete phase timer cannot read a later phase early');
	pending.polling = false;
	context.BeginApplyPolling(pending,'apply');
	context.queuedTimer();
	assert.strictEqual(reads,1);
	assert.strictEqual(consoleSnapshots[consoleSnapshots.length-1].event,'status_pending');
	assert.strictEqual(consoleLevels[consoleLevels.length-1],'info','an expected missing file is informational');
	pending.startedAt = 0;
	context.queuedTimer();
	assert.strictEqual(reads,1,'the first-read wait is part of the original polling deadline');
	assert.strictEqual(pending.timedOut,true);
	pending.polling = true;pending.startedAt = Date.now();
	jqueryState.ajax = function(options){ reads++; options.success({request:pending.requestId,state:'ready'}); };
	context.PollApplyStatus(pending);
	assert.strictEqual(consoleSnapshots[consoleSnapshots.length-1].event,'status_pending','a still-ready reservation is pending, not malformed');
	assert.strictEqual(consoleLevels[consoleLevels.length-1],'info');
	context.vpnmgr_pendingApply = null;
}

testLoadedSettingsContract();
testRequestIdsAndRuntimeContract();
testRuntime404RetryAndCorrelation();
testRuntimeInitialDelayHonorsOriginalDeadline();
testStaleRuntimeResponseIgnored();
testFreshPayloadAndAllSlots();
testStatusCorrelationAndLateCompletion();
testBackendProgressRequiresMatchingResolvedOutcomes();
testPrepareGateAndNoncePost();
testRecoveryAfterLostSettingsPost();
testRecoveryLossAndLateApplyAreUncertainSafe();
testPartialApplyResult();
testVerifiedStoppedConnectionStatus();
testMalformedClientKeepsPollingReachable();
testNativeOverlayCleanup();
testDeferredSuccessCannotFinishNewerRequest();
testNativeStatusPollingPreserved();
testAllowlistedConsoleSnapshotsAndDedupe();
testApplyInitialReadAndPendingNotice();
process.stdout.write('Web UI contract checks passed.\n');
