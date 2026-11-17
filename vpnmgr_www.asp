<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="icon" href="images/favicon.png">
<title>vpnmgr</title>
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<style>
p{font-weight:bolder}thead.collapsible-jquery{color:#fff;padding:0;width:100%;border:none;text-align:left;outline:none;cursor:pointer}.SettingsTable{table-layout:fixed!important;width:745px!important;text-align:left}.SettingsTable input{text-align:left;margin-left:3px!important}.SettingsTable label{margin-right:10px!important}.SettingsTable th{background-color:#1F2D35!important;background:#2F3A3E!important;border-bottom:none!important;border-top:none!important;font-size:12px!important;color:#fff!important;padding:4px!important;font-weight:bolder!important;padding:0!important}.SettingsTable td{padding:4px 4px 4px 10px !important;word-wrap:break-word!important;overflow-wrap:break-word!important;border-right:none;border-left:none}.SettingsTable span.settingname{background-color:#1F2D35!important;background:#2F3A3E!important}.SettingsTable td.settingname{border-right:solid 1px #000;background-color:#1F2D35!important;background:#2F3A3E!important;font-weight:bolder!important}.SettingsTable td.settingvalue{text-align:left!important;border-right:solid 1px #000}.SettingsTable th:first-child{border-left:none!important}.SettingsTable th:last-child{border-right:none!important}.SettingsTable .invalid{background-color:#8b0000!important}.SettingsTable .disabled{background-color:#CCC!important;color:#888!important}
</style>
<script language="JavaScript" type="text/javascript" src="/ext/vpnmgr/www/jquery.js"></script>
<script language="JavaScript" type="text/javascript" src="/state.js"></script>
<script language="JavaScript" type="text/javascript" src="/general.js"></script>
<script language="JavaScript" type="text/javascript" src="/popup.js"></script>
<script language="JavaScript" type="text/javascript" src="/help.js"></script>
<script language="JavaScript" type="text/javascript" src="/ext/vpnmgr/www/detect.js"></script>
<script language="JavaScript" type="text/javascript" src="/js/httpApi.js"></script>
<script language="JavaScript" type="text/javascript" src="/client_function.js"></script>
<script language="JavaScript" type="text/javascript" src="/validator.js"></script>
<script language="JavaScript" type="text/javascript" src="/base64.js"></script>
<script language="JavaScript" type="text/javascript" src="/ext/vpnmgr/vpnmgr_www.js"></script>
<script>
var custom_settings;
function LoadCustomSettings(){
	custom_settings = <% get_custom_settings(); %>;
	for (var prop in custom_settings){
		if (Object.prototype.hasOwnProperty.call(custom_settings, prop)){
			if(prop.indexOf("vpnmgr") != -1 && prop.indexOf("version") == -1){
				eval("delete custom_settings."+prop);
			}
		}
	}
}
</script>
</head>
<body onload="initial();">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="about:blank" width="0" height="0" frameborder="0"></iframe>
<form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">
<input type="hidden" name="current_page" value="">
<input type="hidden" name="next_page" value="">
<input type="hidden" name="modified" value="0">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_wait" value="15">
<input type="hidden" name="first_time" value="">
<input type="hidden" name="SystemCmd" value="">
<input type="hidden" name="action_script" value="start_vpnmgr">
<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>">
<input type="hidden" name="vpn1_desc" value="<% nvram_get("vpn_client1_desc"); %>">
<input type="hidden" name="vpn2_desc" value="<% nvram_get("vpn_client2_desc"); %>">
<input type="hidden" name="vpn3_desc" value="<% nvram_get("vpn_client3_desc"); %>">
<input type="hidden" name="vpn4_desc" value="<% nvram_get("vpn_client4_desc"); %>">
<input type="hidden" name="vpn5_desc" value="<% nvram_get("vpn_client5_desc"); %>">
<input type="hidden" name="vpn1_usn" value="<% nvram_clean_get("vpn_client1_username"); %>">
<input type="hidden" name="vpn2_usn" value="<% nvram_clean_get("vpn_client2_username"); %>">
<input type="hidden" name="vpn3_usn" value="<% nvram_clean_get("vpn_client3_username"); %>">
<input type="hidden" name="vpn4_usn" value="<% nvram_clean_get("vpn_client4_username"); %>">
<input type="hidden" name="vpn5_usn" value="<% nvram_clean_get("vpn_client5_username"); %>">
<input type="hidden" name="vpn1_pwd" value="<% nvram_clean_get("vpn_client1_password"); %>">
<input type="hidden" name="vpn2_pwd" value="<% nvram_clean_get("vpn_client2_password"); %>">
<input type="hidden" name="vpn3_pwd" value="<% nvram_clean_get("vpn_client3_password"); %>">
<input type="hidden" name="vpn4_pwd" value="<% nvram_clean_get("vpn_client4_password"); %>">
<input type="hidden" name="vpn5_pwd" value="<% nvram_clean_get("vpn_client5_password"); %>">
<input type="hidden" name="amng_custom" id="amng_custom" value="">
<table class="content" align="center" cellpadding="0" cellspacing="0">
<tr>
<td width="17">&nbsp;</td>
<td valign="top" width="202">
<div id="mainMenu"></div>
<div id="subMenu"></div></td>
<td valign="top">
<div id="tabMenu" class="submenuBlock"></div>
<table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
<tr>
<td align="left" valign="top">
<table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3" class="FormTitle" id="FormTitle">
<tr>
<td bgcolor="#4D595D" colspan="3" valign="top">
<div>&nbsp;</div>
<div class="formfonttitle" id="scripttitle" style="text-align:center;">vpnmgr</div>
<div style="margin:10px 0 10px 5px;" class="splitLine"></div>
<div class="formfontdesc">Management of your VPN Client connections for various VPN providers</div>
<table width="100%" border="1" align="center" cellpadding="2" cellspacing="0" bordercolor="#6b8fa3" class="FormTable" style="border:0px;" id="table_scripttools">
<thead class="collapsible-jquery" id="scripttools">
<tr><td colspan="2">Utilities (click to expand/collapse)</td></tr>
</thead>
<tr>
<th width="20%">Version information</th>
<td>
<span id="vpnmgr_version_local" style="color:#FFFFFF;"></span>
&nbsp;&nbsp;&nbsp;
<span id="vpnmgr_version_server" style="display:none;">Update version</span>
&nbsp;&nbsp;&nbsp;
<input type="button" class="button_gen" onclick="CheckUpdate();" value="Check" id="btnChkUpdate">
<img id="imgChkUpdate" style="display:none;vertical-align:middle;" src="images/InternetScan.gif"/>
<input type="button" class="button_gen" onclick="DoUpdate();" value="Update" id="btnDoUpdate" style="display:none;">
&nbsp;&nbsp;&nbsp;
</td>
</tr>
<tr>
<th width="20%">Cached data</th>
<td>
<input type="button" class="button_gen" onclick="RefreshCachedData();" value="Refresh" id="btnRefreshCachedData">
<img id="imgRefreshCachedData" style="display:none;vertical-align:middle;" src="images/InternetScan.gif"/>
&nbsp;&nbsp;&nbsp;
<span id="refreshcacheddata_text" style="display:none;">Cached data updated</span>
</td>
</tr>

<tr>
<th width="20%">Show VPN server load in client description
<span style="color:#FFCC00;">(NordVPN servers only)</span>
</th>
<td>
<input type="button" class="button_gen" onclick="GetServerLoad();" value="Load" id="btnGetServerLoad">
<img id="imgGetServerLoad" style="display:none;vertical-align:middle;" src="images/InternetScan.gif"/>
<span id="getserverload_text" style="display:none;">Server loads retrieved, see client descriptions</span>
</td>
</tr>


</table>
<div style="line-height:10px;">&nbsp;</div>
<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable" style="border:0px;" id="table_buttons">
<tr class="apply_gen" valign="top" height="35px">
<td style="background-color:rgb(77, 89, 93);border:0px;">
<input name="button" type="button" class="button_gen" onclick="SaveConfig();" value="Save"/>
</td>
</tr>
</table>
</td>
</tr>
</table>
</td>
</tr>
</table>
</td>
</tr>
</table>
</form>
<form method="post" name="formScriptActions" action="/start_apply.htm" target="hidden_frame">
<input type="hidden" name="productid" value="<% nvram_get("productid"); %>">
<input type="hidden" name="current_page" value="">
<input type="hidden" name="next_page" value="">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_script" value="">
<input type="hidden" name="action_wait" value="">
</form>
<div id="footer"></div>
</body>
</html>
