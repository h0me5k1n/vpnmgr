'use strict';

var assert = require('assert');
var fs = require('fs');
var vm = require('vm');

var jqueryState = {ajax:null,text:{},shown:{},properties:{}};
var consoleSnapshots = [];
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
	setTimeout:function(callback){ context.queuedTimer = callback; return 1; },
	clearTimeout:function(){},
	alert:function(message){ context.lastAlert = message; },
	console:{log:function(prefix,snapshot){consoleSnapshots.push(JSON.parse(snapshot));},error:function(prefix,snapshot){consoleSnapshots.push(JSON.parse(snapshot));}},
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
	context.ContinueApplyChecking();
	assert.strictEqual(context.vpnmgr_pendingApply,null,'late completion should finish the original request');
	assert.strictEqual(calls.filter(function(call){return call.url == '/start_apply.htm' && call.data.filter(function(field){return field.name == 'action_script';})[0].value.indexOf('start_vpnmgrapply_') == 0;}).length,0);
	assert.ok(context.vpnmgr_lastApplyDiagnostic.indexOf('Settings saved') != -1);
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
	assert.strictEqual(statusReads,1,'the ready reservation is recognized after POST loss');
	assert.ok(context.vpnmgr_lastApplyDiagnostic.indexOf('remains reserved') != -1,'ready state explains uncertainty without a malformed-response message');
	pending.startedAt = 0;
	context.PollApplyStatus(pending);
	assert.strictEqual(pending.timedOut,true);
	assert.strictEqual(frozenPassword.disabled,true);
	assert.strictEqual(jqueryState.shown['#btnReloadSettings'],true,'timeout offers reload as an explicit escape');
	context.ContinueApplyChecking();
	assert.strictEqual(recoverPosts,1);
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
		if(initialState == 'running'){
			assert.strictEqual(context.vpnmgr_pendingApply,current.pending,'recovery does not cancel a running application');
			statusState = 'done';
			context.queuedTimer();
		}
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
	var success = {requestId:'1818181818181818181',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = success;
	context.lastAlert = undefined;
	htmlNode.style.overflow = 'scroll';
	context.StartApplyOverlay();
	assert.strictEqual(loadingState.visible,true);
	assert.strictEqual(htmlNode.style.overflow,'hidden');
	assert.strictEqual(loadingState.showArguments[loadingState.showArguments.length-1],0,'native firmware loading helper receives no countdown arguments');
	assert.ok(context.vpnmgr_recoveryRow && context.vpnmgr_recoveryRow.parentNode === loadingTable,'recovery controls are placed in a native loadingBlock table row');
	var done = applyResponse(success.requestId,'done',true,['unmanaged','unmanaged','unmanaged','unmanaged','unmanaged']);
	context.FinishApplyResult(success,done);
	assert.strictEqual(loadingState.visible,false,'successful completion hides the native overlay');
	assert.strictEqual(loadingState.hideCalls,initialHideCount+1);
	assert.strictEqual(htmlNode.style.overflow,'scroll','original page scrolling is restored');
	assert.deepStrictEqual(context.lastScroll,[17,29]);
	assert.strictEqual(recoveryControls.parentNode,recoveryHome,'static recovery controls return to their home after completion');
	assert.strictEqual(context.lastAlert,undefined,'success is silent');
	assert.strictEqual(context.reloadCount,initialReloadCount+1,'confirmed success reloads the page');

	var failure = {requestId:'1919191919191919191',phase:'apply',polling:true};
	context.vpnmgr_pendingApply = failure;
	context.StartApplyOverlay();
	var failed = applyResponse(failure.requestId,'done',true,['applied','failed','unmanaged','applied','unmanaged']);
	failed.clients[1].connection = 'failed';
	context.FinishApplyResult(failure,failed);
	assert.strictEqual(loadingState.visible,false,'terminal failure hides the native overlay');
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

testLoadedSettingsContract();
testRequestIdsAndRuntimeContract();
testRuntime404RetryAndCorrelation();
testStaleRuntimeResponseIgnored();
testFreshPayloadAndAllSlots();
testStatusCorrelationAndLateCompletion();
testPrepareGateAndNoncePost();
testRecoveryAfterLostSettingsPost();
testRecoveryLossAndLateApplyAreUncertainSafe();
testPartialApplyResult();
testVerifiedStoppedConnectionStatus();
testMalformedClientKeepsPollingReachable();
testNativeOverlayCleanup();
testNativeStatusPollingPreserved();
testAllowlistedConsoleSnapshotsAndDedupe();
process.stdout.write('Web UI contract checks passed.\n');
