'use strict';

var assert = require('assert');
var fs = require('fs');
var vm = require('vm');

var jqueryState = {ajax:null,text:{},shown:{},properties:{}};
function jQueryStub(selector){
	return {
		prop:function(name,value){ jqueryState.properties[String(selector)+':'+name] = value; return this; },
		text:function(value){ jqueryState.text[String(selector)] = value; return this; },
		hide:function(){ jqueryState.shown[String(selector)] = false; return this; },
		show:function(){ jqueryState.shown[String(selector)] = true; return this; },
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
	document:{form:{elements:formElements},formScriptActions:{elements:[],fields:[{name:'productid',value:'router'},{name:'action_script',value:''}]},createElement:function(){return {};},getElementById:function(){return {style:{}};},getElementsByTagName:function(){return []; }},
	window:{location:{pathname:'/vpnmgr.asp'}},
	location:{reload:function(){}},
	setTimeout:function(callback){ context.queuedTimer = callback; return 1; },
	clearTimeout:function(){},
	alert:function(message){ context.lastAlert = message; },
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
	return {request:request,state:state,merged:merged,clients:clients,message:state == 'done' ? 'complete' : 'running'};
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
	assert.strictEqual(detectionRequest.url,'/ext/vpnmgr/runtime/detection_'+context.vpnmgr_lastRequestId+'.json');
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'2.6.12',number:'261200',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'known');
	assert.ok(jqueryState.text['#vpnmgr_runtime_status'].indexOf('modern') != -1);

	context.DetectRuntime();
	runtimePost.success('');
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'',number:'',family:'legacy',status:'unknown'});
	assert.strictEqual(context.vpnmgr_runtimeState,'unknown');
	assert.ok(jqueryState.text['#vpnmgr_runtime_status'].indexOf('legacy fallback') != -1);

	context.DetectRuntime();
	runtimePost.success('');
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'',number:'',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'failed');
	context.DetectRuntime();
	runtimePost.success('');
	detectionRequest.success({request:context.vpnmgr_lastRequestId,state:'done',version:'2.6.12',number:'261200',family:'modern',status:'unknown'});
	assert.strictEqual(context.vpnmgr_runtimeState,'failed','unknown runtime status must explicitly use the legacy family');
	context.DetectRuntime();
	runtimePost.error();
	assert.strictEqual(context.vpnmgr_runtimeState,'loading','a transport error still polls the event status');
	assert.strictEqual(jqueryState.properties['#btnSaveConfig:disabled'],true);
}

function testRuntime404RetryAndCorrelation(){
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
	assert.strictEqual(detectionCount,1);
	assert.strictEqual(context.vpnmgr_runtimeState,'loading','initial asynchronous 404 must be retried');
	assert.strictEqual(typeof context.queuedTimer,'function');
	context.queuedTimer();
	assert.strictEqual(detectionCount,2);
	assert.strictEqual(context.vpnmgr_runtimeState,'known','matching delayed status should complete the check');
	assert.strictEqual(calls.filter(function(call){return call.url == '/start_apply.htm';}).length,1,'status retries must not repost the runtime event');
}

function testStaleRuntimeResponseIgnored(){
	var calls = [];
	jqueryState.ajax = function(options){ calls.push(options); };
	context.DetectRuntime();
	var oldPost = calls[0];
	var oldId = context.vpnmgr_lastRequestId;
	oldPost.success('');
	var oldStatus = calls[1];
	context.DetectRuntime();
	var currentPost = calls[2];
	var currentId = context.vpnmgr_lastRequestId;
	currentPost.success('');
	var currentStatus = calls[3];
	oldStatus.success({request:oldId,state:'done',version:'2.6',number:'260000',family:'modern',status:'detected'});
	assert.strictEqual(context.vpnmgr_runtimeState,'loading','a stale response must not satisfy the newer check');
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
	context.window.vpnmgr_settings = [['vpn1_countryid','440'],['vpn1_cityid','918']];
	var unavailableProvider = context.BuildCustomSettingsPayload('2222222222222222222');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_countryname,'Country 1');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_cityname,'City 1');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_countryid,'440','missing provider data must retain the saved country ID');
	assert.strictEqual(unavailableProvider.vpnmgr_vpn1_cityid,'918','missing provider data must retain the saved city ID');
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
	assert.ok(jqueryState.text['#vpnmgr_apply_summary'].indexOf('stale') != -1);

	var malformed = applyResponse(pending.requestId,'done',true);
	malformed.clients.pop();
	assert.strictEqual(context.ApplyResponseValid(malformed),false);
	var incompleteDone = applyResponse(pending.requestId,'done',true);
	incompleteDone.clients[0].status = 'pending';
	assert.strictEqual(context.ApplyResponseValid(incompleteDone),false);

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
	context.ContinueApplyChecking();
	assert.strictEqual(context.vpnmgr_pendingApply,null,'late completion should finish the original request');
	assert.strictEqual(calls.filter(function(call){return call.url == '/start_apply.htm' && call.data.filter(function(field){return field.name == 'action_script';})[0].value.indexOf('start_vpnmgrapply_') == 0;}).length,0);
	assert.ok(jqueryState.text['#vpnmgr_apply_summary'].indexOf('Settings saved') != -1);
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
	assert.strictEqual(calls[2].url,'/ext/vpnmgr/runtime/apply_'+requestId+'.json');
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
	assert.ok(jqueryState.text['#vpnmgr_apply_summary'].indexOf('VPN Client 2') != -1);
	assert.strictEqual(jqueryState.shown['#btnReloadSettings'],true,'reload remains a user action');
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

testLoadedSettingsContract();
testRequestIdsAndRuntimeContract();
testRuntime404RetryAndCorrelation();
testStaleRuntimeResponseIgnored();
testFreshPayloadAndAllSlots();
testStatusCorrelationAndLateCompletion();
testPrepareGateAndNoncePost();
testPartialApplyResult();
process.stdout.write('Web UI contract checks passed.\n');
