#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021 Ethan Dye
# All rights reserved.
#
# clears YAMon entries from iptables & ip6tables
# run: manually
# History
# 2020-01-26: 4.0.7 - no changes
# 2020-01-03: 4.0.6 - no changes
# 2019-12-23: 4.0.5 - no changes
# 2019-11-24: 4.0.4 - no changes (yet)
# 2019-06-18: development starts on initial v4 release
#
##########################################################################

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/shared.sh"

ClearTables() {
	local tables="FORWARD,INPUT,OUTPUT"
	local tt dup_num rn oe
	echo " > Clearing tables:"
	for tt in ${tables//,/ }; do
		oe="$($1 -nL "$tt" --line-numbers -w -W1 | grep "$YAMON_IPTABLES")"
		[ -z "$oe" ] && echo "   * Nothing to clear in $tt" && continue
		rn="$(echo "$oe" | awk '{ print $2 }')"
		echo "   * Deleting $rn from $tt"
		dup_num="$(echo "$oe" | awk '{ print $1 }')"
		[ -n "$rn" ] && eval $1 -D "$tt" $dup_num -w -W1
	done
}

FlushChains() {
	local ch wc chainlist
	echo -e "\n > Flushing chains in $1:"
	chainlist="$($1 -L -w -W1 | grep $YAMON_IPTABLES | grep Chain)"
	[ -z "$chainlist" ] && echo "   * Nothing to flush" && return
	IFS=$'\n'
	for ch in $chainlist; do
		wc="$(echo $ch | cut -d' ' -f2)"
		echo "   * $wc"
		$1 -F "$wc" -w -W1
	done
	unset IFS
}

DeleteChains() {
	local ch wc chainlist
	echo -e "\n > Deleting chains in $cmd:"
	chainlist="$($1 -L -w -W1 | grep $YAMON_IPTABLES | grep Chain)"
	[ -z "$chainlist" ] && echo "   * Nothing to flush" && return
	IFS=$'\n'
	for ch in $chainlist; do
		wc="$(echo $ch | cut -d' ' -f2)"
		echo "   * $wc"
		$1 -X "$wc"
	done
	unset IFS
}

[ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'
for c in ${commands//,/ }; do
	echo -e "\n*******************\nCleaning entries for $c:"
	ClearTables $c
	FlushChains $c
	DeleteChains $c
done
echo -e "\n*******************\nAll '$YAMON_IPTABLES' entries have been removed from iptables & ip6tables\n\n"
