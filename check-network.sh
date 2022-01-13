#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021-2022 Ethan Dye
# All rights reserved.
#
# checks arp & ip for new devices and/or ip changes on the network
# run: by cron
# History
# 2020-01-26: 4.0.7 - added check for error in Check4UpdatesInReports results
#                   - moved GetDeviceGroup to shared.sh
# 2020-01-03: 4.0.6 - only check dmesg if _logNoMatchingMac==1
# 2019-12-23: 4.0.5 - no changes (yet)
# 2019-11-24: 4.0.4 - added Check4UpdatesInReports to sync group names with reports
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/shared.sh"
source "${d_baseDir}/includes/start-stop.sh"

Send2Log "Checking the network for new devices" 1

arpResults="$(cat /proc/net/arp | grep "^[1-9]" | tr "[A-Z]" "[a-z]")"
arpList="$(echo "$arpResults" | grep -Ev "(${_excluding//,/|})" | awk '{ print $4,$1 }')"
#[ -n "$arpList" ] && Send2Log "Check4NewDevices: arpList: $(IndentList "$arpList")"
# echo -e "$(cat /proc/net/arp | grep "^[1-9]" | tr "[A-Z]" "[a-z]" | grep -Ev "(${_excluding//,/|})" | awk '{ print $4,$1 }')\n$(ip neigh show | tr "[A-Z]" "[a-z]" | grep -Ev "(${_excluding//,/|})" | awk '{ print $5,$1 }')" | sort -u
ipResults="$($_IPCmd | tr "[A-Z]" "[a-z]")" # a hack for firmware variants which do not include the full ip command (so `ip neigh show` does not return valid info)
ipList="$(echo "$ipResults" | grep -Ev "(${_excluding//,/|})" | awk '{ print $5,$1 }')"
#[ -n "$ipList" ] && Send2Log "Check4NewDevices: ipList: $(IndentList "$ipList")"


Check4NewDevices() {
	local macIPList
	local currentIPList
	local combinedIPArp
	local newIPList
	local dmsg
	local nip
	local nd
	local mac
	local re_mac='([a-f0-9]{2}:){5}[a-f0-9]{2}'
	local groupName
	local line
	local m
	local i
	local rm

	FindRefMAC() {
		local fm
		local nm
		local rm

		Send2Log "FindRefMAC: $i $m"
		fm="$(echo "$macIPList" | grep "\b${i//\./\\.}\b")"
		nm="$(echo "$fm" | wc -l)"
		[ -z "$fm" ] && nm=0
		if [ "$nm" -eq "1" ] ; then
			rm="$(echo "$fm" | cut -d' ' -f1)"
			Send2Log "FindRefMAC: MAC changed from $m to $rm" 1
			echo "$rm"
			return
		elif [ "$nm" -eq "0" ] ; then
			Send2Log "FindRefMAC: no matching entry for $i in ${macIPFile}... checking $tmpLastSeen" 1
			[ -f "$tmpLastSeen" ] && fm="$(cat "$tmpLastSeen" | grep -e "^lastseen({.*})$" | grep "\b${i//\./\\.}\b" | grep -v "$_generic_mac")"
			[ -z "$fm" ] && nm=0 || nm="$(echo "$fm" | wc -l)"
			if [ "$nm" -eq "1" ]; then
				rm=$(echo "$(GetField "$fm" 'id')" | cut -d'-' -f1)
				Send2Log "FindRefMAC: MAC changed from $m to $rm in $tmpLastSeen" 1
				echo "$rm"
				return
			fi
		fi

		Send2Log "FindRefMAC: $nm matching entries for $i / $m in $macIPFile & $tmpLastSeen... replaced $m with $_generic_mac" 2
		echo "$_generic_mac"

		echo -e "$_ts: $nd\n\tIP: $(echo "$arpResults" | grep "\b$i\b") \n\tarp: $(echo "$ipResults" | grep "\b$i\b" )" >> "${tmplog}bad-mac.txt"
	}

	macIPList="$(cat "$macIPFile" | grep -Ev '^\s{0,}$')"

	#Send2Log "Check4NewDevices: starting macIPList--> $(IndentList "$macIPList")"
	currentIPList="$macIPList"
	combinedIPArp="$(echo -e "${ipList}\n${arpList}" | grep -Ev '^\s{0,}$' | sort -u)"
	newIPList="$(echo "$combinedIPArp" | grep -Ev "$(echo "$currentIPList")")"
	[ -z "$currentIPList" ] && newIPList="$combinedIPArp"

	#Send2Log "Check4NewDevices: currentIPList: $(IndentList "$currentIPList")"

	# add the YAMon entries of dmesg into the logs to see where the unmatched data is coming from (and then clear dmesg)
	[ "${_logNoMatchingMac:-0}" -eq "1" ] && dmsg="$(dmesg -c | grep "YAMon")"
	if [ -z "$newIPList" ]; then
		Send2Log "Check4NewDevices: no new devices... checking that all IP addresses exist in iptables"
		unmatchedIPs="$(echo "$combinedIPArp" | awk '{ print $2 }' | grep -Ev "$(iptables -L "$YAMON_IPTABLES" -vnx -w -W1 | awk '{ print $8 }' | grep '^[1-9]' | grep -v '0.0.0.0/0' | sort)")"
		for nip in $unmatchedIPs; do
			mac="$(GetMACbyIP "$nip")"
			groupName="$(GetDeviceGroup "$mac" "$nip")"
			Send2Log "Check4NewDevices: $nip ($mac / $groupName) is missing in iptables" 2
			CheckIPTableEntry "$nip" "$groupName"
		done

		if [ -n "$dmsg" ]; then
			Send2Log "Check4NewDevices: Found YAMon entries in dmesg" 2
			IFS=$'\n'
			for line in $dmsg; do
				# TODO: parse lines for MAC & IP
				Send2Log "Check4NewDevices: dmesg --> $line" 2
			done
			unset IFS
		fi
	else
		#Send2Log "Check4NewDevices: found new IPs: $(IndentList "$newIPList")" 1
		IFS=$'\n'
		for nd in $newIPList; do
			[ -z "$nd" ] && return
			m="$(echo "$nd" | cut -d' ' -f1)"
			i="$(echo "$nd" | cut -d' ' -f2)"
			Send2Log "Check4NewDevices: new device --> ip=${i}; mac=${m}" 1
			if [ -z "$(echo "$m" | grep -Ei "$re_mac")" ]; then
				Send2Log "Check4NewDevices: Bad MAC --> $(IndentList "$(echo -e "IP: $(echo "$ipResults" | grep "\b${i}\b")\nARP: $(echo "$arpResults" | grep "\b${i}\b")")")" 2
				rm="$(FindRefMAC)"
				newIPList="$(echo "$newIPList" | sed -e "s~${nd}~${rm} ${i}~g" | grep -Ev "$currentIPList")"
				m="$rm"
			fi
			CheckMAC2IPinUserJS "$m" "$i"
			groupName="$(GetDeviceGroup "$m" "$i")"
			CheckMAC2GroupinUserJS "$m" "$groupName"
			CheckIPTableEntry "$i" "$groupName"
			macIPList="$(echo "$macIPList" | grep -v "\b${i//\./\\.}\b")"
		done
		unset IFS

		[ -z "$newIPList" ] && return
		Send2Log "Check4NewDevices: the following new devices were found: $(IndentList "$newIPList")" 1
		echo -e "$macIPList\n$newIPList" | grep -Ev '^\s{0,}$' > "$macIPFile"
	fi
}

CheckMacIP4Duplicates() {
	local macIPList
	local dups
	local combinedIPArp
	local ip
	local activeID
	local line

	macIPList="$(cat "$macIPFile")"
	dups="$(echo -e "$macIPList" | awk '{ print $2 }' | awk ' { tot[$0]++ } END { for (i in tot) if (tot[i]>1) print tot[i],i } ')"
	combinedIPArp="$(echo -e "${ipList}\n${arpList}" | grep -Ev '^\s{0,}$' | sort -u)"
	[ -z "$dups" ] && Send2Log "CheckMacIP4Duplicates: no duplicate entries in $macIPFile" 1 && return
	IFS=$'\n'
	for line in $dups; do
		ip="$(echo "$line" | awk '{ print $2 }')"
		Send2Log "CheckMacIP4Duplicates: $ip has duplicate entries in $macIPFile" 2
		macIPList="$(echo "$macIPList" | grep -v "${ip//\./\\.}")"
		activeID="$(echo "$combinedIPArp" | grep "${ip//\./\\.}")"
		if [ -n "$activeID" ]; then
			Send2Log "CheckMacIP4Duplicates: re-added activeID \`$activeID\`" 2
			macIPList="$macIPList\n$activeID"
		else
			Send2Log "CheckMacIP4Duplicates: no active matches for \`$ip\` in arp & ip lists" 2
		fi
	done
	unset IFS
	echo -e "$macIPList" > "$macIPFile"
}

Check4UpdatesInReports(){
	Send2Log "Check4UpdatesInReports: "
	local url="www.usage-monitoring.com/current/Check4UpdatesInReports.php?db=$_dbkey"
	local dst="$tmplog/updates.txt"
	local prototol='http://'
	local security_protocol=''
	wget "$prototol$url" $security_protocol -qO "$dst"
	IFS=$';'
	local updates=$(cat $dst | sed -e "s~[{}]~~g")
	[ -z "$updates" ] && Send2Log "Check4UpdatesInReports: No updates from the reports" 2
	for entry in $updates ; do
		[ -z "$entry" ] && continue
		if [ -n "$(echo "$entry" | grep "^Error")" ] ; then
			Send2Log "Check4UpdatesInReports: Error in download --> $entry" 1
		else
			local mac=$(echo $entry | cut -d',' -f1)
			local group=$(echo $entry | cut -d',' -f2)
			Send2Log "Check4UpdatesInReports: mac->$mac & group -> $group" 2
			Send2Log "Check4UpdatesInReports: checking $mac / $group" 1
			CheckMAC2GroupinUserJS $mac $group
		fi
	done
}

if [ -n "$_dbkey" ]; then
	Check4UpdatesInReports
	SetAccessRestrictions
fi

Check4NewDevices

CheckMacIP4Duplicates

LogEndOfFunction
