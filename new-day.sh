#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-present Al Caughey
# All rights reserved.
#
# run scripts needed at the start of a new day
# run: by cron
# History
# 2020-01-26: 4.0.7 - no changes
# 2020-01-03: 4.0.6 - no changes
# 2019-12-23: 4.0.5 - added symlinks for day and hour logs
# 2019-11-24: 4.0.4 - no changes (yet)
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/shared.sh"
ChangePath 'rawtraffic_day' "${_path2CurrentMonth}raw-traffic-${_ds}.txt"
hourlyDataFile="${tmplog}hourly_${_ds}.js"
dailyLogFile="${_path2logs}${_ds}.html"
ChangePath 'hourlyDataFile' "$hourlyDataFile"
ChangePath 'dailyLogFile' "$dailyLogFile"
[ "${_doArchiveLiveUpdates:-0}" -eq "1" ] && ChangePath '_liveArchiveFilePath' "${_path2CurrentMonth}${_ds}-live_data4.js"
if [ ! -f "$hourlyDataFile" ] ; then
	echo -e "var hourly_created=\"${_ds} ${_ts}\"\nvar hourly_updated=\"${_ds} ${_ts}\"\nvar serverUptime=\"${_uptime}\"\n" > "$hourlyDataFile"
fi
Send2Log "New day: $_ds (${hourlyDataFile})" 1

[ ! -f "$dailyLogFile" ] && true > "$rawtraffic_day"
[ ! -f "$dailyLogFile" ] && echo "<!DOCTYPE html>
<html lang='en'>
<head>
<meta http-equiv='cache-control' content='no-cache' />
<meta http-equiv='Content-Type' content='text/html;charset=utf-8' />
<link rel='stylesheet' href='https://code.jquery.com/ui/1.13.0/themes/smoothness/jquery-ui.min.css'>
<link rel='stylesheet' type='text/css' href='../css/normalize.min.css'>
<link rel='stylesheet' type='text/css' href='../css/logs.css'>
<script src='https://code.jquery.com/jquery-3.6.0.min.js'></script>
<script src='https://code.jquery.com/ui/1.13.0/jquery-ui.min.js'></script>
<script src='../js/logs.js'></script>
<link rel='shortcut icon' href='../images/favicon.png'/>
</head>
<body>
<div id='header'>
<h1>Log for <span id='logDate'>${_ds}</span></h1>
<p>Show: <label><input class='filter' type='checkbox' name='no-errors' checked>Errors</label><label><input class='filter' type='checkbox' name='no-ll2' checked>Level 2</label><label><input class='filter' type='checkbox' name='no-ll1' checked>Level 1</label><label><input class='filter' type='checkbox' name='no-ll0'>Level 0</label></p>
</div><div id='log-contents' class='no-ll0'>
" > "$dailyLogFile"

# update the day-log symlink
nll="${_path2logs%/}/${_ds}.html"
oll="${_wwwPath}logs/day-log.html"
[ -h "$oll" ] && rm -fv "$oll"
ln -s "$nll" "$oll"
Send2Log "new-day: day log changed from  $oll --> $nll" 1

LogEndOfFunction
