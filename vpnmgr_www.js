// Keep global $ available to the firmware scripts loaded by state.js.
var $j = jQuery;
var daysofweek = ['Mon','Tues','Wed','Thurs','Fri','Sat','Sun'];

var vpnmgr_providers = [];
var providerCountries = {};
var providerTypes = {
	'nordvpn':   ['Standard','Double','P2P'],
	'pia':       ['Standard','Strong'],
	'wevpn':     ['Standard'],
	'surfshark': ['Standard']
};

var refreshcacheddatainterval;
var getserverloadinterval;
var vpnmgr_initComplete = false;

function SettingHint(hintid){
	var tag_name = document.getElementsByTagName('a');
	for (var i=0;i<tag_name.length;i++){
		tag_name[i].onmouseout=nd;
	}
	hinttext='My text goes here';
	if(hintid == 1) hinttext='Manage VPN client using vpnmgr';
	if(hintid == 2) hinttext='Provider to use for VPN';
	if(hintid == 3) hinttext='Username for VPN';
	if(hintid == 4) hinttext='Password for VPN';
	if(hintid == 5) hinttext='Protocol to use for VPN server';
	if(hintid == 6) hinttext='Type of VPN server to use';
	if(hintid == 7) hinttext='Country of VPN server to use';
	if(hintid == 8) hinttext='City of VPN server to use';
	if(hintid == 9) hinttext='Automatically update VPN to new VPN server';
	if(hintid == 10) hinttext='Day(s) of week to check for new server/reload server config';
	if(hintid == 11) hinttext='Set schedule by every X hours/days or custom input';
	if(hintid == 12) hinttext='Set frequency of update';
	if(hintid == 13) hinttext='Hour(s) of day to check for new server/reload server config (* for all,0-23. Comma separate for multiple hours.)';
	if(hintid == 14) hinttext='Minute(s) of hour to check for new server/reload server config (* for all,0-59. Comma separate for multiple minutes.)';
	if(hintid == 14) hinttext='Use vpnmgr\'s recommended custom settings for VPN client. Disable this if you want to use your own custom settings.';
	return overlib(hinttext,HAUTO,VAUTO);
}

function OptionsEnableDisable(forminput,isformload){
	var inputname = forminput.name;
	var inputvalue = forminput.value;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));
	var prefix2 = prefix.replace('vpnmgr_','');
	
	var fieldnames = ['provider','usn','pwd','customsettings','protocol','type','countryname','cityname','schenabled','schhours','schmins'];
	var fieldnames2 = ['schedulemode','everyxselect','everyxvalue'];
	
	if(inputvalue == 'false'){
		for(var i = 0; i < fieldnames.length; i++){
			$j('[name='+prefix+'_'+fieldnames[i]+']').prop('disabled',true);
			$j('[name='+prefix+'_'+fieldnames[i]+']').addClass('disabled');
		}
		for (var i = 0; i < daysofweek.length; i++){
			$j('#'+prefix+'_'+daysofweek[i].toLowerCase()).prop('disabled',true);
		}
		for (var i = 0; i < fieldnames2.length; i++){
			$j('[name='+prefix2+'_'+fieldnames2[i]+']').addClass('disabled');
			$j('[name='+prefix2+'_'+fieldnames2[i]+']').prop('disabled',true);
		}
	}
	else if(inputvalue == 'true'){
		for(var i = 0; i < fieldnames.length; i++){
			$j('[name='+prefix+'_'+fieldnames[i]+']').prop('disabled',false);
			$j('[name='+prefix+'_'+fieldnames[i]+']').removeClass('disabled');
		}
		for (var i = 0; i < daysofweek.length; i++){
			$j('#'+prefix+'_'+daysofweek[i].toLowerCase()).prop('disabled',false);
		}
		for (var i = 0; i < fieldnames2.length; i++){
			$j('[name='+prefix2+'_'+fieldnames2[i]+']').removeClass('disabled');
			$j('[name='+prefix2+'_'+fieldnames2[i]+']').prop('disabled',false);
		}
		if(!isformload){
			ScheduleOptionsEnableDisable($j('#'+prefix+'_sch_'+$j('[name='+prefix+'_schenabled]:checked').val().toLowerCase())[0]);
			VPNTypesToggle($j('#'+prefix+'_prov_'+$j('[name='+prefix+'_provider]:checked').val().toLowerCase())[0]);
		}
	}
}

function VPNTypesToggle(forminput){
	if(!forminput) return;
	var inputname = forminput.name;
	var inputvalue = forminput.value;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));
	var pid = inputvalue.toLowerCase();
	var types = providerTypes[pid] || ['Standard'];
	var allTypes = ['Standard','Double','P2P','Strong'];
	for(var i = 0; i < allTypes.length; i++){
		var t = allTypes[i].toLowerCase();
		if(types.indexOf(allTypes[i]) != -1){
			$j('label[for='+prefix+'_'+t+'],#'+prefix+'_'+t).show();
		}
		else{
			$j('label[for='+prefix+'_'+t+'],#'+prefix+'_'+t).hide();
		}
	}
	
	$j('#'+prefix+'_standard').prop('checked',true);
	
	PopulateCountryDropdown(prefix.replace('vpnmgr_vpn',''));
	
	if($j('select[name='+prefix+'_countryname]').val() == ''){
		$j('select[name='+prefix+'_cityname]').prop('disabled',true);
	}
	else if($j('select[name='+prefix+'_countryname]').val() != ''){
		$j('select[name='+prefix+'_cityname]').prop('disabled',false);
	}
	
	PopulateCityDropdown(prefix.replace('vpnmgr_vpn',''));
	var dropdown = $j('select[name='+prefix+'_cityname]');
	if(dropdown[0].length == 0 || dropdown.find('option:first-child').val().length == 0){
		dropdown.prop('disabled',true);
	}
	else if(dropdown[0].length > 0){
		dropdown.prop('disabled',false);
	}
}

function ScheduleOptionsEnableDisable(forminput){
	var inputname = forminput.name;
	var inputvalue = forminput.value;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));
	var prefix2 = prefix.replace('vpnmgr_','');
	
	var fieldnames = ['schhours','schmins'];
	var fieldnames2 = ['schedulemode','everyxselect','everyxvalue'];
	
	if(eval('document.form.'+prefix+'_managed').value == 'true'){
		if(inputvalue == 'false'){
			for (var i = 0; i < fieldnames.length; i++){
				$j('input[name='+prefix+'_'+fieldnames[i]+']').addClass('disabled');
				$j('input[name='+prefix+'_'+fieldnames[i]+']').prop('disabled',true);
			}
			for (var i = 0; i < daysofweek.length; i++){
				$j('#'+prefix+'_'+daysofweek[i].toLowerCase()).prop('disabled',true);
			}
			for (var i = 0; i < fieldnames2.length; i++){
				$j('[name='+prefix2+'_'+fieldnames2[i]+']').addClass('disabled');
				$j('[name='+prefix2+'_'+fieldnames2[i]+']').prop('disabled',true);
			}
		}
		else if(inputvalue == 'true'){
			for (var i = 0; i < fieldnames.length; i++){
				$j('input[name='+prefix+'_'+fieldnames[i]+']').removeClass('disabled');
				$j('input[name='+prefix+'_'+fieldnames[i]+']').prop('disabled',false);
			}
			for (var i = 0; i < daysofweek.length; i++){
				$j('#'+prefix+'_'+daysofweek[i].toLowerCase()).prop('disabled',false);
			}
			for (var i = 0; i < fieldnames2.length; i++){
				$j('[name='+prefix2+'_'+fieldnames2[i]+']').removeClass('disabled');
				$j('[name='+prefix2+'_'+fieldnames2[i]+']').prop('disabled',false);
			}
		}
	}
}

function PopulateCountryDropdown(vpnclient){
	for (var vpnno = 1; vpnno < 6; vpnno++){
		if(vpnclient != 'all'){
			if(vpnno != vpnclient){
				continue;
			}
		}
		var dropdown = $j('#vpnmgr_vpn'+vpnno+'_countryname');
		dropdown.empty();
		var pid = eval('document.form.vpnmgr_vpn'+vpnno+'_provider').value.toLowerCase();
		var countryarray = providerCountries[pid] || [];
		if(pid == 'nordvpn'){
			dropdown.append('<option selected="true"></option>');
			dropdown.prop('selectedIndex',0);
		}
		$j.each(countryarray,function (key,entry){
			dropdown.append($j('<option></option>').attr('value',entry.name).text(entry.name));
		});
	}
}

function PopulateCityDropdown(vpnclient){
	for (var vpnno = 1; vpnno < 6; vpnno++){
		if(vpnclient != 'all'){
			if(vpnno != vpnclient){
				continue;
			}
		}
		var dropdown = $j('#vpnmgr_vpn'+vpnno+'_cityname');
		dropdown.empty();
		var pid = eval('document.form.vpnmgr_vpn'+vpnno+'_provider').value.toLowerCase();
		var cityarray = providerCountries[pid] || [];
		if(pid == 'nordvpn'){
			dropdown.append('<option selected="true"></option>');
			dropdown.prop('selectedIndex',0);
		}
		$j.each(cityarray,function (key,entry){
			if(entry.name != eval('document.form.vpnmgr_vpn'+vpnno+'_countryname').value){
				return true;
			}
			else{
				$j.each(entry.cities,function (key2,entry2){
					dropdown.append($j('<option></option>').attr('value',entry2.name).text(entry2.name));
				});
				return false;
			}
		});
	}
}

function ScheduleModeToggle(forminput){
	var inputname = forminput.name;
	var inputvalue = forminput.value;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));
	
	if(inputvalue == 'EveryX'){
		showhide(prefix+'_schedulefrequency',true);
		showhide(prefix+'_customhours',false);
		showhide(prefix+'_custommins',false);
		if($j('#'+prefix+'_everyxselect').val() == 'hours'){
			showhide(prefix+'_spanxhours',true);
			showhide(prefix+'_spanxminutes',false);
		}
		else if($j('#'+prefix+'_everyxselect').val() == 'minutes'){
			showhide(prefix+'_spanxhours',false);
			showhide(prefix+'_spanxminutes',true);
		}
	}
	else if(inputvalue == 'Custom'){
		showhide(prefix+'_schedulefrequency',false);
		showhide(prefix+'_customhours',true);
		showhide(prefix+'_custommins',true);
	}
}

function EveryXToggle(forminput){
	var inputname = forminput.name;
	var inputvalue = forminput.value;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));
	
	if(inputvalue == 'hours'){
		showhide(prefix+'_spanxhours',true);
		showhide(prefix+'_spanxminutes',false);
	}
	else if(inputvalue == 'minutes'){
		showhide(prefix+'_spanxhours',false);
		showhide(prefix+'_spanxminutes',true);
	}
	
	Validate_ScheduleValue($j('[name='+prefix+'_everyxvalue]')[0]);
}

function Validate_Schedule(forminput,hoursmins){
	var inputname = forminput.name;
	var inputvalues = forminput.value.split(',');
	var upperlimit = 0;
	
	if(hoursmins == 'hours'){
		upperlimit = 23;
	}
	else if (hoursmins == 'mins'){
		upperlimit = 59;
	}
	
	var validationfailed = 'false';
	for(var i=0; i < inputvalues.length; i++){
		if(inputvalues[i] == '*' && i == 0){
			validationfailed = 'false';
		}
		else if(inputvalues[i] == '*' && i != 0){
			validationfailed = 'true';
		}
		else if(inputvalues[0] == '*' && i > 0){
			validationfailed = 'true';
		}
		else if(inputvalues[i] == ''){
			validationfailed = 'true';
		}
		else if(! isNaN(inputvalues[i]*1)){
			if((inputvalues[i]*1) > upperlimit || (inputvalues[i]*1) < 0){
				validationfailed = 'true';
			}
		}
		else{
			validationfailed = 'true';
		}
	}
	
	if(validationfailed == 'true'){
		$j(forminput).addClass('invalid');
		return false;
	}
	else{
		$j(forminput).removeClass('invalid');
		return true;
	}
}

function Validate_ScheduleValue(forminput){
	var inputname = forminput.name;
	var inputvalue = forminput.value*1;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));
	
	var upperlimit = 0;
	var lowerlimit = 1;
	
	var unittype = $j('#'+prefix+'_everyxselect').val();
	
	if(unittype == 'hours'){
		upperlimit = 24;
	}
	else if(unittype == 'minutes'){
		upperlimit = 30;
	}
	
	if(inputvalue > upperlimit || inputvalue < lowerlimit || forminput.value.length < 1){
		$j(forminput).addClass('invalid');
		return false;
	}
	else{
		$j(forminput).removeClass('invalid');
		return true;
	}
}

function Validate_All(){
	var validationfailed = false;
	for(var i=1; i < 6; i++){
		if(eval('document.form.vpn'+i+'_schedulemode').value == 'EveryX'){
			if(! Validate_ScheduleValue(eval('document.form.vpn'+i+'_everyxvalue'))) validationfailed=true;
		}
		else if(eval('document.form.vpn'+i+'_schedulemode').value == 'Custom'){
			if(! Validate_Schedule(eval('document.form.vpnmgr_vpn'+i+'_schhours'),'hours')) validationfailed=true;
			if(! Validate_Schedule(eval('document.form.vpnmgr_vpn'+i+'_schmins'),'mins')) validationfailed=true;
		}
	}
	if(validationfailed){
		alert('Validation for some fields failed. Please correct invalid values and try again.');
		return false;
	}
	else{
		return true;
	}
}

function get_conf_file(){
	$j.ajax({
		url: '/ext/vpnmgr/config.htm',
		dataType: 'text',
		error: function(xhr){
			setTimeout(get_conf_file,1000);
		},
		success: function(data){
			var settings = data.split('\n');
			settings.reverse();
			settings = settings.filter(Boolean);
			var settingcount = settings.length;
			window['vpnmgr_settings'] = [];
			for (var i = 0; i < settingcount; i++){
				if (settings[i].indexOf('#') != -1){
					continue
				}
				var setting = settings[i].split('=');
				window['vpnmgr_settings'].unshift(setting);
				}
				
				for (var vpnno = 5; vpnno >= 1; vpnno--){
					$j('#table_scripttools').after(BuildConfigTable('vpn'+vpnno,'VPN Client '+vpnno));
				}
				
				for (var i = 0; i < window['vpnmgr_settings'].length; i++){
					var settingname = window['vpnmgr_settings'][i][0];
					var settingvalue = window['vpnmgr_settings'][i][1];
					if(settingname.indexOf('cityid') != -1 || settingname.indexOf('countryid') != -1 || settingname.indexOf('countryname') != -1 || settingname.indexOf('cityname') != -1) continue;
					if(settingname.indexOf('schdays') == -1){
						var vpnmgr_field = document.form['vpnmgr_'+settingname];
						if (vpnmgr_field) {
							vpnmgr_field.value = settingvalue;
						}
						if(settingname.indexOf('managed') != -1) OptionsEnableDisable($j('#vpnmgr_'+settingname.replace('_managed','')+'_man_'+settingvalue)[0],true);
						if(settingname.indexOf('schenabled') != -1) ScheduleOptionsEnableDisable($j('#vpnmgr_'+settingname.replace('_schenabled','')+'_sch_'+settingvalue)[0]);
						if(settingname.indexOf('provider') != -1) VPNTypesToggle($j('#vpnmgr_'+settingname.replace('_provider','')+'_prov_'+settingvalue.toLowerCase())[0]);
					}
					else{
						if(settingvalue == '*'){
							for (var i2 = 0; i2 < daysofweek.length; i2++){
								$j('#vpnmgr_'+settingname.substring(0,vpnmgr_settings[i][0].indexOf('_'))+'_'+daysofweek[i2].toLowerCase()).prop('checked',true);
							}
						}
						else{
							var schdayarray = settingvalue.split(',');
							for (var i2 = 0; i2 < schdayarray.length; i2++){
								$j('#vpnmgr_'+settingname.substring(0,vpnmgr_settings[i][0].indexOf('_'))+'_'+schdayarray[i2].toLowerCase()).prop('checked',true);
							}
						}
					}
				}
				
				PopulateCountryDropdown('all');
				for (var i = 1; i < 6; i++){
					eval('document.form.vpnmgr_vpn'+i+'_countryname').value = window['vpnmgr_settings'].filter(function(item){
						return item[0] == 'vpn'+i+'_countryname';
					})[0][1];
					
					if(eval('document.form.vpnmgr_vpn'+i+'_countryname').value == ''){
						$j('#vpnmgr_vpn'+i+'_cityname').prop('disabled',true);
					}
					else if(eval('document.form.vpnmgr_vpn'+i+'_countryname').value != ''){
						$j('#vpnmgr_vpn'+i+'_cityname').prop('disabled',false);
					}
					
					if(eval('document.form.vpnmgr_vpn'+i+'_countryname').value == '' && eval('document.form.vpnmgr_vpn'+i+'_countryname').length == 1){
						$j('#vpnmgr_vpn'+i+'_cityname').prop('disabled',true);
					}
				}
				
				PopulateCityDropdown('all');
				
				for (var i = 1; i < 6; i++){
					eval('document.form.vpnmgr_vpn'+i+'_cityname').value = window['vpnmgr_settings'].filter(function(item){
						return item[0] == 'vpn'+i+'_cityname';
					})[0][1];
					
					if((eval('document.form.vpnmgr_vpn'+i+'_cityname').length == 0) || (eval('document.form.vpnmgr_vpn'+i+'_cityname').length == 1 && eval('document.form.vpnmgr_vpn'+i+'_cityname').value == '')){
						$j('#vpnmgr_vpn'+i+'_cityname').prop('disabled',true);
					}
					else if(eval('document.form.vpnmgr_vpn'+i+'_cityname').length > 0){
						$j('#vpnmgr_vpn'+i+'_cityname').prop('disabled',false);
					}
				}
				
				for (var i = 1; i < 6; i++){
					eval('document.form.vpnmgr_vpn'+i+'_usn').value = eval('document.form.vpn'+i+'_usn').value;
					eval('document.form.vpnmgr_vpn'+i+'_pwd').value = eval('document.form.vpn'+i+'_pwd').value;
					
					if($j('[name=vpnmgr_vpn'+i+'_schhours]').val().indexOf('/') != -1){
						eval('document.form.vpn'+i+'_schedulemode').value = 'EveryX';
						eval('document.form.vpn'+i+'_everyxselect').value = 'hours';
						eval('document.form.vpn'+i+'_everyxvalue').value = $j('[name=vpnmgr_vpn'+i+'_schhours]').val().split('/')[1];
					}
					else if($j('[name=vpnmgr_vpn'+i+'_schmins]').val().indexOf('/') != -1){
						eval('document.form.vpn'+i+'_schedulemode').value = 'EveryX';
						eval('document.form.vpn'+i+'_everyxselect').value = 'minutes';
						eval('document.form.vpn'+i+'_everyxvalue').value = $j('[name=vpnmgr_vpn'+i+'_schmins]').val().split('/')[1];
					}
					else{
						eval('document.form.vpn'+i+'_schedulemode').value = 'Custom';
					}
					ScheduleModeToggle($j('#vpn'+i+'_schmode_'+$j('[name=vpn'+i+'_schedulemode]:checked').val().toLowerCase())[0]);
				}
				
				showhide('imgRefreshCachedData',false);
				showhide('refreshcacheddata_text',false);
				showhide('btnRefreshCachedData',true);

				AddEventHandlers();
				vpnmgr_initComplete = true;
			}
	});
}

function GetCookie(cookiename,returntype){
	if(cookie.get('vpnmgr_'+cookiename) != null){
		return cookie.get('vpnmgr_'+cookiename);
	}
	else{
		if(returntype == 'string'){
			return '';
		}
		else if(returntype == 'number'){
			return 0;
		}
	}
}

function SetCookie(cookiename,cookievalue){
	cookie.set('vpnmgr_'+cookiename,cookievalue,10*365);
}

function SetCurrentPage(){
	document.form.next_page.value = window.location.pathname.substring(1);
	document.form.current_page.value = window.location.pathname.substring(1);
}

function reload(){
	location.reload(true);
}

function pass_checked(obj,showobj){
	switchType(obj,showobj.checked,true);
}

function SaveConfig(){
	if (!vpnmgr_initComplete) {
		alert('Settings have not finished loading yet. Please reload the page and try again before saving.');
		return false;
	}
	if(Validate_All()){
		for(var i=1; i < 6; i++){
			if(eval('document.form.vpn'+i+'_schedulemode').value == 'EveryX'){
				if(eval('document.form.vpn'+i+'_everyxselect').value == 'hours'){
					var everyxvalue = eval('document.form.vpn'+i+'_everyxvalue').value*1;
					eval('document.form.vpnmgr_vpn'+i+'_schmins').value = 0;
					if(everyxvalue == 24){
						eval('document.form.vpnmgr_vpn'+i+'_schhours').value = 0;
					}
					else{
						eval('document.form.vpnmgr_vpn'+i+'_schhours').value = '*/'+everyxvalue;
					}
				}
				else if(eval('document.form.vpn'+i+'_everyxselect').value == 'minutes'){
					eval('document.form.vpnmgr_vpn'+i+'_schhours').value = 0;
					var everyxvalue = eval('document.form.vpn'+i+'_everyxvalue').value*1;
					eval('document.form.vpnmgr_vpn'+i+'_schmins').value = '*/'+everyxvalue;
				}
			}
		}
		
		$j('[name*=vpnmgr_]').prop('disabled',false);
		document.getElementById('amng_custom').value = JSON.stringify($j('form').serializeObject());
		var action_script_tmp = 'start_vpnmgr';
		document.form.action_script.value = action_script_tmp;
		var restart_time = 15;
		document.form.action_wait.value = restart_time;
		showLoading();
		document.form.submit();
	}
	else{
		return false;
	}
}

function initial(){
	SetCurrentPage();
	LoadCustomSettings();
	show_menu();
	GetProviderList();
	ScriptUpdateLayout();
}

function BuildConfigTable(prefix,title){
	var charthtml = '<div style="line-height:10px;">&nbsp;</div>';
	charthtml+='<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable" id="table_config_'+prefix+'">';
	charthtml+='<thead class="collapsible-jquery" id="'+prefix+'">';
	charthtml+='<tr>';
	charthtml+='<td colspan="2">'+title+' Configuration (click to expand/collapse)</td>';
	charthtml+='</tr>';
	charthtml+='</thead>';
	charthtml+='<tr>';
	charthtml+='<td colspan="2" align="center" style="padding: 0px;">';
	
	charthtml+='<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable SettingsTable">';
	charthtml+='<col style="width:35%;">';
	charthtml+='<col style="width:65%;">';
	
	/* DESCRIPTION */
	charthtml+='<tr>';
	charthtml+='<td class="settingname">Description</a></td><td class="settingvalue"><span id="vpnmgr_'+prefix+'_desc" style="color:#ffffff;">'+$j('input[name='+prefix+'_desc]').val()+'</span></td>';
	charthtml+='</tr>';
	
	/* MANAGEMENT ENABLED */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(1);">Managed by vpnmgr?</a></td><td class="settingvalue"><input type="radio" onchange="OptionsEnableDisable(this,false)" name="vpnmgr_'+prefix+'_managed" id="vpnmgr_'+prefix+'_man_true" class="input" value="true"><label for="vpnmgr_'+prefix+'_man_true">Yes</label><input type="radio" onchange="OptionsEnableDisable(this,false)" name="vpnmgr_'+prefix+'_managed" id="vpnmgr_'+prefix+'_man_false" class="input" value="false" checked><label for="vpnmgr_'+prefix+'_man_false">No</label></td>';
	charthtml+='</tr>';
	
	/* PROVIDER */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(2);">VPN Provider</a></td><td class="settingvalue">';
	for(var pi = 0; pi < vpnmgr_providers.length; pi++){
		var pid = vpnmgr_providers[pi].id;
		var pname = vpnmgr_providers[pi].name;
		charthtml+='<input type="radio" onchange="VPNTypesToggle(this)" name="vpnmgr_'+prefix+'_provider" id="vpnmgr_'+prefix+'_prov_'+pid+'" class="input" value="'+pname+'"'+(pi === 0 ? ' checked' : '')+'><label for="vpnmgr_'+prefix+'_prov_'+pid+'">'+pname+'</label>';
	}
	charthtml+='</td>';
	charthtml+='</tr>';
	
	/* USERNAME ENABLED */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(3);">Username</a></td><td class="settingvalue"><input autocomplete="off" autocapitalize="off" type="text" class="input_30_table" onchange="" name="vpnmgr_'+prefix+'_usn" id="vpnmgr_'+prefix+'_usn"></td>';
	charthtml+='</tr>';
	
	/* PASSWORD */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(4);">Password</a></td><td class="settingvalue"><input autocomplete="off" autocapitalize="off" type="password" class="input_30_table" onchange="" name="vpnmgr_'+prefix+'_pwd" id="vpnmgr_'+prefix+'_pwd">&nbsp;&nbsp;&nbsp;<input type="checkbox" name="show_pass_'+prefix+'" onclick="pass_checked(document.form.vpnmgr_'+prefix+'_pwd,document.form.show_pass_'+prefix+')" style="vertical-align:middle;"><label for="vpnmgr_'+prefix+'_pwd" style="vertical-align:middle;margin-right:10px;margin-bottom:5px;">Show password?</label></td>';
	charthtml+='</tr>';
	
	/* CUSTOM SETTINGS */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(15);">Use vpnmgr custom settings?</a></td><td class="settingvalue"><input type="radio" name="vpnmgr_'+prefix+'_customsettings" id="vpnmgr_'+prefix+'_custsettings_true" class="input" value="true"><label for="vpnmgr_'+prefix+'_custsettings_true">Yes</label><input type="radio" name="vpnmgr_'+prefix+'_customsettings" id="vpnmgr_'+prefix+'_custsettings_false" class="input" value="false" checked><label for="vpnmgr_'+prefix+'_custsettings_false">No</label></td>';
	charthtml+='</tr>';
	
	/* TYPE */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(5);">Type</a></td><td class="settingvalue"><input type="radio" name="vpnmgr_'+prefix+'_type" id="vpnmgr_'+prefix+'_standard" class="input" value="Standard" checked><label for="vpnmgr_'+prefix+'_standard">Standard</label><input type="radio" name="vpnmgr_'+prefix+'_type" id="vpnmgr_'+prefix+'_double" class="input" value="Double"><label for="vpnmgr_'+prefix+'_double">Double</label><input type="radio" name="vpnmgr_'+prefix+'_type" id="vpnmgr_'+prefix+'_p2p" class="input" value="P2P"><label for="vpnmgr_'+prefix+'_p2p">P2P</label><input type="radio" name="vpnmgr_'+prefix+'_type" id="vpnmgr_'+prefix+'_strong" class="input" value="Strong"><label for="vpnmgr_'+prefix+'_strong">Strong</label></td>';
	charthtml+='</tr>';
	
	/* PROTOCOL */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(6);">Protocol</a></td><td class="settingvalue"><input type="radio" name="vpnmgr_'+prefix+'_protocol" id="vpnmgr_'+prefix+'_tcp" class="input" value="TCP"><label for="vpnmgr_'+prefix+'_tcp">TCP</label><input type="radio" name="vpnmgr_'+prefix+'_protocol" id="vpnmgr_'+prefix+'_udp" class="input" value="UDP" checked><label for="vpnmgr_'+prefix+'_udp">UDP</label></td>';
	charthtml+='</tr>';
	
	/* COUNTRY */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(7);">Country</a></td><td class="settingvalue"><select name="vpnmgr_'+prefix+'_countryname" id="vpnmgr_'+prefix+'_countryname" onChange="setCitiesforCountry(this)" class="input_option"></select></td>';
	charthtml+='</tr>';
	
	/* CITY */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(8);">City</a></td><td class="settingvalue"><select name="vpnmgr_'+prefix+'_cityname" id="vpnmgr_'+prefix+'_cityname" class="input_option"></select></td>';
	charthtml+='</tr>';
	
	/* SCHEDULE ENABLED */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(9);">Scheduled update/reload?</a></td><td class="settingvalue"><input type="radio" onchange="ScheduleOptionsEnableDisable(this)" name="vpnmgr_'+prefix+'_schenabled" id="vpnmgr_'+prefix+'_sch_true" class="input" value="true"><label for="vpnmgr_'+prefix+'_sch_true">Yes</label><input type="radio"  onchange="ScheduleOptionsEnableDisable(this)" name="vpnmgr_'+prefix+'_schenabled" id="vpnmgr_'+prefix+'_sch_false" class="input" value="false" checked><label for="vpnmgr_'+prefix+'_sch_false">No</label></td>';
	charthtml+='</tr>';
	
	/* SCHEDULE DAYS */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(10);">Schedule Days</a></td><td class="settingvalue">';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_mon" class="input" value="Mon"><label for="vpnmgr_'+prefix+'_mon">Mon</label>';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_tues" class="input" value="Tues"><label for="vpnmgr_'+prefix+'_tues">Tues</label>';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_wed" class="input" value="Wed"><label for="vpnmgr_'+prefix+'_wed">Wed</label>';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_thurs" class="input" value="Thurs"><label for="vpnmgr_'+prefix+'_thurs">Thurs</label>';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_fri" class="input" value="Fri"><label for="vpnmgr_'+prefix+'_fri">Fri</label>';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_sat" class="input" value="Sat"><label for="vpnmgr_'+prefix+'_sat">Sat</label>';
	charthtml+='<input type="checkbox" name="vpnmgr_'+prefix+'_schdays" id="vpnmgr_'+prefix+'_sun" class="input" value="Sun"><label for="vpnmgr_'+prefix+'_sun">Sun</label>';
	charthtml+='</td></tr>';
	
	/* SCHEDULE MODE */
	charthtml+='<tr>';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(11);">Schedule Mode</a></td><td class="settingvalue"><input type="radio" onchange="ScheduleModeToggle(this)" name="'+prefix+'_schedulemode" id="'+prefix+'_schmode_everyx" class="input" value="EveryX" checked><label for="'+prefix+'_schmode_everyx">Every X hours/minutes</label><input type="radio" onchange="ScheduleModeToggle(this)" name="'+prefix+'_schedulemode" id="'+prefix+'_schmode_custom" class="input" value="Custom"><label for="'+prefix+'_schmode_custom">Custom</label>';
	charthtml+='</tr>';
	
	/* SCHEDULE FREQUENCY */
	charthtml+='<tr id="'+prefix+'_schedulefrequency">';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(12);">Frequency</a></td>';
	charthtml+='<td class="settingvalue"><span style="color:#FFFFFF;margin-left:3px;">Every </span>';
	charthtml+='<input autocomplete="off" style="text-align:center;padding-left:2px;" type="text" maxlength="2" class="input_3_table removespacing" name="'+prefix+'_everyxvalue" id="'+prefix+'_everyxvalue" value="1" onkeypress="return validator.isNumber(this,event)" onkeyup="Validate_ScheduleValue(this)" onblur="Validate_ScheduleValue(this)" />';
	charthtml+='&nbsp;<select name="'+prefix+'_everyxselect" id="'+prefix+'_everyxselect" class="input_option" onchange="EveryXToggle(this)">';
	charthtml+='<option value="hours">hours</option><option value="minutes">minutes</option></select>';
	charthtml+='<span id="'+prefix+'_spanxhours" style="color:#FFCC00;"> (between 1 and 24)</span>';
	charthtml+='<span id="'+prefix+'_spanxminutes" style="color:#FFCC00;"> (between 1 and 30)</span>';
	charthtml+='</td></tr>';
	
	/* SCHEDULE CUSTOM HOURS */
	charthtml+='<tr id="'+prefix+'_customhours">';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(13);">Schedule Hours</a></td><td class="settingvalue"><input data-lpignore="true" autocomplete="off" autocapitalize="off" type="text" class="input_32_table" name="vpnmgr_'+prefix+'_schhours" value="*" onkeyup="Validate_Schedule(this,\'hours\')" onblur="Validate_Schedule(this,\'hours\')" /></td>';
	charthtml+='</tr>';
	
	/* SCHEDULE CUSTOM MINS */
	charthtml+='<tr id="'+prefix+'_custommins">';
	charthtml+='<td class="settingname"><a class="hintstyle" href="javascript:void(0);" onclick="SettingHint(14);">Schedule Minutes</a></td><td class="settingvalue"><input data-lpignore="true" autocomplete="off" autocapitalize="off" type="text" class="input_32_table" name="vpnmgr_'+prefix+'_schmins" value="*" onkeyup="Validate_Schedule(this,\'mins\')" onblur="Validate_Schedule(this,\'mins\')" /></td>';
	charthtml+='</tr>';
	
	charthtml+='</table>';
	charthtml+='</td>';
	charthtml+='</tr>';
	charthtml+='</table>';
	return charthtml;
}

function AddEventHandlers(){
	$j('.collapsible-jquery').click(function(){
		$j(this).siblings().toggle('fast',function(){
			if($j(this).css('display') == 'none'){
				SetCookie($j(this).siblings()[0].id,'collapsed');
			}
			else{
				SetCookie($j(this).siblings()[0].id,'expanded');
			}
		})
	});
	$j('.collapsible-jquery').each(function(index,element){
		if(GetCookie($j(this)[0].id,'string') == 'collapsed'){
			$j(this).siblings().toggle(false);
		}
		else{
			$j(this).siblings().toggle(true);
		}
	});
}

$j.fn.serializeObject = function(){
	var o = custom_settings;
	var a = this.serializeArray();
	$j.each(a,function(){
		if (o[this.name] !== undefined && this.name.indexOf('vpnmgr') != -1 && this.name.indexOf('version') == -1 && this.name.indexOf('schdays') == -1 && this.name.indexOf('countryid') == -1 && this.name.indexOf('cityid') == -1){
			if (!o[this.name].push){
				o[this.name] = [o[this.name]];
			}
			o[this.name].push(this.value || '');
		}
		else if (this.name.indexOf('vpnmgr') != -1 && this.name.indexOf('version') == -1 && this.name.indexOf('schdays') == -1 && this.name.indexOf('countryid') == -1 && this.name.indexOf('cityid') == -1){
			o[this.name] = this.value || '';
		}
	});
	for(var i=1; i < 6; i++){
		var schdays = [];
		$j.each($j('input[name="vpnmgr_vpn'+i+'_schdays"]:checked'),function(){
			schdays.push($j(this).val());
		});
		var schdaysstring = schdays.join(',');
		if(schdaysstring == 'Mon,Tues,Wed,Thurs,Fri,Sat,Sun'){
			schdaysstring = '*';
		}
		o['vpnmgr_vpn'+i+'_schdays'] = schdaysstring;
		
		var selectedprovider = $j('input[name="vpnmgr_vpn'+i+'_provider"]:checked').val();
		var selectedpid = selectedprovider ? selectedprovider.toLowerCase() : '';
		if(selectedpid == 'nordvpn' && $j('select[name="vpnmgr_vpn'+i+'_countryname"]').val() != ''){
			var nordcountries = providerCountries['nordvpn'] || [];
			o['vpnmgr_vpn'+i+'_countryid'] = nordcountries.filter(function(item){
				return item.name == $j('select[name="vpnmgr_vpn'+i+'_countryname"]').val();
			}).map(function(d){return d.id})[0] || 0;
			if($j('select[name="vpnmgr_vpn'+i+'_cityname"]').val() == ''){
				o['vpnmgr_vpn'+i+'_cityid'] = 0;
			}
			else{
				var nordcity = nordcountries.filter(function(item){
					return item.name == $j('select[name="vpnmgr_vpn'+i+'_countryname"]').val();
				})[0];
				o['vpnmgr_vpn'+i+'_cityid'] = nordcity ? nordcity.cities.filter(function(item){
					return item.name == $j('select[name="vpnmgr_vpn'+i+'_cityname"]').val();
				}).map(function(d){return d.id})[0] || 0 : 0;
			}
		}
		else{
			o['vpnmgr_vpn'+i+'_countryid'] = 0;
			o['vpnmgr_vpn'+i+'_cityid'] = 0;
		}
	}
	return o;
};

function ScriptUpdateLayout(){
	var localver = GetVersionNumber('local');
	var serverver = GetVersionNumber('server');
	$j('#vpnmgr_version_local').text(localver);
	
	if (localver != serverver && serverver != 'N/A'){
		$j('#vpnmgr_version_server').text('Updated version available: '+serverver);
		showhide('btnChkUpdate',false);
		showhide('vpnmgr_version_server',true);
		showhide('btnDoUpdate',true);
	}
}

function update_status(){
	$j.ajax({
		url: '/ext/vpnmgr/detect_update.js',
		dataType: 'script',
		error: function(xhr){
			setTimeout(update_status,1000);
		},
		success: function(){
			if (updatestatus == 'InProgress'){
				setTimeout(update_status,1000);
			}
			else{
				document.getElementById('imgChkUpdate').style.display = 'none';
				showhide('vpnmgr_version_server',true);
				if(updatestatus != 'None'){
					$j('#vpnmgr_version_server').text('Updated version available: '+updatestatus);
					showhide('btnChkUpdate',false);
					showhide('btnDoUpdate',true);
				}
				else{
					$j('#vpnmgr_version_server').text('No update available');
					showhide('btnChkUpdate',true);
					showhide('btnDoUpdate',false);
				}
			}
		}
	});
}

function CheckUpdate(){
	showhide('btnChkUpdate',false);
	document.formScriptActions.action_script.value='start_vpnmgrcheckupdate';
	document.formScriptActions.submit();
	document.getElementById('imgChkUpdate').style.display = '';
	setTimeout(update_status,2000);
}

function DoUpdate(){
	var action_script_tmp = 'start_vpnmgrdoupdate';
	document.form.action_script.value = action_script_tmp;
	var restart_time = 10;
	document.form.action_wait.value = restart_time;
	showLoading();
	document.form.submit();
}

function getserverload_status(){
	$j.ajax({
		url: '/ext/vpnmgr/vpnmgrserverloads.js',
		dataType: 'script',
		error: function(xhr){
			//do nothing
		},
		success: function(data){
			clearInterval(getserverloadinterval);
			showhide('imgGetServerLoad',false);
			showhide('getserverload_text',true);
			
			for(var i=1; i<=5; i++){
				try{
					if($j('#vpnmgr_vpn'+i+'_desc').html().indexOf('|') != -1){
						$j('#vpnmgr_vpn'+i+'_desc').html($j('#vpnmgr_vpn'+i+'_desc').html().substring(0,$j('#vpnmgr_vpn'+i+'_desc').html().indexOf('|')-1)+' | '+eval('vpn'+i+'_serverload')+'%');
					}
					else{
						$j('#vpnmgr_vpn'+i+'_desc').html($j('#vpnmgr_vpn'+i+'_desc').html()+' | '+eval('vpn'+i+'_serverload')+'%');
					}
				}
				catch(err){
					continue;
				}
			}
			setTimeout(showhide,3000,'getserverload_text',false);
			setTimeout(showhide,3100,'btnGetServerLoad',true);
		}
	});
}

function GetServerLoad(){
	showhide('btnGetServerLoad',false);
	document.formScriptActions.action_script.value = 'start_vpnmgrgetserverload';
	document.formScriptActions.submit();
	showhide('imgGetServerLoad',true);
	showhide('getserverload_text',false);
	setTimeout(StartGetServerLoadInterval,5000);
}

function StartGetServerLoadInterval(){
	getserverloadinterval = setInterval(getserverload_status,1000);
}

function RefreshCachedData(){
	showhide('btnRefreshCachedData',false);
	document.formScriptActions.action_script.value = 'start_vpnmgrrefreshcacheddata';
	document.formScriptActions.submit();
	showhide('imgRefreshCachedData',true);
	showhide('refreshcacheddata_text',false);
	setTimeout(StartRefreshCachedDataInterval,5000);
}

function StartRefreshCachedDataInterval(){
	refreshcacheddatainterval = setInterval(refreshcacheddata_status,1000);
}

var refreshcount=1;
function refreshcacheddata_status(){
	refreshcount++;
	$j.ajax({
		url: '/ext/vpnmgr/detect_vpnmgr.js',
		dataType: 'script',
		error: function(xhr){
			//do nothing
		},
		success: function(){
			if (refreshcacheddatastatus == 'InProgress'){
				showhide('imgRefreshCachedData',true);
				showhide('refreshcacheddata_text',true);
				document.getElementById('refreshcacheddata_text').innerHTML = 'Cached data refresh in progress - '+refreshcount+'s elapsed';
			}
			else if (refreshcacheddatastatus == 'Done'){
				document.getElementById('refreshcacheddata_text').innerHTML = 'Refreshing data...';
				refreshcount=1;
				clearInterval(refreshcacheddatainterval);
				PostRefreshCachedData();
			}
			else if (refreshcacheddatastatus == 'LOCKED'){
				showhide('imgRefreshCachedData',false);
				document.getElementById('refreshcacheddata_text').innerHTML = 'Cached data refresh already running!';
				showhide('refreshcacheddata_text',true);
				showhide('btnRefreshCachedData',true);
				clearInterval(refreshcacheddatainterval);
			}
		}
	});
}

function PostRefreshCachedData(){
	for (var vpnno = 1; vpnno < 6; vpnno++){
		$j('#table_config_vpn'+vpnno).prev('div').remove();
		$j('#table_config_vpn'+vpnno).remove();
	}
	vpnmgr_providers = [];
	providerCountries = {};
	setTimeout(GetProviderList,3000);
}

function GetVersionNumber(versiontype){
	var versionprop;
	if(versiontype == 'local'){
		versionprop = custom_settings.vpnmgr_version_local;
	}
	else if(versiontype == 'server'){
		versionprop = custom_settings.vpnmgr_version_server;
	}
	
	if(typeof versionprop == 'undefined' || versionprop == null){
		return 'N/A';
	}
	else{
		return versionprop;
	}
}

function GetProviderList(){
	$j.ajax({
		url: '/ext/vpnmgr/providers.htm',
		dataType: 'text',
		error: function(){
			get_conf_file();
		},
		success: function(data){
			var lines = data.split('\n');
			for(var i = 0; i < lines.length; i++){
				if(!lines[i]) continue;
				var parts = lines[i].split('|');
				if(parts.length >= 2){
					vpnmgr_providers.push({id: parts[0], name: parts[1]});
				}
			}
			LoadProviderCountryData(0);
		}
	});
}

function LoadProviderCountryData(idx){
	if(idx >= vpnmgr_providers.length){ get_conf_file(); return; }
	var p = vpnmgr_providers[idx];
	$j.ajax({
		url: '/ext/vpnmgr/' + p.id + '_countrydata.htm',
		dataType: p.id === 'nordvpn' ? 'json' : 'text',
		error: function(){
			LoadProviderCountryData(idx + 1);
		},
		success: function(data){
			providerCountries[p.id] = (p.id === 'nordvpn') ? data : parseCountryData(data);
			LoadProviderCountryData(idx + 1);
		}
	});
}

function parseCountryData(rawcountrydata){
	var parsedarray = [];
	
	var tmpcountries = [];
	tmpcountries = rawcountrydata.split('\n');
	tmpcountries = tmpcountries.filter(Boolean);
	
	var tmpcountriessorted = [];
	
	var citiesAU = [];
	var citiesCA = [];
	var citiesDE = [];
	var citiesUS = [];
	var citiesUAE = [];
	var citiesUK = [];
	var citiesAT = [];
	var citiesBE = [];
	var citiesBG = [];
	var citiesBR = [];
	var citiesCH = [];
	var citiesCZ = [];
	var citiesDK = [];
	var citiesES = [];
	var citiesFR = [];
	var citiesHK = [];
	var citiesHU = [];
	var citiesIE = [];
	var citiesIL = [];
	var citiesIN = [];
	var citiesIT = [];
	var citiesJP = [];
	var citiesMX = [];
	var citiesNL = [];
	var citiesNO = [];
	var citiesNZ = [];
	var citiesPL = [];
	var citiesRO = [];
	var citiesRS = [];
	var citiesSE = [];
	var citiesSG = [];
	var citiesZA = [];
	
	$j.each(tmpcountries,function (index,value){
		if(getCountryCode(value) == 'AU'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('AU ',''));
			citiesAU.push(obj);
			value = 'Australia';
		}
		else if(getCountryCode(value) == 'CA'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('CA ',''));
			citiesCA.push(obj);
			value = 'Canada';
		}
		else if(getCountryCode(value) == 'DE'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('DE ',''));
			citiesDE.push(obj);
			value = 'Germany';
		}
		else if(getCountryCode(value) == 'US'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('US ',''));
			citiesUS.push(obj);
			value = 'United States';
		}
		else if(getCountryCode(value) == 'AT'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('AT ',''));
			citiesAT.push(obj);
			value = 'Austria';
		}
		else if(getCountryCode(value) == 'BE'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('BE ',''));
			citiesBE.push(obj);
			value = 'Belgium';
		}
		else if(getCountryCode(value) == 'BG'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('BG ',''));
			citiesBG.push(obj);
			value = 'Bulgaria';
		}
		else if(getCountryCode(value) == 'BR'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('BR ',''));
			citiesBR.push(obj);
			value = 'Brazil';
		}
		else if(getCountryCode(value) == 'CH'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('CH ',''));
			citiesCH.push(obj);
			value = 'Switzerland';
		}
		else if(getCountryCode(value) == 'CZ'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('CZ ',''));
			citiesCZ.push(obj);
			value = 'Czech Republic';
		}
		else if(getCountryCode(value) == 'DK'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('DK ',''));
			citiesDK.push(obj);
			value = 'Denmark';
		}
		else if(getCountryCode(value) == 'ES'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('ES ',''));
			citiesES.push(obj);
			value = 'Spain';
		}
		else if(getCountryCode(value) == 'FR'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('FR ',''));
			citiesFR.push(obj);
			value = 'France';
		}
		else if(getCountryCode(value) == 'HK'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('HK ',''));
			citiesHK.push(obj);
			value = 'Hong Kong';
		}
		else if(getCountryCode(value) == 'HU'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('HU ',''));
			citiesHU.push(obj);
			value = 'Hungary';
		}
		else if(getCountryCode(value) == 'IE'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('IE ',''));
			citiesIE.push(obj);
			value = 'Ireland';
		}
		else if(getCountryCode(value) == 'IL'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('IL ',''));
			citiesIL.push(obj);
			value = 'Israel';
		}
		else if(getCountryCode(value) == 'IN'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('IN ',''));
			citiesIN.push(obj);
			value = 'India';
		}
		else if(getCountryCode(value) == 'IT'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('IT ',''));
			citiesIT.push(obj);
			value = 'Italy';
		}
		else if(getCountryCode(value) == 'JP'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('JP ',''));
			citiesJP.push(obj);
			value = 'Japan';
		}
		else if(getCountryCode(value) == 'MX'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('MX ',''));
			citiesMX.push(obj);
			value = 'Mexico';
		}
		else if(getCountryCode(value) == 'NL'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('NL ',''));
			citiesNL.push(obj);
			value = 'Netherlands';
		}
		else if(getCountryCode(value) == 'NO'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('NO ',''));
			citiesNO.push(obj);
			value = 'Norway';
		}
		else if(getCountryCode(value) == 'NZ'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('NZ ',''));
			citiesNZ.push(obj);
			value = 'New Zealand';
		}
		else if(getCountryCode(value) == 'PL'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('PL ',''));
			citiesPL.push(obj);
			value = 'Poland';
		}
		else if(getCountryCode(value) == 'RO'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('RO ',''));
			citiesRO.push(obj);
			value = 'Romania';
		}
		else if(getCountryCode(value) == 'RS'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('RS ',''));
			citiesRS.push(obj);
			value = 'Serbia';
		}
		else if(getCountryCode(value) == 'SE'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('SE ',''));
			citiesSE.push(obj);
			value = 'Sweden';
		}
		else if(getCountryCode(value) == 'SG'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('SG ',''));
			citiesSG.push(obj);
			value = 'Singapore';
		}
		else if(getCountryCode(value) == 'UAE' || getCountryCode(value) == 'AE'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('UAE ','').replaceAll('AE ',''));
			citiesUAE.push(obj);
			value = 'United Arab Emirates';
		}
		else if(getCountryCode(value) == 'UK' || getCountryCode(value) == 'GB'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('UK ','').replaceAll('GB ',''));
			citiesUK.push(obj);
			value = 'United Kingdom';
		}
		else if(getCountryCode(value) == 'ZA'){
			var obj = {};
			obj['name'] = capitalizeFirstLetter(value.replaceAll('_',' ').replaceAll('ZA ',''));
			citiesZA.push(obj);
			value = 'South Africa';
		}
		else{
			value = capitalizeFirstLetter(value.replaceAll('_',' '));
		}
		
		tmpcountriessorted.push(value)
	});
	tmpcountriessorted.sort();
	
	var unique = [];
	for(var i = 0; i < tmpcountriessorted.length; i++){
		if(!unique[tmpcountriessorted[i]]){
			var obj = {};
			obj['name']=tmpcountriessorted[i];
			parsedarray.push(obj);
			unique[tmpcountriessorted[i]] = 1;
		}
	}
	
	$j.each(parsedarray,function (key,entry){
		if(entry.name == 'Australia'){
			entry['cities'] = citiesAU;
		}
		else if(entry.name == 'Canada'){
			entry['cities'] = citiesCA;
		}
		else if(entry.name == 'Germany'){
			entry['cities'] = citiesDE;
		}
		else if(entry.name == 'United States'){
			entry['cities'] = citiesUS;
		}
		else if(entry.name == 'United Arab Emirates'){
			entry['cities'] = citiesUAE;
		}
		else if(entry.name == 'United Kingdom'){
			entry['cities'] = citiesUK;
		}
		else if(entry.name == 'Austria'){
			entry['cities'] = citiesAT;
		}
		else if(entry.name == 'Belgium'){
			entry['cities'] = citiesBE;
		}
		else if(entry.name == 'Bulgaria'){
			entry['cities'] = citiesBG;
		}
		else if(entry.name == 'Brazil'){
			entry['cities'] = citiesBR;
		}
		else if(entry.name == 'Switzerland'){
			entry['cities'] = citiesCH;
		}
		else if(entry.name == 'Czech Republic'){
			entry['cities'] = citiesCZ;
		}
		else if(entry.name == 'Denmark'){
			entry['cities'] = citiesDK;
		}
		else if(entry.name == 'Spain'){
			entry['cities'] = citiesES;
		}
		else if(entry.name == 'France'){
			entry['cities'] = citiesFR;
		}
		else if(entry.name == 'Hong Kong'){
			entry['cities'] = citiesHK;
		}
		else if(entry.name == 'Hungary'){
			entry['cities'] = citiesHU;
		}
		else if(entry.name == 'Ireland'){
			entry['cities'] = citiesIE;
		}
		else if(entry.name == 'Israel'){
			entry['cities'] = citiesIL;
		}
		else if(entry.name == 'India'){
			entry['cities'] = citiesIN;
		}
		else if(entry.name == 'Italy'){
			entry['cities'] = citiesIT;
		}
		else if(entry.name == 'Japan'){
			entry['cities'] = citiesJP;
		}
		else if(entry.name == 'Mexico'){
			entry['cities'] = citiesMX;
		}
		else if(entry.name == 'Netherlands'){
			entry['cities'] = citiesNL;
		}
		else if(entry.name == 'Norway'){
			entry['cities'] = citiesNO;
		}
		else if(entry.name == 'New Zealand'){
			entry['cities'] = citiesNZ;
		}
		else if(entry.name == 'Poland'){
			entry['cities'] = citiesPL;
		}
		else if(entry.name == 'Romania'){
			entry['cities'] = citiesRO;
		}
		else if(entry.name == 'Serbia'){
			entry['cities'] = citiesRS;
		}
		else if(entry.name == 'Sweden'){
			entry['cities'] = citiesSE;
		}
		else if(entry.name == 'Singapore'){
			entry['cities'] = citiesSG;
		}
		else if(entry.name == 'South Africa'){
			entry['cities'] = citiesZA;
		}
		else{
			entry['cities'] = [];
		}
	});
	
	return parsedarray;
}

function setCitiesforCountry(forminput){
	var inputname = forminput.name;
	var inputvalue = forminput.value;
	var prefix = inputname.substring(0,inputname.lastIndexOf('_'));

	var dropdown = $j('select[name='+prefix+'_cityname]');
	dropdown.empty();

	var pid = eval('document.form.'+prefix+'_provider').value.toLowerCase();
	var cityarray = providerCountries[pid] || [];
	if(pid == 'nordvpn'){
		dropdown.append('<option selected="true"></option>');
	}

	$j.each(cityarray,function (key,entry){
		if(entry.name != $j('select[name='+prefix+'_countryname]').val()){
			return true;
		}
		else{
			$j.each(entry.cities,function (key2,entry2){
				dropdown.append($j('<option></option>').attr('value',entry2.name).text(entry2.name));
			});
			
			if(dropdown[0].length == 2 && dropdown.find('option:first-child').val().length == 0){
				//dropdown.find('option:first-child').remove();
				dropdown.prop('selectedIndex',0);
			}
			else{
				dropdown.prop('selectedIndex',0);
			}
			
			return false;
		}
	});
	
	if(inputvalue == ''){
		dropdown.prop('disabled',true);
	}
	else if(inputvalue != ''){
		dropdown.prop('disabled',false);
	}
	
	if(dropdown[0].length == 0){
		dropdown.prop('disabled',true);
	}
	else{
		dropdown.prop('disabled',false);
	}
}

function capitalizeFirstLetter(string){
	return string.replace(/(^\w{1})|(\s{1}\w{1})/g,function(match){ return match.toUpperCase(); });
}

function getCountryCode(string){
	string = string.replaceAll(' ','_');
	if(string.indexOf('_') != -1){
		return string.substring(0,string.indexOf('_')).toUpperCase();
	}
	else{
		return string.toUpperCase();
	}
}

String.prototype.replaceAll = function(strReplace,strWith){
	/* See http://stackoverflow.com/a/3561711/556609 */
	var esc = strReplace.replace(/[-\/\\^$*+?.()|[\]{}]/g,'\\$&');
	var reg = new RegExp(esc,'ig');
	return this.replace(reg,strWith);
};
