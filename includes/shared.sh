##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021-2022 Ethan Dye
# All rights reserved.
#
# various utility functions (shared between one or more scripts)
#
# History
# 2020-03-19: 4.0.7 - added static leases for Tomato (thx tvlz)
#                   - added wait option ( -w -W1) to commands that add entries in iptables
#                   - then added _iptablesWait 'cause not all firmware variants support iptables -w...
#                   - combined StaticLeases_Merlin & StaticLeases_Tomato into StaticLeases_Merlin_Tomato
#                   - added GetMACbyIP & GetDeviceGroup (from traffic & check-network)
# 2020-01-03: 4.0.6 - no changes
# 2019-12-23: 4.0.5 - changed loglevel of start messages in logs
# 2019-11-24: 4.0.4 - no changes (yet)
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

_ds="$(date +"%Y-%m-%d")"
_ts="$(date +"%T")"
_generic_mac="un:kn:ow:n0:0m:ac"
_excluding='FAILED,INCOMPLETE,00:00:00:00:00:00' # excludes listed entries from the results
_reIP4="([0-9]{1,3}\.){3}[0-9]{1,3}"

source "${d_baseDir}/includes/version.sh"
source "${d_baseDir}/config.file"
source "${d_baseDir}/includes/paths.sh"
source "${d_baseDir}/strings/${_lang:-en}/strings.sh"

tmplog='/tmp/yamon/'
[ -d "$tmplog" ] || mkdir -p "$tmplog"
tmplogFile='/tmp/yamon/yamon.log'

[ -z "$showEcho" ] && exec >> $tmplogFile 2>&1 # send error messages to the log file as well!

Send2Log() {
	[ "${2:-0}" -lt "${_loglevel:-0}" ] && return
	echo -e "<section class='ll${2:-0}'><article class='dt'>$(date +"%T")</article><article class='msg'>${1}</article></section>" >> "$tmplogFile"
}

IndentList() {
	echo '<ul>'
	echo -e "$1" | grep -Ev '^\s{0,}$' | sed -E -e 's~(.*$)~<li>\1</li>~Ig'
	echo '</ul>'
}

Send2Log "${0##$d_baseDir/} - start"

SetRenice() {
	# if firmware supports renice, set the value
	Send2Log "SetRenice: renice 10 $$"
	renice 10 $$
}

NoRenice() {
	# if firmware doesn't support renice
	Send2Log "NoRenice"
	return
}

$_setRenice

LogEndOfFunction() {
	Send2Log "${0##$d_baseDir/} - end" "$1"
	sed -i -E -e 's~^ ([^<].*$)~<pre>\1</pre>~g' -e 's~(^[^<].*$)~<p class="err">\1</p>~g' "$tmplogFile"
}

AddEntry() {
	local param="${1//./_}"
	local value="$2"
	local pathsFile="${3:-${d_baseDir}/includes/paths.sh}"
	local existingValue

	existingValue="$(grep -m1 "${param}=.\{0,\}\$" "$pathsFile")"
	if [ -z "$existingValue" ]; then
		Send2Log "AddEntry: adding value --> \`${param}\`='${value}' in $pathsFile" 1
		echo "${param}='${value}'" >> "${d_baseDir}/includes/paths.sh"
	else
		Send2Log "ChangePath: changing value of \`${param}\` to $value (prior ${existingValue}) in $pathsFile" 1
		sed -i "s~^${existingValue}\$~${param}='${value}'~g" "$pathsFile"
	fi
}

ChangePath() {
	# changes a value in /includes/paths.sh
	AddEntry "$1" "$2" "$3"
}

CheckGroupChain() {
	local cmd="$1"
	local groupName="${2:-Unknown}"
	local groupChain

	Send2Log "CheckGroupChain: $cmd / $groupName"
	groupChain="${YAMON_IPTABLES}_$(echo "$groupName" | sed "s/[^a-z0-9]//ig")"
	if [ -z "$($cmd -L -w -W1 | grep '^Chain' | grep "${groupChain}\b")" ]; then
		Send2Log "CheckGroupChain: Adding group chain to iptables: $groupChain" 2
		eval $cmd -N "$groupChain" -w -W1
		eval $cmd -A "$groupChain" -j "RETURN" -w -W1
	fi
}

GetMACbyIP() {
	local ip="$1"
	local tip="\b${ip//\./\\.}\b"
	local mip
	local dd
	local id
	local mac

	# first check arp
  mip="$(grep -Ev "(${_excluding//,/|})" /proc/net/arp | grep -m1 "$tip" | awk '{ print $4 }' | tr "[A-Z]" "[a-z]")"
	if [ -n "$mip" ]; then
		echo "$mip"
		return
	fi

	# then check users.js
	dd="$(grep -e '^mac2ip({ .* })$' "$_usersFile" | grep -m1 "$tip")"
	if [ -z "$dd" ]; then
		Send2Log "GetMACbyIP - no matching entry for $ip in users.js $(IndentList "$dd")" 2
	else
		id="$(GetField "$dd" 'id')"
		mac="$(echo "$id"| cut -d'-' -f1)"
		Send2Log "GetMACbyIP - $ip --> $id --> $mac"
		[ -n "$mac" ] && echo "$mac"
	fi
}

GetDeviceGroup() {
	local mgList
	local dd
	local group

	mgList="$(grep -e '^mac2group({ .* })$' "$_usersFile")"
	dd="$(echo "$mgList" | grep "$1")"
	if [ -z "$dd" ]; then
		Send2Log "GetDeviceGroup - no matching entry for $1 in users.js... set to '${_defaultGroup:-Unknown}'" 2
		echo "${_defaultGroup:-Unknown}"
		return
	fi
	group="$(GetField "$dd" 'group')"

	Send2Log "GetDeviceGroup - $1 / $2 --> $dd --> $group"
	echo "$group"
}

AddIPTableRules() {
	local commands
	local cmd

	DeleteIPTableRule() {
		local ruleName="$1"
		local cmd
		local nl="0"
		local ln

		for cmd in ${commands//,/ }; do
			while true; do
				ln="$($cmd -L "$YAMON_IPTABLES" -n --line-numbers | grep -m1 "$ruleName" | awk '{ print $1 }')"
				[ -z $ln ] && break
				eval $cmd -D "$YAMON_IPTABLES" "$ln" -w -W1
				nl="$(( nl + 1 ))"
			done
			Send2Log "DeleteIPTableRule: deleted $nl $ruleName rules from ${cmd}: $YAMON_IPTABLES" 2
		done
	}

	[ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'

	DeleteIPTableRule LOG
	DeleteIPTableRule RETURN

	for cmd in ${commands//,/ }; do
		if [ "$_logNoMatchingMac" -eq "1" ]; then
			eval $cmd -A "$YAMON_IPTABLES" -j LOG --log-prefix "YAMon: " -w -W1
			Send2Log "AddIPTableRules: added LOG rule in ${cmd}: $YAMON_IPTABLES" 2
		else
			eval $cmd -A "$YAMON_IPTABLES" -j RETURN -w -W1
			Send2Log "AddIPTableRules: added RETURN rule in ${cmd}: $YAMON_IPTABLES" 2
		fi
	done
}

RemoveMatchingRules() {
	local ip="$1"
	local tip="\b${ip//\./\\.}\b"
	local n=0
	local matchingRule cmd

	if [ -n "$(echo "$ip" | grep -E "$_reIP4")" ]; then
		cmd='iptables'
	else
		[ -z "$ip6Enabled" ] && return
		cmd='ip6tables'
	fi

	while true; do
		[ -z "$ip" ] && break
		matchingRule="$($cmd -L "$YAMON_IPTABLES" -n --line-numbers -w -W1 | grep -m1 -i "$tip" | cut -d' ' -f1)"
		[ -z "$matchingRule" ] && break
		eval $cmd -D "$YAMON_IPTABLES" "$matchingRule" -w -W1
		n=$(( n + 1 ))
	done
	Send2Log "RemoveMatchingRules: removed $n entries for $ip" 2
}

CheckIPTableEntry() {
	local ip="$1"
	local tip="\b${ip//\./\\.}\b"
	local groupName="${2:-Unknown}"
	local cmd
	local g_ip
	local nm

	AddIP() {
		local groupChain

		groupChain="${YAMON_IPTABLES}_$(echo $groupName | sed "s~[^a-z0-9]~~ig")"
		Send2Log "AddIP: $cmd $YAMON_IPTABLES $ip --> $groupChain (firmware: $_firmware)"
		if [ "$_firmware" -eq "0" ] && [ "$cmd" == 'ip6tables' ] ; then
			eval $cmd -I "$YAMON_IPTABLES" -j "RETURN" -s $ip -w -W1
			eval $cmd -I "$YAMON_IPTABLES" -j "RETURN" -d $ip -w -W1
			eval $cmd -I "$YAMON_IPTABLES" -j "$groupChain" -s $ip -w -W1
			eval $cmd -I "$YAMON_IPTABLES" -j "$groupChain" -d $ip -w -W1
		else
			eval $cmd -I "$YAMON_IPTABLES" -g "$groupChain" -s $ip -w -W1
			eval $cmd -I "$YAMON_IPTABLES" -g "$groupChain" -d $ip -w -W1
			Send2Log "AddIP: $cmd -I \"$YAMON_IPTABLES\" -g \"$groupChain\" -s $ip"
		fi
	}

	if [ -n "$(echo $ip | grep -E "$_reIP4")" ]; then
		cmd='iptables'
		g_ip="$_generic_ipv4"
	else
		[ -z "$ip6Enabled" ] && return
		cmd='ip6tables'
		g_ip="$_generic_ipv6"
	fi
	Send2Log "CheckIPTableEntry: $ip / $groupName"
	Send2Log "CheckIPTableEntry: ip=$ip / cmd=$cmd / chain=$YAMON_IPTABLES"
	Send2Log "CheckIPTableEntry: checking $cmd for $ip"

	[ "$ip" == "$g_ip" ] && return
	nm="$($cmd -L "$YAMON_IPTABLES" -n -w -W1 | grep -ic "$tip")"

	if [ "$nm" -eq "2" ] || [ "$nm" -eq "4" ]; then  # correct number of entries
		Send2Log "CheckIPTableEntry: $nm matches for $ip in $cmd / $YAMON_IPTABLES"
		return
	fi

	CheckGroupChain "$cmd" "$groupName"

	if [ "$nm" -eq "0" ]; then
		Send2Log "CheckIPTableEntry: no match for $ip in $cmd / $YAMON_IPTABLES"
	else
		Send2Log "CheckIPTableEntry: Incorrect number of rules for $ip in $cmd / $YAMON_IPTABLES -> ${nm}... removing duplicates" 3
		RemoveMatchingRules "$ip"
	fi
	AddIP
}

UpdateLastSeen() {
	local id="$1"
	local tls="$2"
	local lsd="$_ds $tls"
	local line

	Send2Log "UpdateLastSeen: Updating last seen for '${id}' to '${lsd}'"
	echo -e "lastseen({ \"id\":\"${id}\", \"last-seen\":\"${lsd}\" })\n$(grep -v -e "^lastseen({ \"id\":\"${id}\".* })\$" "$tmpLastSeen")" > "$tmpLastSeen"
	line="$(grep -e "^mac2ip({ \"id\":\"${id}\".* })\$" "$_usersFile" | grep -m1 '"active":"0"')"
	[ -z "$line" ] && return
	sed -i "s~${line}~$(UpdateField "$line" 'active' '1')~" "$_usersFile"
	Send2Log "UpdateLastSeen: $id set to active" 1
	UsersJSUpdated
}

GetField() {	#returns just the first match... duplicates are ignored
	local result

	result="$(echo "$1" | grep -io -m1 "${2}\":\"[^\"]\{1,\}" | cut -d'"' -f3)"
	echo "$result"
	[ -n "$result" ] && Send2Log "GetField: ${2}='${result}' in \`${1}\`" && return
	[ -z "$result" ] && [ -z "$1" ] && Send2Log "GetField: field '${2}' not found because the search string was empty (\`${1}\`)" && return
	[ -z "$result" ] && Send2Log "GetField: field '${2}' not found in \`${1}\`" 1
}

UsersJSUpdated() {
	Send2Log "UsersJSUpdated: users_updated changed to '${_ds} ${_ts}'" 2
	sed -i "s~users_updated=\"[^\"]\{0,\}\"~users_updated=\"${_ds} ${_ts}\"~" "$_usersFile"
}

UpdateField() {
	local cl="$1" # current line of text
	local wf="$2" # which field to update
	local nv="$3" # new value
	local result

  result="$(echo "$cl" | sed -e "s~\"${wf}\":\"[^\"]\{0,\}\"~\"${wf}\":\"${nv}\"~" -e "s~\"updated\":\"[^\"]\{0,\}\"~\"updated\":\"${_ds} ${_ts}\"~")"
	[ -z "$result" ] && Send2Log "UpdateField: replacement of $wf failed" 2
	echo "$result"
}

GetDeviceName() {
	local mac="$1"
	local dn
	local big
	local nextnum

	NullFunction() { # do nothing
		echo
	}
	DNSMasqConf() {
		local mac="$1"
		local result

		result="$(grep -i "dhcp-host=" "$_dnsmasq_conf" | grep -i "$mac" | cut -d',' -f"$deviceNameField")"
		Send2Log "DNSMasqConf: result=$result"
		echo "$result"
	}
	DNSMasqLease() {
		local result

		[ -f "$_dnsmasq_leases" ] && result="$(grep -i "$1" "$_dnsmasq_leases" | tr '\n' ' / ' | cut -d' ' -f4)"
		Send2Log "DNSMasqLease: result=$result"
		echo "$result"
	}
	StaticLeases_DDWRT() {
		local mac="$1"
		local nvr
		local result

		nvr="$(nvram show 2>&1 | grep -i "static_leases=")"
		result="$(echo "$nvr" | grep -io "${mac}[^=]*=.\{1,\}=.\{1,\}=" | cut -d'=' -f2)"
		Send2Log "StaticLeases_DDWRT: result=$result"
		echo "$result"
	}
	StaticLeases_OpenWRT() { # thanks to Robert Micsutka for providing this code & easywinclan for suggesting & testing improvements!
		local mac="$1"
		local result
		local ucihostid

		ucihostid="$(uci show dhcp | grep -i "$mac" | cut -d'.' -f2)"
		[ -n "$ucihostid" ] && result="$(uci get "dhcp.${ucihostid}.name")"
		Send2Log "StaticLeases_OpenWRT: result=$result"
		echo "$result"
	}
	StaticLeases_Merlin_Tomato() { #thanks to Chris Dougherty for providing Merlin code, and to Tvlz for providing Tomato Nvram settings
		local mac="$1"
		local dhcp_str
		local nvr
		local nvrt
		local nvrfix
		local iter
		local result

		if [ "$_firmware" -eq "3" ]; then
			dhcp_str='dhcpd_static'
		else
			dhcp_str='dhcp_staticlist'
		fi
		nvr="$(nvram show 2>&1 | grep -i "${dhcp_str}=")"
		nvrt="$nvr"
		while [ "$nvrt" ]; do
			iter="${nvrt%%<*}"
			nvrfix="${nvrfix}${iter}="
			[ "$nvrt" == "$iter" ] && nvrt='' || nvrt="${nvrt#*<}"
		done
		nvr="${nvrfix//>/=}"
		result=$(echo "$nvr" | grep -io "${mac}[^=]*=.\{1,\}=.\{1,\}=" | cut -d'=' -f3)
		Send2Log "StaticLeases_Merlin_Tomato: result=$result"
		echo "$result"
	}

	Send2Log "GetDeviceName: $mac $2"

	# check first in static leases
	dn="$($nameFromStaticLeases "$mac")"
	if [ -n "${dn/$/}" ]; then
		Send2Log "GetDeviceName: found device name $dn for $mac in static leases (${nameFromStaticLeases})"
		echo "$dn"
		return
	fi
	Send2Log "GetDeviceName: No device name for $mac in static leases (${nameFromStaticLeases})"

	# then in DNSMasqConf
	dn="$($nameFromDNSMasqConf "$mac")"
	if [ -n "${dn/$/}" ]; then
		Send2Log "GetDeviceName: found device name $dn for $mac in $_dnsmasq_conf"
		echo "$dn"
		return
	fi
	Send2Log "GetDeviceName: No device name for $mac in in $_dnsmasq_conf (${nameFromDNSMasqConf})"

	# finally in DNSMasqLease
	dn="$($nameFromDNSMasqLease "$mac")"
	if [ -n "${dn/$/}" ]; then
		Send2Log "GetDeviceName: found device name $dn for $mac in $_dnsmasq_leases"
		echo "$dn"
		return
	fi
	Send2Log "GetDeviceName: No device name for $mac in in $_dnsmasq_leases (${nameFromDNSMasqLease})"

	# Dang... no matches
	big="$(grep -e '^mac2ip({ .* })$' "$_usersFile" | grep -o "\"${_defaultDeviceName}-[^\"]\{0,\}\"" | sort | tail -1 | tr -d '"' | cut -d'-' -f2)"
	nextnum="$(printf %02d $(( $(echo "${big#0} ") + 1 )))"
	echo "${_defaultDeviceName}-${nextnum}"
	Send2Log "GetDeviceName: did not find name for ${mac}... defaulting to ${_defaultDeviceName}-${nextnum}"
}

CheckChains() {
	local chain="$1"
	local commands
	local ipChain
	local cmd

	[ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'
	for cmd in ${commands//,/ }; do
		ipChain="$($cmd -L -w -W1 | grep "Chain $YAMON_IPTABLES" | grep "\b${chain}\b")"
		if [ -z "$ipChain" ]; then
			Send2Log "CheckChains: Adding $chain in $cmd" 2
			eval $cmd -N "$chain" -w -W1
		else
			Send2Log "CheckChains: $chain exists in $cmd" 1
		fi
	done
}

CheckMAC2GroupinUserJS() {
	local m="$1"
	local gn="${2:-${_defaultGroup:-Unknown}}"
	local matchesMACGroup
	local cgn

	ChangeMACGroup() {
		local newLine
		local groupChain
		local matchingMACs
		local matchingRules
		local rule ip id ln i cmd

		Send2Log "ChangeMACGroup: group names do not match! $gn != $cgn" 2
		newLine="$(UpdateField "$matchesMACGroup" 'group' "$gn")"
		groupChain="${YAMON_IPTABLES}_$(echo "$gn" | sed "s~[^a-z0-9]~~ig")"
		sed -i "s~${matchesMACGroup}~${newLine}~" "$_usersFile"
		#To do - change entries in ip[6]tables
		# iptables -E YAMONv40_Interfaces2 YAMONv40_Interfaces
		matchingMACs="$(grep "^mac2ip({ \"id\":\"$(GetField "$matchesMACGroup" 'mac').* })\$" "$_usersFile")"
		IFS=$'\n'
		for line in $matchingMACs; do
			[ -z "$line" ] && continue
			id="$(GetField $line 'id')"
			[ -z "$id" ] && continue
			ip="$(echo "$id" | cut -d'-' -f2)"

			if [ -n "$(echo $ip | grep -E "$_reIP4")" ]; then # simplistically matches IPv4
				cmd='iptables'
			else
				[ -n "$ip6Enabled" ] || cmd='iptables'
				cmd='ip6tables'
			fi
			Send2Log "ChangeMACGroup: changing chain destination for $ip in $cmd ($gn)" 2

			matchingRules="$($cmd -L "$YAMON_IPTABLES" -n --line-numbers -w -W1 | grep "\b${ip//\./\\.}\b")"
			for rule in $matchingRules; do
				[ -z "$rule" ] && continue
				ln="$(echo "$rule" | awk '{ print $1 }')"
				i="$(echo "$rule" | awk '{ print $5 }')"
				CheckChains "$groupChain"
				if [ "$i" != "$_generic_ipv4" ]; then
					eval $cmd -R "$YAMON_IPTABLES" "$ln" -s "$i" -j "$groupChain" -w -W1
				else
					i="$(echo "$rule" | awk '{ print $6 }')"
					eval $cmd -R "$YAMON_IPTABLES" "$ln" -d "$i" -j "$groupChain" -w -W1
				fi
				Send2Log "ChangeMACGroup: changing destination of $rule to $gn" 2
			done
		done
		UsersJSUpdated
	}
	AddNewMACGroup(){
		local newentry="mac2group({ \"mac\":\"${m}\", \"group\":\"${gn}\" })"

		Send2Log "AddNewMACGroup: adding mac2group entry for $m & $gn" 2
		sed -i "s~// MAC -> Groups~// MAC -> Groups\n${newentry}~g" "$_usersFile"
		UsersJSUpdated
	}

	Send2Log "CheckMAC2GroupinUserJS: $m $gn" 2
	matchesMACGroup="$(grep -e "^mac2group({ \"mac\":\"${m}\".* })\$" "$_usersFile")"

	if [ -z "$matchesMACGroup" ]; then
		AddNewMACGroup
	elif [ "$(echo $matchesMACGroup | wc -l)" -eq 1 ] ; then
		cgn="$(GetField "$matchesMACGroup" 'group')"
		[ "$gn" == "$cgn" ] || ChangeMACGroup
	else
		Send2Log "CheckDeviceInUserJS: uh-oh... *${matchesMACGroup}* mac2group matches for '${m}' in '${_usersFile}' --> $(IndentList "$(grep -e "^mac2group({ \"mac\":\"${m}\".* })\$" "$_usersFile")")" 2
	fi
}

CheckMAC2IPinUserJS() {
	local m="$1"
	local i="$2"
	local dn="$3"
	local matchesMACIP

	DeactivateByIP() {
		local othersWithIP
		local od
		local nl

		Send2Log "DeactivateByIP: $i"
		othersWithIP="$(grep -e '^mac2ip({ .* })$' "$_usersFile" | grep "\b${i//\./\\.}\b" | grep '"active":"1"')"
		if [ -z "$othersWithIP" ]; then
			Send2Log "DeactivateByIP: no active duplicates of $i in $_usersFile"
			return
		fi
		Send2Log "DeactivateByIP: $(echo "$othersWithIP" | wc -l) active duplicates of $i in $_usersFile"
		IFS=$'\n'
		for od in $othersWithIP; do
			Send2Log "DeactivateByIP: set active=0 in $od"
			sed -i "s~${od}~$(UpdateField "$od" 'active' '0')~g" "$_usersFile"
			UsersJSUpdated
		done
		unset IFS
	}
	AddNewMACIP() {
		local othersWithMAC
		local ndn

		Send2Log "AddNewMACIP: mac=$m ip=$i device-name=$dn"
		DeactivateByIP
		[ -z "$dn" ] && othersWithMAC="$(grep -e '^mac2ip({ .* })$' "$_usersFile" | grep -m1 "$m")" # NB - specifically looks for just one match
		if [ -n "$othersWithMAC" ]; then
			dn="$(GetField "$othersWithMAC" 'name')"
			Send2Log "AddNewMACIP: copying device name '$dn' from $othersWithMAC"
			if [ -n "$(echo "$dn" | grep "$_defaultDeviceName")" ]; then
				ndn="$(GetDeviceName "$m" "$i")"
				[ -z "$(echo "$ndn" | grep "$_defaultDeviceName")" ] && dn="$ndn"
			fi
		elif [ -z "$dn" ]; then
			dn="$(GetDeviceName "$m" "$i")"
		fi
		local newentry="mac2ip({ \"id\":\"${m}-${i}\", \"name\":\"${dn:-New Device}\", \"active\":\"1\", \"added\":\"${_ds} ${_ts}\", \"updated\":\"\" })"
		Send2Log "AddNewMACIP: adding $newentry to $_usersFile"
		sed -i "s~// MAC -> IP~// MAC -> IP\n${newentry}~g" "$_usersFile"
		UpdateLastSeen "$m-$i" "$(date +"%T")"
		UsersJSUpdated
	}

	Send2Log "CheckMAC2IPinUserJS: mac=$m ip=$i"
	matchesMACIP="$(grep -e "^mac2ip({ \"id\":\"${m}-${i}\".* })\$" "$_usersFile")"
	if [ -z "$matchesMACIP" ]; then
		AddNewMACIP
	elif [ "$(echo "$matchesMACIP" | wc -l)" -eq 1 ] ; then
		Send2Log "CheckMAC2IPinUserJS: found a unique match for ${m}-${i}"
		[ -z "$dn" ] && return
		# TODO: check that the name matches
	else
		Send2Log "CheckMAC2IPinUserJS: uh-oh... *$(echo "$matchesMACIP" | wc -l)* matches for '${m}-${i}' in '$_usersFile' --> $(IndentList "$(echo "$matchesMACIP")")" 2
	fi
}

AddActiveDevices() {
	local _ActiveIPs
	local _MACGroups
	local currentMacIP
	local device
	local id
	local ip
	local mac
	local group

	Send2Log "AddActiveDevices"
	_ActiveIPs="$(grep -e '^mac2ip({ .* })$' "$_usersFile" | grep '"active":"1"')"
	_MACGroups="$(grep -e '^mac2group({ .* })$' "$_usersFile")"
	IFS=$'\n'
	for device in $_ActiveIPs; do
		currentMacIP="$(cat "$macIPFile")"
		id="$(GetField "$device" 'id')"
		ip="$(echo "$id" | cut -d'-' -f2)"
		[ -z "$ip" ] && Send2Log "AddActiveDevices --> IP is null --> $device" && continue
		[ "$_generic_ipv4" == "$ip" ] || [ "$_generic_ipv6" == "$ip" ] && continue
		mac="$(echo "$id" | cut -d'-' -f1)"
		group="$(GetField "$(echo "$_MACGroups" | grep -i "\"$mac\"")" 'group')"

		Send2Log "AddActiveDevices --> $id / $mac / $ip / ${group:-Unknown} "
		if [ -z "$(echo "$currentMacIP" | grep "${ip//\./\\.}$")" ]; then
			Send2Log "AddActiveDevices --> IP $ip does not exist in ${macIPFile}... added to the list"
		else
			Send2Log "AddActiveDevices --> IP $ip exists in ${macIPFile}... deleted entries $(IndentList "$(echo "$currentMacIP" | grep "${ip//\./\\.}\$")")" 2
			echo "$currentMacIP" | grep -v "${ip//\./\\.}\$" > "$macIPFile"
		fi
		Send2Log "AddActiveDevices --> $id added to $macIPFile" 1
		echo "$mac $ip" >> "$macIPFile"

		CheckIPTableEntry "$ip" "${group:-Unknown}"
	done
	unset IFS
	Send2Log "AddActiveDevices --> $(IndentList "$(cat "$macIPFile")")"
}

DigitAdd() {
	local n1=${1:-0}
	local n2=${2:-0}
	local l1=${#n1}
	local l2=${#n2}
	local carry=0
	local d1
	local d2
	local s
	local total
	if [ "$l1" -lt "${_max_digits:-12}" ] && [ "$l2" -lt "${_max_digits:-12}" ]; then
		echo $(( n1 + n2 ))
		return
	fi

	while [ $l1 -gt 0 ] || [ $l2 -gt 0 ]; do
		d1=0
		d2=0
		l1=$(( l1 - 1 ))
		l2=$(( l2 - 1 ))
		[ $l1 -ge 0 ] && d1=${n1:$l1:1}
		[ $l2 -ge 0 ] && d2=${n2:$l2:1}
		s=$(( d1 + d2 + carry ))
		sum=$(( s % 10 ))
		carry=$(( s / 10 ))
		total="${sum}${total}"
	done
	[ $carry -eq 1 ] && total="${carry}${total}"
	echo "${total:-0}"
	Send2Log "DigitAdd: $1 + $2 = $total"
}

DigitSub() {
	local n1
	local n2
	n1="$(echo "${1:-0}" | sed 's/-*//')"
	n2="$(echo "${2:-0}" | sed 's/-*//')"
	if [ $n1 == $n2 ]; then
		echo 0
		return
	fi
	local l1=${#n1}
	local l2=${#n2}
	local b=0
	local d1
	local d2
	local d
	local total
	if [ "$l1" -lt "${_max_digits:-12}" ] && [ "$l2" -lt "${_max_digits:-12}" ]; then
		echo $(( n1 - n2 ))
		return
	fi

	while [ $l1 -gt 0 ] || [ $l2 -gt 0 ]; do
		d1=0
		d2=0
		l1=$(( l1 - 1 ))
		l2=$(( l2 - 1 ))
		[ $l1 -ge 0 ] && d1=${n1:$l1:1}
		[ $l2 -ge 0 ] && d2=${n2:$l2:1}
		[ "$d2" == "-" ] && d2=0
		d1=$(( d1 - b ))
		b=0
		[ $d2 -gt $d1 ] && b=1
		d=$(( d1 + b * 10 - d2 ))
		total="${d}${total}"
	done
	[ $b -eq 1 ] && total="-${total}"
	echo "$(echo "$total" | sed 's/0*//')"
	Send2Log "DigitSub: $1 - $2 = $(echo "$total" | sed 's/0*//')"
}

CheckIntervalFiles() {
	[ -f "$_intervalDataFile" ] && Send2Log "CheckIntervalFiles: interval file exists --> $_intervalDataFile" 1 && return
	if [ ! -d "$_path2CurrentMonth" ]; then
		mkdir -p "$_path2CurrentMonth"
		Send2Log "CheckIntervalFiles: create directory --> $_path2CurrentMonth" 1
	fi
	Send2Log "CheckIntervalFiles: create interval file --> $_intervalDataFile" 1
	echo -e "var monthly_created=\"${_ds} ${_ts}\"\nvar monthly_updated=\"${_ds} ${_ts}\"\nvar monthlyDataCap=\"${_monthlyDataCap}\"\n" >> $_intervalDataFile
}
