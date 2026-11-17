'use strict';

// One isolated Chrome or Firefox session against loopback fixtures; never contacts a router.
// Requires an existing compatible browser/driver, with no package installs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {spawn} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const template = fs.readFileSync(path.join(root, 'vpnmgr_www.asp'), 'utf8');
const jquery = fs.readFileSync(path.join(root, 'www/jquery.js'));
const script = fs.readFileSync(path.join(root, 'vpnmgr_www.js'));
const nativePopupPath = process.env.MERLIN_POPUP_JS;
const nativePopup = nativePopupPath ? fs.readFileSync(path.resolve(nativePopupPath)) : null;
const browserType = String(process.env.WEBUI_BROWSER || 'chrome').toLowerCase();
if (!['chrome','firefox'].includes(browserType)) throw new Error('WEBUI_BROWSER must be chrome or firefox');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'vpnmgr-browser-'));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const started = Date.now();
let state, session, driver, driverUrl, pageUrl, bidiSocket;
const bidiLogs = [];
const bidiPending = new Map();
let bidiCommandId = 0;
const firmware = `window.fixtureErrors=[];window.fixtureAlerts=[];window.fixtureShowLoadingArgs=[];window.fixtureLoadingVisible=false;
window.addEventListener('error',function(e){fixtureErrors.push(e.message);});
window.alert=function(s){fixtureAlerts.push(s);};window.stopFlag=0;
window.show_menu=function(){
  var mask=document.getElementById('Loading');
  if(!mask||document.getElementById('loadingBlock'))return;
  var table=document.createElement('table');table.id='loadingBlock';table.className='loadingBlock';
  var row=table.insertRow(-1);var imageCell=row.insertCell(-1);imageCell.style.width='20%';
  var image=document.createElement('img');image.src='/images/loading.gif';image.alt='';imageCell.appendChild(image);
  var textCell=row.insertCell(-1);var main=document.createElement('div');main.id='proceeding_main_txt';main.textContent='Please wait';textCell.appendChild(main);
  var detail=document.createElement('div');detail.id='proceeding_txt';textCell.appendChild(detail);mask.appendChild(table);
};
${nativePopup ? '' : `window.showLoading=function(){fixtureShowLoadingArgs.push(arguments.length);disableCheckChangedStatus();if(window.scrollTo)window.scrollTo(0,0);document.documentElement.style.overflow='hidden';var mask=document.getElementById('Loading');if(mask)mask.style.visibility='visible';fixtureLoadingVisible=true;};
window.hideLoading=function(){var mask=document.getElementById('Loading');if(mask)mask.style.visibility='hidden';document.documentElement.style.overflow='';fixtureLoadingVisible=false;};`}
window.showhide=function(id,show){var e=document.getElementById(id);if(e)e.style.display=show?'':'none';};
window.cookie={get:function(){return null;},set:function(){}};
window.nd=function(){};window.overlib=function(){};
window.switchType=function(e,checked){e.type=checked?'text':'password';};
window.fixtureInstallLoadingStyles=function(){var style=document.createElement('style');style.textContent='.popup_bg{position:absolute;top:0;left:0;width:100%;height:100%;z-index:9999;background:#444F53;opacity:.94;visibility:hidden;overflow:hidden}.loadingBlock{position:absolute;width:400px;font-size:20px;color:white;font-weight:bold;background:black;border-radius:10px;top:0;z-index:200}';document.head.appendChild(style);};
window.fixtureInstallLoadingStyles();`;
const general = `window.showtext=function(element,text){if(element)element.innerHTML=text;};window.translate=function(text){return text;};window.re_mode='0';window.disableCheckChangedStatus=function(){window.stopFlag=1;};`;

function fixture(version = '2.6.12') {
  const config = {};
  for (let i = 1; i <= 5; i++) {
    Object.assign(config, Object.fromEntries(Object.entries({managed:i <= 3 ? 'true':'false',provider:'NordVPN',customsettings:'true',protocol:i === 2 ? 'TCP':'UDP',type:'Standard',countryname:'Australia',countryid:'13',cityname:'Sydney',cityid:'100',schenabled:'false',schhours:'*',schmins:'0',schdays:'*'}).map(([k,v]) => ['vpn'+i+'_'+k,v])));
  }
  return {version, family:version === '2.5.9' ? 'legacy':'modern',config,providers:'nordvpn|NordVPN\npia|PIA\n',records:new Map(),posts:[],recoveries:[],redirects:0,delayDetection:false,busy:false,failSlot:0,stoppedSlot:0,hold:false,wrongStatus:false,loseSettingsPost:false,recoveryLoss:false,recoveryAgeMs:0,runningApply:false,completeRunning:false,configFailure:false,custom:{vpnmgr_version_local:'fixture',vpnmgr_version_server:'fixture',vpnmgr_version_source:'fixture@1234567',unrelated_setting:'preserve=\\value'},creds:{}};
}

function clients() {
  return Array.from({length:5}, (_,index) => ({slot:index+1,status:state.config['vpn'+(index+1)+'_managed'] !== 'true' ? 'unmanaged':state.failSlot === index+1 ? 'failed':'applied',connection:state.config['vpn'+(index+1)+'_managed'] !== 'true' ? 'not_requested':state.failSlot === index+1 ? 'failed':state.stoppedSlot === index+1 ? 'verified_stopped':'connected'}));
}
function respond(res, code, body, type = 'text/plain') {
  res.writeHead(code, {'content-type':type,'cache-control':'no-store'});
  res.end(body);
}
function render() {
  return template.replace(/<% get_custom_settings\(\); %>/g, JSON.stringify(state.custom))
    .replace(/<% nvram_(?:clean_)?get\("([^"]+)"\); %>/g, (_,key) => {
      const match = /^vpn_client([1-5])_(username|password|desc)$/.exec(key);
      const value = match ? state.creds[key] || (match[2] === 'desc' ? 'Fixture client '+match[1] : match[2]+'-'+match[1]) : key === 'preferred_lang' ? 'EN' : 'fixture';
      return String(value).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;');
    });
}
const server = http.createServer(async (req,res) => {
  try {
    const url = new URL(req.url,'http://127.0.0.1');
    const pathname = url.pathname;
    if (pathname === '/vpnmgr.asp') { state.pageLoads=(state.pageLoads || 0)+1; return respond(res,200,render(),'text/html'); }
    if (pathname === '/ext/vpnmgr/www/jquery.js') return respond(res,200,jquery,'application/javascript');
    if (pathname === '/ext/vpnmgr/vpnmgr_www.js') return respond(res,200,script,'application/javascript');
    if (pathname === '/state.js') return respond(res,200,firmware,'application/javascript');
    if (pathname === '/general.js') return respond(res,200,general,'application/javascript');
    if (pathname === '/popup.js') return respond(res,200,nativePopup || '', 'application/javascript');
    if (pathname === '/ext/vpnmgr/providers.htm') return respond(res,200,state.providers);
    if (pathname === '/ext/vpnmgr/nordvpn_countrydata.htm') return respond(res,200,JSON.stringify([{id:13,name:'Australia',cities:[{id:100,name:'Sydney'}]},{id:14,name:'Canada',cities:[{id:200,name:'Toronto'}]}]),'application/json');
    if (pathname === '/ext/vpnmgr/pia_countrydata.htm') return respond(res,200,'AU_Sydney\nUK_London\n');
    if (pathname === '/ext/vpnmgr/config.htm') return respond(res,state.configFailure ? 503:200,Object.entries(state.config).map(([k,v]) => k+'='+v).join('\n'));
    if (pathname === '/unexpected-redirect') { state.redirects++; return respond(res,500,'Firmware response executed'); }
    if (pathname === '/start_apply.htm') {
      let body = '';
      for await (const part of req) body += part;
      const fields = new URLSearchParams(body);
      const action = fields.get('action_script');
      state.posts.push({action,fields});
      const match = /^start_vpnmgr(runtime|prepare|apply|recover)_(\d+)$/.exec(action || '');
      assert.ok(match, 'unexpected control action '+action);
      const [,kind,id] = match;
      if (kind === 'runtime') {
        state.records.set('detection_'+id+'.json',{request:id,state:'done',version:state.version,number:state.version ? '2006012':'',family:state.version ? state.family:'legacy',status:state.version ? 'detected':'unknown',misses:state.delayDetection ? 1:0});
        state.delayDetection = false;
      } else if (kind === 'prepare') {
        assert.equal(fields.has('amng_custom'),false,'reservation must precede the settings payload');
        state.records.set('apply_'+id+'.json',{request:id,state:state.busy ? 'busy':'ready',readyAt:Date.now()-state.recoveryAgeMs});
        state.recoveryAgeMs = 0;
      } else if (kind === 'apply') {
        // A rejected gateway response models no firmware delivery. Destroying a
        // reused socket can make Chrome transparently retry the POST itself.
        if (state.loseSettingsPost) { state.loseSettingsPost = false; return respond(res,503,'Not delivered to firmware'); }
        assert.equal(state.records.get('apply_'+id+'.json').state,'ready','apply must own a ready reservation');
        const payload = JSON.parse(fields.get('amng_custom'));
        assert.equal(payload.vpnmgr_request_id,id);
        state.lastPayload = payload;
        for (const [key,value] of Object.entries(payload)) {
          if (/^vpnmgr_vpn[1-5]_/.test(key)) {
            const short = key.slice(7);
            const credential = /^vpn([1-5])_(usn|pwd)$/.exec(short);
            if (credential) state.creds['vpn_client'+credential[1]+'_'+(credential[2] === 'usn' ? 'username':'password')] = value;
            else state.config[short] = String(value);
          }
        }
        state.records.set('apply_'+id+'.json',state.runningApply ? {request:id,state:'running',merged:true,clients:Array.from({length:5},(_,index)=>({slot:index+1,status:'pending',connection:'unknown'})),message:'running'} : {request:id,state:'done',merged:true,clients:clients(),message:'complete'});
        state.runningApply = false;
      } else {
        assert.equal(fields.has('amng_custom'),false,'recovery control must never resend settings');
        state.recoveries.push({id,state:state.records.get('apply_'+id+'.json').state});
        if (state.recoveryLoss) { state.recoveryLoss = false; return respond(res,503,'Recovery not delivered to firmware'); }
        const record = state.records.get('apply_'+id+'.json');
        if (record && record.state === 'ready' && Date.now()-record.readyAt >= 60000) {
          state.records.set('apply_'+id+'.json',{request:id,state:'failed',merged:false,clients:Array.from({length:5},(_,index)=>({slot:index+1,status:'pending',connection:'unknown'})),message:'expired'});
        }
      }
      // The real firmware returns executable callbacks/reload code. AJAX must leave this inert.
      return respond(res,200,'<script>parent.location.replace("/unexpected-redirect")</script>','text/html');
    }
    if (pathname.startsWith('/ext/vpnmgr/runtime/')) {
      const name = pathname.split('/').pop();
      let result = state.records.get(name);
      if (result && name.startsWith('apply_') && result.state === 'running' && state.completeRunning) {
        result = {request:result.request,state:'done',merged:true,clients:clients(),message:'complete'};
        state.records.set(name,result);
        state.completeRunning = false;
      }
      if (!result || result.misses-- > 0 || (name.startsWith('apply_') && state.hold && result.state === 'done')) return respond(res,404,'Not ready');
      return respond(res,200,JSON.stringify(state.wrongStatus && result.state === 'done' && name.startsWith('apply_') ? {...result,request:'999'}:result),'application/json');
    }
    if (/\.(js|css|png|gif)$/.test(pathname)) return respond(res,200,'',pathname.endsWith('.js') ? 'application/javascript':'text/plain');
    return respond(res,404,'Fixture route absent');
  } catch (error) { state.serverError = error.stack; respond(res,500,'Fixture assertion failed'); }
});

async function wd(method, suffix, body) {
  const response = await fetch(driverUrl+(session ? '/session/'+session:'')+suffix,{method,headers:{'content-type':'application/json'},body:body === undefined ? undefined:JSON.stringify(body)});
  const data = await response.json();
  if (!response.ok || data.value?.error) throw new Error(JSON.stringify(data.value));
  return data.value;
}
const execute = scriptText => wd('POST','/execute/sync',{script:scriptText,args:[]});
function connectBiDi(socketUrl) {
  return new Promise((resolve,reject) => {
    bidiSocket = new WebSocket(socketUrl);
    bidiSocket.addEventListener('open',resolve,{once:true});
    bidiSocket.addEventListener('error',reject,{once:true});
    bidiSocket.addEventListener('message',event => {
      let message;
      try { message = JSON.parse(event.data); } catch (_) { return; }
      if (message.id !== undefined && bidiPending.has(message.id)) {
        const pending = bidiPending.get(message.id);
        bidiPending.delete(message.id);
        if (message.type === 'error') pending.reject(new Error(message.message || message.error));
        else pending.resolve(message.result);
      }
      if (message.method === 'log.entryAdded' && message.params) {
        bidiLogs.push({text:String(message.params.text || ''),level:String(message.params.level || ''),type:String(message.params.type || '')});
      }
    });
  });
}
function sendBiDi(method,params) {
  const id = ++bidiCommandId;
  return new Promise((resolve,reject) => {
    const timeout = setTimeout(() => { bidiPending.delete(id); reject(new Error('WebDriver BiDi command timed out: '+method)); },5000);
    bidiPending.set(id,{resolve:function(result){clearTimeout(timeout);resolve(result);},reject:function(error){clearTimeout(timeout);reject(error);}});
    bidiSocket.send(JSON.stringify({id,method,params}));
  });
}
async function browserConsoleMessages() {
  if (browserType === 'firefox') return bidiLogs.map(entry => entry.text);
  return (await wd('POST','/log',{type:'browser'})).map(entry => entry.message);
}
async function until(expression, label, limit = 15000) {
  const deadline = Date.now()+limit;
  while (Date.now() < deadline) {
    if (state.serverError) throw new Error(state.serverError);
    const errors = await execute('return window.fixtureErrors || []');
    if (errors !== null) assert.deepEqual(errors,[],label+' JavaScript errors');
    if (await execute('return !!('+expression+')')) return;
    await pause(100);
  }
  throw new Error('Timed out: '+label+'; '+await execute('return JSON.stringify({config:window.vpnmgr_configState,runtime:window.vpnmgr_runtimeState,apply:window.vpnmgr_lastApplyDiagnostic,loading:document.querySelector("#Loading").style.visibility,alerts:window.fixtureAlerts})'));
}
async function untilHost(predicate, label, limit = 15000) {
  const deadline = Date.now()+limit;
  while (Date.now() < deadline) {
    if (state.serverError) throw new Error(state.serverError);
    if (predicate()) return;
    await pause(100);
  }
  throw new Error('Timed out waiting for fixture: '+label);
}
async function load() {
  await wd('POST','/url',{url:pageUrl});
  await until('window.vpnmgr_initComplete && !document.querySelector("#btnSaveConfig").disabled','page ready');
  assert.equal(await execute('return document.querySelectorAll("[id^=table_config_vpn]").length'),5);
  assert.equal(await execute('return !!document.querySelector("#vpnmgr_runtime_status").closest("#table_scripttools")'),true,'runtime readout remains in Utilities');
  assert.equal(await execute('return !!document.querySelector("#vpnmgr_config_status").closest("#table_runtime_status")'),true,'saved-settings load status stays in its original table');
  assert.equal(await execute('return document.querySelector("#vpnmgr_apply_summary") === null && document.querySelector("#vpnmgr_client_status") === null'),true,'permanent apply and client status rows are removed');
}
async function click(selector) {
  await execute('document.querySelector('+JSON.stringify(selector)+').click();');
}
async function clickVisible(selector) {
  const element = await wd('POST','/element',{using:'css selector',value:selector});
  const id = element['element-6066-11e4-a52e-4f735466cecf'] || element.ELEMENT;
  assert.ok(id,'visible control exists: '+selector);
  await wd('POST','/element/'+id+'/click',{});
}
async function save() {
	const pageLoadsBefore = state.pageLoads;
  // Observe the synchronous click before a fast fixture can finish its AJAX
  // round trips. No artificial production delay is needed to see the overlay.
  const started = await execute('document.querySelector("#btnSaveConfig").click();return {active:window.vpnmgr_applyOverlayActive,visible:document.querySelector("#Loading").style.visibility === "visible",untimed:window.fixtureShowLoadingArgs.length ? window.fixtureShowLoadingArgs[window.fixtureShowLoadingArgs.length-1] === 0 : document.querySelector("#proceeding_main_txt").textContent.indexOf("Please wait") !== -1,controls:document.querySelector("#loadingBlock").contains(document.querySelector("#vpnmgr_recovery_controls")),text:document.querySelector("#Loading").innerText,exposesCodes:/(verified_stopped|merged|unmanaged|pending|applied)/.test(document.body.innerText)};');
  assert.equal(started.active,true,'native loading overlay starts');
  assert.equal(await execute('return window.stopFlag'),0,'native overlay preserves firmware status/autologout polling');
  assert.equal(started.visible,true,'apply uses the visible full-screen mask');
  assert.equal(started.untimed,true,'native loading helper is called without a countdown');
  assert.equal(started.controls,true,'recovery controls live in a native loadingBlock table');
  assert.match(started.text,/Please wait|Applying settings/);
  assert.equal(started.exposesCodes,false,'the overlay does not expose backend status codes');
  await until('!window.vpnmgr_pendingApply && (!document.querySelector("#btnSaveConfig") || !document.querySelector("#btnSaveConfig").disabled)','apply terminal');
  if(!state.busy && !state.failSlot) {
    await untilHost(() => state.pageLoads === pageLoadsBefore+1,'confirmed success reloads from saved settings');
    await until('window.vpnmgr_initComplete && document.querySelector("#btnSaveConfig") && !document.querySelector("#btnSaveConfig").disabled','reloaded settings ready');
  }
  else assert.equal(state.pageLoads,pageLoadsBefore,'failed apply retains the current page');
  await until('document.querySelector("#Loading").style.visibility !== "visible"','native overlay cleanup');
  assert.equal(await execute('return !/(merged|unmanaged|pending|applied|verified_stopped)/.test(document.querySelector("#Loading").innerText)'),true,'final loading text exposes no backend status codes');
  assert.equal(state.redirects,0);
}

async function run() {
  state = fixture();
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  pageUrl = 'http://127.0.0.1:'+server.address().port+'/vpnmgr.asp';
  // Have the selected driver choose an unused port and parse its startup announcement.
  const firefox = browserType === 'firefox';
  const driverCommand = firefox ? (process.env.GECKODRIVER || 'geckodriver') : (process.env.CHROMEDRIVER || 'chromedriver');
  const driverArgs = ['--port=0'];
  if (firefox) driverArgs.push('--websocket-port=0','--profile-root',profile);
  driver = spawn(driverCommand,driverArgs,{stdio:['ignore','pipe','pipe']});
  let output = '';
  driver.stdout.on('data',data => { output += data; });
  driver.stderr.on('data',data => { output += data; });
  driver.on('error',error => { output += error.message; });
  const startupPattern = firefox ? /Listening on (?:\[[^\]]+\]|[^:\s]+):(\d+)/ : /started successfully on port (\d+)/;
  for (let count=0; count<100 && !startupPattern.test(output); count++) await pause(100);
  const port = startupPattern.exec(output);
  assert.ok(port,(firefox ? 'geckodriver':'ChromeDriver')+' did not start: '+output);
  driverUrl = 'http://127.0.0.1:'+port[1];
  let capabilities;
  if (firefox) {
    // geckodriver creates and owns a disposable session profile and removes it when deleted.
    const options = {args:['-headless'],binary:process.env.FIREFOX_BINARY || '/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox'};
    capabilities = {browserName:'firefox','moz:firefoxOptions':options,webSocketUrl:true};
  }
  else {
    const options = {args:['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--user-data-dir='+profile]};
    if (process.env.CHROME_BINARY) options.binary = process.env.CHROME_BINARY;
    capabilities = {browserName:'chrome','goog:chromeOptions':options,'goog:loggingPrefs':{browser:'ALL'}};
  }
  let created;
  try { created = await wd('POST','/session',{capabilities:{alwaysMatch:capabilities}}); }
  catch (error) { throw new Error(error.message+'\n'+(firefox ? 'geckodriver' : 'ChromeDriver')+' output:\n'+output); }
  session = created.sessionId;
  if (firefox) {
    const socketUrl = created.capabilities && created.capabilities.webSocketUrl;
    assert.ok(socketUrl,'Firefox session did not return the requested WebDriver BiDi URL');
    await connectBiDi(socketUrl);
    await sendBiDi('session.subscribe',{events:['log.entryAdded']});
  }

  for (const version of ['2.5.9','2.6.12','2.7.8','']) {
    state = fixture(version);
    if(version === '2.6.12') state.providers = 'nordvpn|NordVPN\n';
    state.delayDetection = true;
    await load();
    assert.equal(await execute('return vpnmgr_runtime.family'),version === '2.5.9' || !version ? 'legacy':'modern');
    assert.equal(await execute('return vpnmgr_runtimeState'),version ? 'known':'unknown');
    await click('#vpnmgr_vpn1_tcp');
    await click('#vpnmgr_vpn2_udp');
    await click('#vpnmgr_vpn3_custsettings_false');
    if(version === '2.7.8') {
      await click('#vpnmgr_vpn4_man_true');
      await click('#vpnmgr_vpn5_man_true');
      await click('#vpnmgr_vpn4_tcp');
      await click('#vpnmgr_vpn5_custsettings_false');
    }
    await execute('document.form.vpnmgr_vpn3_pwd.value="fixture=secret\\\\value";');
    await save();
    assert.equal(state.lastPayload.vpnmgr_vpn1_protocol,'TCP');
    assert.equal(state.lastPayload.vpnmgr_vpn2_protocol,'UDP');
    assert.equal(state.lastPayload.vpnmgr_vpn3_customsettings,'false');
    assert.equal(state.lastPayload.vpnmgr_vpn3_pwd,'fixture=secret\\value');
    assert.equal(state.lastPayload.unrelated_setting,'preserve=\\value');
    assert.equal(state.lastPayload.vpnmgr_version_source,'fixture@1234567');
    if(version === '2.7.8') {
      assert.equal(state.lastPayload.vpnmgr_vpn4_managed,'true');
      assert.equal(state.lastPayload.vpnmgr_vpn4_protocol,'TCP');
      assert.equal(state.lastPayload.vpnmgr_vpn5_managed,'true');
      assert.equal(state.lastPayload.vpnmgr_vpn5_customsettings,'false');
    }
    assert.equal(await execute('return document.form.vpnmgr_vpn1_protocol.value'),'TCP');
    assert.equal(await execute('return document.form.vpnmgr_vpn3_pwd.value'),'fixture=secret\\value');
    await click('#vpnmgr_vpn1_udp');
    await click('#vpnmgr_vpn3_custsettings_true');
    await save();
    assert.equal(state.lastPayload.vpnmgr_vpn1_protocol,'UDP');
    assert.equal(state.lastPayload.vpnmgr_vpn3_customsettings,'true');
    assert.equal(Array.isArray(state.lastPayload.vpnmgr_vpn1_protocol),false);
  }

  state = fixture();
  await load();
  await click('#vpnmgr_vpn1_prov_pia');
  await save();
  assert.equal(state.lastPayload.vpnmgr_vpn1_provider,'PIA');
  assert.equal(await execute('return document.form.vpnmgr_vpn1_provider.value'),'PIA');
  await click('#vpnmgr_vpn1_prov_nordvpn');
  await click('#vpnmgr_vpn1_sch_true');
  await execute('document.form.vpnmgr_vpn1_schhours.value="1,6";document.form.vpnmgr_vpn1_schmins.value="15";');
  await click('#vpnmgr_vpn1_mon');
  await save();
  assert.equal(state.lastPayload.vpnmgr_vpn1_provider,'NordVPN');
  assert.equal(state.lastPayload.vpnmgr_vpn1_schhours,'1,6');
  assert.equal(state.lastPayload.vpnmgr_vpn1_schmins,'15');

  state.busy = true;
  const applies = state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length;
  await save();
  assert.equal(state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length,applies);
  assert.match(await execute('return fixtureAlerts[fixtureAlerts.length-1]'),/Another save is in progress.*not submitted/);
  state.busy = false;
  state.failSlot = 2;
  await save();
  assert.match(await execute('return fixtureAlerts[fixtureAlerts.length-1]'),/failed for VPN Client 2/);
  assert.equal(await execute('return document.querySelector("#vpnmgr_apply_summary") === null && document.querySelector("#vpnmgr_client_status_2") === null'),true);

  state.hold = true;
  state.failSlot = 0;
  await click('#btnSaveConfig');
  await until('vpnmgr_pendingApply && vpnmgr_pendingApply.phase === "apply"','pending apply');
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.disabled'),true);
  await execute('vpnmgr_pendingApply.startedAt=0;PollApplyStatus(vpnmgr_pendingApply);');
  assert.equal(await execute('return vpnmgr_pendingApply.polling'),false);
  const applyPostsBeforeRecovery = state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length;
  const recoveriesBefore = state.recoveries.length;
  const pageLoadsBeforeLateResult = state.pageLoads;
  state.hold = false;
  state.wrongStatus = true;
  await clickVisible('#btnContinueApply');
  await until('window.vpnmgr_lastApplyDiagnostic.indexOf("stale") !== -1','stale result rejected');
  assert.equal(state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length,applyPostsBeforeRecovery,'continue checking must not repost a payload');
  assert.equal(state.recoveries.length,recoveriesBefore+1,'continue checking requests safe same-ID recovery');
  state.wrongStatus = false;
  await until('!window.vpnmgr_pendingApply && (!document.querySelector("#btnSaveConfig") || !document.querySelector("#btnSaveConfig").disabled)','late result');
  await untilHost(() => state.pageLoads === pageLoadsBeforeLateResult+1,'late confirmed success reloads saved settings');
  await until('window.vpnmgr_initComplete && document.querySelector("#btnSaveConfig") && !document.querySelector("#btnSaveConfig").disabled','late result reload ready');
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.disabled'),false);

  state = fixture();
  state.stoppedSlot = 1;
  await load();
  await save();
  assert.equal(state.records.get('apply_'+state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).slice(-1)[0].action.match(/_(\d+)$/)[1]+'.json').clients[0].connection,'verified_stopped');
  const stoppedId = state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).slice(-1)[0].action.match(/_(\d+)$/)[1];
  const browserLog = await browserConsoleMessages();
  assert.equal(browserLog.some(message => message.includes(stoppedId) && message.includes('verified_stopped')),true,'plain-text console diagnostics remain inspectable across the successful reload');
  assert.equal(await execute('return fixtureAlerts.length'),0,'verified stopped completes without an error alert');

  state = fixture();
  state.loseSettingsPost = true;
  state.recoveryAgeMs = 61000;
  await load();
  await click('#btnSaveConfig');
  await until('vpnmgr_pendingApply && vpnmgr_pendingApply.phase === "apply"','lost settings POST after ready');
  await untilHost(() => state.posts.some(post => post.action.startsWith('start_vpnmgrapply_')),'lost settings POST reaches fixture');
  await execute('vpnmgr_pendingApply.startedAt=0;PollApplyStatus(vpnmgr_pendingApply);');
  await until('vpnmgr_pendingApply.timedOut && !vpnmgr_pendingApply.polling','lost POST timeout');
  const lostApplyCount = state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length;
  await clickVisible('#btnContinueApply');
  await until('!vpnmgr_pendingApply && !document.querySelector("#btnSaveConfig").disabled','expired reservation recovery');
  assert.equal(state.recoveries.length,1);
  assert.equal(state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length,lostApplyCount,'recovery must not repeat the lost payload');
  assert.match(await execute('return vpnmgr_lastApplyDiagnostic'),/expired/);
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.disabled'),false);

  state = fixture();
  state.loseSettingsPost = true;
  state.recoveryLoss = true;
  state.recoveryAgeMs = 61000;
  await load();
  await click('#btnSaveConfig');
  await until('vpnmgr_pendingApply && vpnmgr_pendingApply.phase === "apply"','recovery POST loss setup');
  await untilHost(() => state.posts.some(post => post.action.startsWith('start_vpnmgrapply_')),'apply request reaches fixture before recovery loss');
  await execute('vpnmgr_pendingApply.startedAt=0;PollApplyStatus(vpnmgr_pendingApply);');
  await until('vpnmgr_pendingApply.timedOut && !vpnmgr_pendingApply.polling','recovery POST loss timeout');
  const recoveryLossApplyCount = state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length;
  await clickVisible('#btnContinueApply');
  await until('vpnmgr_pendingApply && vpnmgr_pendingApply.polling && vpnmgr_lastApplyDiagnostic.indexOf("remains reserved") !== -1','recovery acknowledgement lost');
  assert.equal(state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length,recoveryLossApplyCount);
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.disabled'),true,'uncertain recovery keeps config frozen');
  assert.equal(await execute('return document.querySelector("#btnReloadSettings").style.display !== "none"'),true,'reload remains an explicit escape');

  state = fixture();
  state.runningApply = true;
  await load();
  await click('#btnSaveConfig');
  await until('vpnmgr_pendingApply && vpnmgr_pendingApply.phase === "apply" && Object.keys(vpnmgr_lastApplyLog[vpnmgr_pendingApply.requestId] || {}).some(function(item){return item.indexOf("\\"state\\":\\"running\\"") !== -1;})','running apply');
  const runningId = state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).slice(-1)[0].action.match(/_(\d+)$/)[1];
  await execute('vpnmgr_pendingApply.startedAt=0;PollApplyStatus(vpnmgr_pendingApply);');
  await until('vpnmgr_pendingApply.timedOut && !vpnmgr_pendingApply.polling','running apply timeout');
  await clickVisible('#btnContinueApply');
  await untilHost(() => state.recoveries.length === 1,'running apply recovery request');
  assert.equal(state.recoveries[0].state,'running','recovery must leave running work unchanged');
  state.completeRunning = true;
  const pageLoadsBeforeRunningFinish = state.pageLoads;
  await until('!window.vpnmgr_pendingApply && (!document.querySelector("#btnSaveConfig") || !document.querySelector("#btnSaveConfig").disabled)','running apply completes');
  await untilHost(() => state.pageLoads === pageLoadsBeforeRunningFinish+1,'running apply success reloads saved settings');
  await until('window.vpnmgr_initComplete && document.querySelector("#btnSaveConfig") && !document.querySelector("#btnSaveConfig").disabled','running apply reload ready');
  assert.equal(state.records.get('apply_'+runningId+'.json').state,'done');
  assert.equal(state.posts.filter(post => post.action.startsWith('start_vpnmgrapply_')).length,1);

  state = fixture();
  state.config.vpn1_cityname = 'Melbourne';
  state.config.vpn1_cityid = '999';
  await load();
  assert.equal(await execute('return document.form.vpnmgr_vpn1_cityname.value'),'Melbourne');
  await save();
  assert.equal(state.lastPayload.vpnmgr_vpn1_cityid,'999','unchanged unavailable city keeps its saved ID');
  await execute('document.form.vpnmgr_vpn1_cityname.value="Sydney";');
  await save();
  assert.equal(state.lastPayload.vpnmgr_vpn1_cityid,100,'changed city uses its current catalogue ID');
  await execute('var country=document.form.vpnmgr_vpn1_countryname;country.value="Canada";setCitiesforCountry(country);document.form.vpnmgr_vpn1_cityname.value="Toronto";');
  await save();
  assert.equal(state.lastPayload.vpnmgr_vpn1_countryid,14,'changed country uses current catalogue ID');
  assert.equal(state.lastPayload.vpnmgr_vpn1_cityid,200,'changed country and city use current catalogue ID');
  await click('#vpnmgr_vpn1_prov_pia');
  await save();
  assert.equal(state.lastPayload.vpnmgr_vpn1_provider,'PIA');
  assert.equal(state.lastPayload.vpnmgr_vpn1_countryid,0,'changed provider does not inherit old country ID');
  assert.equal(state.lastPayload.vpnmgr_vpn1_cityid,0,'changed provider does not inherit old city ID');

  state = fixture();
  state.providers = 'pia|PIA\n';
  await load();
  assert.equal(await execute('return document.form.vpnmgr_vpn1_provider.value'),'NordVPN');
  await click('#btnSaveConfig');
  assert.match(await execute('return fixtureAlerts[fixtureAlerts.length-1]'),/unavailable/);
  assert.equal(state.posts.some(post => post.action.startsWith('start_vpnmgrapply_')),false);

  state = fixture();
  state.configFailure = true;
  await wd('POST','/url',{url:pageUrl});
  await until('vpnmgr_configState === "failed"','config failure');
  assert.equal(await execute('return document.querySelector("#btnSaveConfig").disabled'),true);
  state.configFailure = false;
  await click('#btnConfigRetry');
  await until('vpnmgr_initComplete && !document.querySelector("#btnSaveConfig").disabled','config retry');
  assert.equal(await execute('return document.querySelectorAll("[id^=table_config_vpn]").length'),5);
  // A syntactically valid truncated file must never enable a destructive Save.
  delete state.config.vpn4_protocol;
  await execute('document.form.vpnmgr_vpn1_pwd.value="unsaved fixture";get_conf_file();');
  await until('vpnmgr_configState === "failed"','truncated config rejected');
  assert.equal(await execute('return document.querySelector("#btnSaveConfig").disabled'),true);
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.value'),'unsaved fixture');
  state.config.vpn4_protocol = 'udp';
  state.config.vpn2_protocol = 'tcp';
  await click('#btnConfigRetry');
  await until('vpnmgr_initComplete && !document.querySelector("#btnSaveConfig").disabled','complete config retry');
  assert.equal(await execute('return document.querySelectorAll("[id^=table_config_vpn]").length'),5);
  assert.equal(await execute('return document.form.vpnmgr_vpn2_protocol.value'),'TCP');
  assert.equal(state.redirects,0);
  console.log('Real '+(firefox ? 'Firefox Developer':'Chrome')+' WebUI journeys passed: runtime families/unknown, five slots, Save/reload, repeated edits, provider/schedule/location changes, native overlay/recovery controls, busy/partial/stale/late results, reservation recovery/lost acknowledgements, stopped-client status, unavailable provider, load retry and inert firmware response.');
  console.log('One isolated browser session; '+((Date.now()-started)/1000).toFixed(2)+'s wall. Popup boundary: '+(nativePopupPath || 'native-like fixture'));
  console.log('Firmware endpoints were simulated; no router contacted.');
}

run().catch(error => { console.error(error.stack);process.exitCode=1; }).finally(async () => {
  if (bidiSocket && bidiSocket.readyState !== WebSocket.CLOSED) {
    try {
      if (bidiSocket.readyState < WebSocket.CLOSING) bidiSocket.close();
      await Promise.race([
        new Promise(resolve => bidiSocket.addEventListener('close',resolve,{once:true})),
        pause(1000)
      ]);
    } catch (_) {}
  }
  if (session) { try { await wd('DELETE',''); } catch (_) {} }
  if (driver && driver.exitCode === null && driver.signalCode === null) {
    await new Promise(resolve => {
      const timeout = setTimeout(resolve,2000);
      driver.once('exit',() => { clearTimeout(timeout);resolve(); });
      driver.kill();
    });
  }
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  fs.rmSync(profile,{recursive:true,force:true});
});
