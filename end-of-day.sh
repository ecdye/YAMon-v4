#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021 Ethan Dye
# All rights reserved.
#
# wraps things up at the end of each day
# run: by cron
# History
# 2020-01-26: 4.0.7 - no changes
# 2020-01-03: 4.0.6 - no changes
# 2019-12-23: 4.0.5 - no changes
# 2019-11-24: 4.0.4 - added '2>/dev/null ' to tar call to prevent spurious messages in the logs
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

DeactiveIdleDevices() {
	local _activeIPs
	local _inActiveIPs
	local lastseen
	local line
	local id
	local ls
	local wl
	local newline
	local changes1
	local changes2

  _activeIPs="$(cat "$_usersFile" | grep -e '^mac2ip({.*})$' | grep '"active":"1"')"

	Send2Log "DeactiveIdleDevices - _activeIPs"
	IFS=$'\n'
	for line in $_activeIPs; do
		[ -z "$line" ] && continue
		id="$(GetField "$line" 'id')"
		ls="$(GetField "$(echo "$lastseen" | grep "$id")" 'last-seen')"
		ods="$(date --date=@"$(DigitSub "$(date --date="$_ds" +%s)" "2592000")" +%s)"
		if [ -z "$ls" ] || [ "$ods" -ge "$(date --date="$ls" +%s)" ]; then
			newline="$(UpdateField "$line" 'active' '0')"
			newline="$(UpdateField "$newline" 'updated' "$_ds $_ts")"
			sed -i "s~${line}~${newline}~g" "$_usersFile"
			cat "$tmpLastSeen" | grep -e '^lastseen({.*})$' | grep -v "\"$id\"" > $tmpLastSeen
			cp "$tmpLastSeen" "$_lastSeenFile"
			# TODO: cull the inactive entries from iptables?!?
			Send2Log "DeactiveIdleDevices: $id set to inactive (based upon users.js)" 1
			changes1=1
	  fi
	done
	unset IFS
	[ -z "$changes1" ] && Send2Log "DeactiveIdleDevices: no active devices deactivated"

	_inActiveIPs="$(cat "$_usersFile" | grep -e '^mac2ip({.*})$' | grep '"active":"0"')"
	[ -f "$_lastSeenFile" ] && lastseen="$(cat "$_lastSeenFile" | grep -e '^lastseen({.*})$')"
	Send2Log "DeactiveIdleDevices - lastseen"
	IFS=$'\n'
	for line in $lastseen; do
		[ -z "$line" ] && continue
		id="$(GetField "$line" 'id')"
		wl="$(echo "$_inActiveIPs" | grep "\"$id\"")"
		if [ -n "$wl" ]; then
			newline="$(UpdateField "$wl" 'active' '1')"
			newline="$(UpdateField "$newline" 'updated' "$_ds $_ts")"
			sed -i "s~${wl}~${newline}~" "$_usersFile"
			Send2Log "DeactiveIdleDevices: $id set to active (based upon lastseen.js)" 1
			changes2=1
		fi
	done
	unset IFS
	[ -z "$changes2" ] && Send2Log "DeactiveIdleDevices: no deactived devices activated"
	[ -n "$changes1" ] || [ -n "$changes2" ] && UsersJSUpdated
}

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/shared.sh"
source "${d_baseDir}/includes/dailytotals.sh"
[ -n "$1" ] && _ds="$1"
sleep 75 # wait until all tasks for the day should've been completed... may have to adjust this value

Send2Log "End of day: $_ds" 1
Send2Log "End of day: copy $hourlyDataFile --> $_path2CurrentMonth"
cp "$hourlyDataFile" "$_path2CurrentMonth"

# Calculate the daily totals
Send2Log "End of day: tally the traffic for the day and update the monthly file"
CalculateDailyTotals "$_ds" "$_intervalDataFile"

Send2Log "End of day: backup files as required"
cp "$tmplogFile" "$_path2logs"

[ "$_doDailyBU" -eq "1" ] && tar -chzf "${_path2bu}bu-${_ds}.tar.gz" $_usersFile $tmpLastSeen "$(find -L ${d_baseDir} | grep "$_ds")" 2>/dev/null && Send2Log "End of day: archive date specific files to '${_path2bu}bu-${_ds}.tar.gz'"
rm -f "$(find "$tmplog" | grep "$_ds")" # delete the date specific files

DeactiveIdleDevices

LogEndOfFunction
