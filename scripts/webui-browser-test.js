'use strict';

// One isolated Chrome session against loopback fixtures; never contacts a router.
// Requires an existing compatible Chrome/ChromeDriver, with no package installs.
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
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'vpnmgr-browser-'));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const started = Date.now();
let state, session, driver, driverUrl, pageUrl;
const firmware = `window.fixtureErrors=[];window.fixtureAlerts=[];
window.addEventListener('error',function(e){fixtureErrors.push(e.message);});
window.alert=function(s){fixtureAlerts.push(s);};
window.show_menu=function(){};window.showLoading=function(){};
window.showhide=function(id,show){var e=document.getElementById(id);if(e)e.style.display=show?'':'none';};
window.cookie={get:function(){return null;},set:function(){}};
window.nd=function(){};window.overlib=function(){};
window.switchType=function(e,checked){e.type=checked?'text':'password';};`;

function fixture(version = '2.6.12') {
  const config = {};
  for (let i = 1; i <= 5; i++) {
    Object.assign(config, Object.fromEntries(Object.entries({managed:i <= 3 ? 'true':'false',provider:'NordVPN',customsettings:'true',protocol:i === 2 ? 'TCP':'UDP',type:'Standard',countryname:'Australia',countryid:'13',cityname:'Sydney',cityid:'100',schenabled:'false',schhours:'*',schmins:'0',schdays:'*'}).map(([k,v]) => ['vpn'+i+'_'+k,v])));
  }
  return {version, family:version === '2.5.9' ? 'legacy':'modern',config,providers:'nordvpn|NordVPN\npia|PIA\n',records:new Map(),posts:[],redirects:0,delayDetection:false,busy:false,failSlot:0,hold:false,wrongStatus:false,configFailure:false,custom:{vpnmgr_version_local:'fixture',vpnmgr_version_server:'fixture',vpnmgr_version_source:'fixture@1234567',unrelated_setting:'preserve=\\value'},creds:{}};
}

function clients() {
  return Array.from({length:5}, (_,index) => ({slot:index+1,status:state.config['vpn'+(index+1)+'_managed'] !== 'true' ? 'unmanaged':state.failSlot === index+1 ? 'failed':'applied',connection:'not_requested'}));
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
    if (pathname === '/vpnmgr.asp') return respond(res,200,render(),'text/html');
    if (pathname === '/ext/vpnmgr/www/jquery.js') return respond(res,200,jquery,'application/javascript');
    if (pathname === '/ext/vpnmgr/vpnmgr_www.js') return respond(res,200,script,'application/javascript');
    if (pathname === '/state.js') return respond(res,200,firmware,'application/javascript');
    if (pathname === '/ext/vpnmgr/providers.htm') return respond(res,200,state.providers);
    if (pathname === '/ext/vpnmgr/nordvpn_countrydata.htm') return respond(res,200,JSON.stringify([{id:13,name:'Australia',cities:[{id:100,name:'Sydney'}]}]),'application/json');
    if (pathname === '/ext/vpnmgr/pia_countrydata.htm') return respond(res,200,'AU_Sydney\nUK_London\n');
    if (pathname === '/ext/vpnmgr/config.htm') return respond(res,state.configFailure ? 503:200,Object.entries(state.config).map(([k,v]) => k+'='+v).join('\n'));
    if (pathname === '/unexpected-redirect') { state.redirects++; return respond(res,500,'Firmware response executed'); }
    if (pathname === '/start_apply.htm') {
      let body = '';
      for await (const part of req) body += part;
      const fields = new URLSearchParams(body);
      const action = fields.get('action_script');
      state.posts.push({action,fields});
      const match = /^start_vpnmgr(runtime|prepare|apply)_(\d+)$/.exec(action || '');
      assert.ok(match, 'unexpected control action '+action);
      const [,kind,id] = match;
      if (kind === 'runtime') {
        state.records.set('detection_'+id+'.json',{request:id,state:'done',version:state.version,number:state.version ? '2006012':'',family:state.version ? state.family:'legacy',status:state.version ? 'detected':'unknown',misses:state.delayDetection ? 1:0});
        state.delayDetection = false;
      } else if (kind === 'prepare') {
        assert.equal(fields.has('amng_custom'),false,'reservation must precede the settings payload');
        state.records.set('apply_'+id+'.json',{request:id,state:state.busy ? 'busy':'ready'});
      } else {
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
        state.records.set('apply_'+id+'.json',{request:id,state:'done',merged:true,clients:clients(),message:'complete'});
      }
      // The real firmware returns executable callbacks/reload code. AJAX must leave this inert.
      return respond(res,200,'<script>parent.location.replace("/unexpected-redirect")</script>','text/html');
    }
    if (pathname.startsWith('/ext/vpnmgr/runtime/')) {
      const name = pathname.split('/').pop();
      const result = state.records.get(name);
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
async function until(expression, label, limit = 15000) {
  const deadline = Date.now()+limit;
  while (Date.now() < deadline) {
    if (state.serverError) throw new Error(state.serverError);
    const errors = await execute('return window.fixtureErrors || []');
    assert.deepEqual(errors,[],label+' JavaScript errors');
    if (await execute('return !!('+expression+')')) return;
    await pause(100);
  }
  throw new Error('Timed out: '+label+'; '+await execute('return JSON.stringify({config:window.vpnmgr_configState,runtime:window.vpnmgr_runtimeState,summary:document.querySelector("#vpnmgr_apply_summary").textContent,alerts:window.fixtureAlerts})'));
}
async function load() {
  await wd('POST','/url',{url:pageUrl});
  await until('window.vpnmgr_initComplete && !document.querySelector("#btnSaveConfig").disabled','page ready');
  assert.equal(await execute('return document.querySelectorAll("[id^=table_config_vpn]").length'),5);
}
async function click(selector) {
  await execute('document.querySelector('+JSON.stringify(selector)+').click();');
}
async function save() {
  await click('#btnSaveConfig');
  await until('!window.vpnmgr_pendingApply && !document.querySelector("#btnSaveConfig").disabled','apply terminal');
  assert.equal(state.redirects,0);
}

async function run() {
  state = fixture();
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  pageUrl = 'http://127.0.0.1:'+server.address().port+'/vpnmgr.asp';
  // Have ChromeDriver choose its own unused port; parse only its startup announcement.
  driver = spawn(process.env.CHROMEDRIVER || 'chromedriver',['--port=0'],{stdio:['ignore','pipe','pipe']});
  let output = '';
  driver.stdout.on('data',data => { output += data; });
  driver.stderr.on('data',data => { output += data; });
  driver.on('error',error => { output += error.message; });
  for (let count=0; count<100 && !/started successfully on port (\d+)/.test(output); count++) await pause(100);
  const port = /started successfully on port (\d+)/.exec(output);
  assert.ok(port,'ChromeDriver did not start: '+output);
  driverUrl = 'http://127.0.0.1:'+port[1];
  const options = {args:['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--user-data-dir='+profile]};
  if (process.env.CHROME_BINARY) options.binary = process.env.CHROME_BINARY;
  const created = await wd('POST','/session',{capabilities:{alwaysMatch:{browserName:'chrome','goog:chromeOptions':options}}});
  session = created.sessionId;

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
    await load();
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
  await load();
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
  assert.match(await execute('return document.querySelector("#vpnmgr_apply_summary").textContent'),/not submitted.*busy/);
  state.busy = false;
  state.failSlot = 2;
  await save();
  assert.match(await execute('return document.querySelector("#vpnmgr_apply_summary").textContent'),/failed for VPN Client 2/);
  assert.match(await execute('return document.querySelector("#vpnmgr_client_status_2").textContent'),/failed/);

  state.hold = true;
  state.failSlot = 0;
  await click('#btnSaveConfig');
  await until('vpnmgr_pendingApply && vpnmgr_pendingApply.phase === "apply"','pending apply');
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.disabled'),true);
  await execute('vpnmgr_pendingApply.startedAt=0;PollApplyStatus(vpnmgr_pendingApply);');
  assert.equal(await execute('return vpnmgr_pendingApply.polling'),false);
  const posted = state.posts.length;
  state.hold = false;
  state.wrongStatus = true;
  await click('#btnContinueApply');
  await until('document.querySelector("#vpnmgr_apply_summary").textContent.indexOf("stale") !== -1','stale result rejected');
  assert.equal(state.posts.length,posted,'continue checking must not repost a payload');
  state.wrongStatus = false;
  await until('!vpnmgr_pendingApply && !document.querySelector("#btnSaveConfig").disabled','late result');
  assert.equal(await execute('return document.form.vpnmgr_vpn1_pwd.disabled'),false);

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
  console.log('Real Chrome WebUI journeys passed: runtime families/unknown, five slots, Save/reload, repeated edits, provider/schedule changes, busy/partial/stale/late results, unavailable provider, load retry and inert firmware response.');
  console.log('One isolated browser session; '+((Date.now()-started)/1000).toFixed(2)+'s wall. Firmware endpoints were simulated; no router contacted.');
}

run().catch(error => { console.error(error.stack);process.exitCode=1; }).finally(async () => {
  if (session) { try { await wd('DELETE',''); } catch (_) {} }
  if (driver) driver.kill();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  fs.rmSync(profile,{recursive:true,force:true});
});
