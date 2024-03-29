#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021-2022 Ethan Dye
# All rights reserved.
#
# tidies up things just after the end of each hour
# run: by cron
# History
# 2020-01-26: 4.0.7 - changed to list Tomato cru jobs in the log (thx tvlz)
# 2020-01-03: 4.0.6 - get acRules based upon firmware
# 2019-12-23: 4.0.5 - added log messages; added JS to head of tmplogFile
# 2019-11-24: 4.0.4 - no changes (yet)
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/shared.sh"
source "${d_baseDir}/includes/traffic.sh"

hr="$(echo $_ts | cut -d':' -f1)"
sleep 59
Send2Log "End of hour: $hr (${_ds})" 1

GetTraffic '-vnxZ'  # get the data and zero the tables

sleep 10 # delay ~10 seconds into next hour to allow tasks from previous hour to finish... might have to adjust this value

Send2Log "End of hour: append \`$rawtraffic_hr\` to \`$rawtraffic_day\`"
cat "$rawtraffic_hr" >> "$rawtraffic_day"

if [ "$_firmware" -eq "0" ] ; then
	acRules="$(cat /tmp/cron.d/yamon_jobs)"
elif [ "$_firmware" -eq "3" ] || [ "$_firmware" -eq "2" ] || [ "$_firmware" -eq "5" ]; then
	acRules="$(cru l | grep "yamon")"
else
	acRules="$(crontab -l)"
fi

Send2Log "crontab: $(IndentList "$acRules")"
[ -n "$_dbkey" ] && Send2Log "blocked: $(IndentList "$(iptables -L | grep blocked -B 2)")" 2
Send2Log "End of hour: append \`$tmplogFile\` to \`$dailyLogFile\`" 2
#contents of tmplog minus the header lines
tmplogContents=$(cat "$tmplogFile" | grep -v "<\(/\{0,1\}head\|html\|meta\|link\|script\|head\|body\|!--header--\|!DOCTYPE\)")

echo "$tmplogContents</div>" | sed -E -e "s~^ ([^<].*$)~<pre>\1</pre>~g" -e "s~(^[^<].*$)~<p class='err'>\1</p>~g" >> "$dailyLogFile"

#use temp timestamps to catch the change of hour & date
tds=$(date +"%Y-%m-%d")
thr=$(date +"%H")
#reset the temporary log file
echo "<!DOCTYPE html>
<html lang='en-US'>
<head>
<meta charset='utf-8'/>
<meta http-equiv='cache-control' content='no-cache'/>
<meta name='viewport' content='width=device-width,initial-scale=1.0'/>
<title>YAMon: Logs</title>
<link rel='stylesheet' href='https://code.jquery.com/ui/1.13.0/themes/smoothness/jquery-ui.min.css'>
<link rel='stylesheet' type='text/css' href='../css/normalize.min.css'>
<link rel='stylesheet' type='text/css' href='../css/logs.css'>
<script src='https://code.jquery.com/jquery-3.6.0.min.js'></script>
<script src='https://code.jquery.com/ui/1.13.0/jquery-ui.min.js'></script>
<script src='../js/logs.js'></script>
<link rel='shortcut icon' href='../images/favicon.png'/>
</head>
<body>
<div id='header'> <!--header-->
<h1>Log for <span id='logDate'>${tds}</span></h1> <!--header-->
<p>Show: <label><input class='filter' type='checkbox' name='no-errors' checked>Errors</label><label><input class='filter' type='checkbox' name='no-ll2' checked>Level 2</label><label><input class='filter' type='checkbox' name='no-ll1' checked>Level 1</label><label><input class='filter' type='checkbox' name='no-ll0'>Level 0</label></p> <!--header-->
</div> <!--header-->
<div class='hour-contents'><p>Hour: ${thr}</p>
" > "$tmplogFile"

Send2Log "End of hour: remove \`$rawtraffic_hr\`"
rm "$rawtraffic_hr"

Send2Log "Processes: $(IndentList "$(ps | grep -v grep | grep "$d_baseDir")")"

LogEndOfFunction
