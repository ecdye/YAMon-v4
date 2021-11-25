#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021 Ethan Dye
# All rights reserved.
#
# updates the data for the live tab
# run: by cron
# History
# 2020-01-26: 4.0.7 - no changes
# 2020-01-03: 4.0.6 - added current traffic to the output file
# 2019-12-23: 4.0.5 - no changes
# 2019-11-24: 4.0.4 - no changes (yet)
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/shared.sh"
source "${d_baseDir}/includes/traffic.sh"

Send2Log "Running update-live-data"

CurrentConnections_0() { # _doCurrConnections=0 --> do nothing, the option is disabled
	return
}

CurrentConnections_1() { # _doCurrConnections=1
	local ip4t
	local ip6t
	local ipt
	local macIP
	local ip
	local tip
	local "do"
	local up
	local mac
	local ddd
	local err

	IP6Enabled() {
		echo "$(ip6tables -L "$YAMON_IPTABLES" -vnx $_iptablesWait | grep -v RETURN | awk '{ print $2,$7,$8 }' | grep "^[1-9]")"
	}
	NoIP6() {
		echo
	}
	ArchiveLiveUpdates_0() { # _doArchiveLiveUpdates=0 --> do nothing, the option is disabled
		return
	}
	ArchiveLiveUpdates_1() { # _doArchiveLiveUpdates=1
	  local diskUtilization

		diskUtilization="$(df "$d_baseDir" | tail -n 1 | awk '{ print $(NF-1) }' | cut -d'%' -f1)"
		if [ "$diskUtilization" -lt 90 ]; then
			cat "$_liveFilePath" >> $_liveArchiveFilePath
		else
			Send2Log "ArchiveLiveUpdates_: skipped because of low disk space: $diskUtilization" 3
		fi
	}

	# to-do - grab the iptables data and send along with the live data
	ip4t=$(iptables -L "$YAMON_IPTABLES" -vnx $_iptablesWait | grep -v RETURN | awk '{ print $2,$8,$9 }' | grep "^[1-9]")
	ip6t="$($ip6tablesFn)"
	ipt="$ip4t\n$ip6t"
	macIP="$(cat "$macIPFile")"

	echo -e "\n/*current traffic by device:*/" >> $_liveFilePath
	while true; do
		[ -z "$ipt" ] && break
		fl="$(echo -e "$ipt" | head -n 1)"
		[ -z "$fl" ] && break
		ip="$(echo "$fl" | cut -d' ' -f2)"
		if [ "$_generic_ipv4" == "$ip" ] || [ "$_generic_ipv6" == "$ip" ]; then
			ip="$(echo "$fl" | cut -d' ' -f3)"
		fi
		if [ "$_generic_ipv4" == "$ip" ] || [ "$_generic_ipv6" == "$ip" ]; then
			ipt="$(echo -e "$ipt" | grep -v "$fl")" # delete just the first entry from the list of IPs
		else
			tip="\b${ip//\./\\.}\b"
			do="$(echo "$ipt" | grep -E "(${_generic_ipv4}|${_generic_ipv6}) $tip\b" | cut -d' ' -f1 | head -n 1)"
			up="$(echo "$ipt" | grep -E "$tip (${_generic_ipv4}|${_generic_ipv6})" | cut -d' ' -f1 | head -n 1)"
			mac="$(echo "$macIP" | grep "$tip" | awk '{ print $1 }')"
			[ -z "$mac" ] && mac="$(GetMACbyIP "$tip")"
			echo "curr_users4({id:'${mac}-${ip}',down:'${do:-0}',up:'${up:-0}'})" >> $_liveFilePath
			ipt="$(echo -e "$ipt" | grep -v "$tip")" # delete all matching entries for the current IP
		fi
	done

	ddd="$(awk "$_conntrack_awk" "$_conntrack")"
	echo -e "\n/*current connections by ip:*/" >> $_liveFilePath
	err="$(echo "${ddd%,}]" 2>&1 1>> $_liveFilePath)"
	[ -n "$err" ] && Send2Log "ERROR >>> doliveUpdates: $(IndentList "$err")" 3
	$doArchiveLiveUpdates
}

loads="$(cat /proc/loadavg | cut -d' ' -f1,2,3 | tr -s ' ' ',')"
Send2Log ">>> loadavg: $loads"

echo -e "var last_update='$_ds $_ts'\nserverload($loads)" > $_liveFilePath

$doCurrConnections

LogEndOfFunction
