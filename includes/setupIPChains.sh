##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021 Ethan Dye
# All rights reserved.
#
# functions to define chains in iptables & optionally ip6tables
#
# History
# 2020-03-20: 4.0.7 - added wait option ( -w -W1) to commands that add entries in iptables;
#                   - then added _iptablesWait 'cause not all firmware variants support iptables -w...
# 2020-01-03: 4.0.6 - added check for _logNoMatchingMac in SetupIPChains
# 2019-12-23: 4.0.5 - no changes
# 2019-11-24: 4.0.4 - no changes (yet)
# 2019-06-18: development starts on initial v4 release
#
# To Do:
#	* allow comma separated list of guest interfaces
#	* add ip6 addresses for interfaces
#
##########################################################################

_PRIVATE_IP4_BLOCKS='10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
_PRIVATE_IP6_BLOCKS='fc00::/7,ff02::/7'
_LOCAL_IP4='255.255.255.255,224.0.0.1,127.0.0.1'
_LOCAL_IP6=''
LOCAL="${YAMON_IPTABLES}Local"
ENTRY="${YAMON_IPTABLES}Entry"

CheckTables() {
  local commands
  local foundRuleInChain
  local cmd
  local i=1
  local dup_num
  local rule="${YAMON_IPTABLES}Entry"

  [ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'

  for cmd in ${commands//,/ }; do
    foundRuleInChain="$($cmd -nL "$1" -w -W1 | grep -ic "\b$rule\b")"

    if [ "$foundRuleInChain" -eq 1 ]; then
      Send2Log "CheckTables: '$cmd' rule $rule exists in chain $1" 1
      return
    elif [ "$foundRuleInChain" -eq 0 ]; then
      Send2Log "CheckTables: Created '$cmd' rule $rule in chain $1" 2
      eval $cmd -I "$1" -j "$rule" -w -W1
      return
    fi

    # It's unlikely you should get here... but added defensively
    Send2Log "CheckTables: Found $foundRuleInChain instances of '$cmd' $rule in chain $1... deleting entries individually rather than flushing!" 3
    while [  "$i" -le "$foundRuleInChain" ]; do
      dup_num="$($cmd -nL "$1" --line-numbers | grep -m 1 -i "\b$rule\b" | cut -d' ' -f1)"
      eval $cmd -D "$1" "$dup_num" -w -W1
      i=$(( i + 1 ))
    done
    eval $cmd -I "$1" -j "$rule" -w -W1
  done
}

AddPrivateBlocks() {
  local commands
  local ipBlocks
  local iprs
  local iprd

  [ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'
  [ -n "$ip6Enabled" ] && ipBlocks="$_PRIVATE_IP6_BLOCKS" || ipBlocks="$_PRIVATE_IP4_BLOCKS"

  for cmd in $commands; do
    $cmd -F "$YAMON_IPTABLES" -w -W1
    $cmd -F "$ENTRY" -w -W1
    $cmd -F "$LOCAL" -w -W1
    Send2Log "AddPrivateBlocks: $cmd / '$YAMON_IPTABLES' / '$ENTRY' / '$LOCAL' / $ipBlocks" 1
    for iprs in ${ipBlocks//,/ }; do
      for iprd in ${ipBlocks//,/ }; do
        if [ "$_firmware" -eq "0" ] && [ "$cmd" == 'ip6tables' ]; then
          eval $cmd -I "$ENTRY" -j "RETURN" -s $iprs -d $iprd -w -W1
          eval $cmd -I "$ENTRY" -j "$LOCAL" -s $iprs -d $iprd -w -W1
        else
          eval $cmd -I "$ENTRY" -g "$LOCAL" -s $iprs -d $iprd -w -W1
        fi
      done
    done
    eval $cmd -A "$ENTRY" -j "${YAMON_IPTABLES}" -w -W1
    eval $cmd -I "$LOCAL" -j "RETURN" -w -W1

    Send2Log "chains --> $cmd / $YAMON_IPTABLES --> $(IndentList "$($cmd -L -vx -w -W1 | grep "$YAMON_IPTABLES" | grep "Chain")")"
  done
}

AddLocalIPs() {
  local ip
  local commands
  local cmd
  local ipAddresses

  [ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'
  [ -n "$ip6Enabled" ] && ipAddresses="$_LOCAL_IP6" || ipAddresses="$_LOCAL_IP4"

  for cmd in ${commands//,/ }; do
    Send2Log "AddLocalIPs: $cmd / '$YAMON_IPTABLES' / '$ENTRY' / '$LOCAL' / $ipAddresses" 1
    for ip in ${ipAddresses//,/ }; do
      if [ "$_firmware" -eq "0" ] && [ "$cmd" == 'ip6tables' ] ; then
        eval $cmd -I "$ENTRY" -j "RETURN" -s $ip -w -W1
        eval $cmd -I "$ENTRY" -j "RETURN" -d $ip -w -W1
        eval $cmd -I "$ENTRY" -j "$LOCAL" -s $ip -w -W1
        eval $cmd -I "$ENTRY" -j "$LOCAL" -d $ip -w -W1
      else
        eval $cmd -I "$ENTRY" -g "$LOCAL" -s $ip -w -W1
        eval $cmd -I "$ENTRY" -g "$LOCAL" -d $ip -w -W1
      fi
    done
  done
}

SetupIPChains() {
  local ch
  local tbl
  local chains="${YAMON_IPTABLES},${ENTRY},${LOCAL}"
  local tables="FORWARD,INPUT,OUTPUT"

  [ -n "$ip6Enabled" ] && commands='iptables,ip6tables' || commands='iptables'
  Send2Log "SetupIPChains" 1
  for ch in ${chains//,/ }; do
    CheckChains "$ch"
  done
  AddPrivateBlocks
  AddLocalIPs
  for tbl in ${tables//,/ }; do
    CheckTables "$tbl"
  done
  AddIPTableRules
}

AddNetworkInterfaces() {
  local re_mac='([a-f0-9]{2}:){5}[a-f0-9]{2}'
  local listofInterfaces
  local interfaceList
  local inf ifc ifn
  local mac
  local inet4 inet6
  local ip iplist
  local pnd line

  Send2Log "AddNetworkInterfaces:" 1
  listofInterfaces="$(ifconfig | grep "HWaddr" | awk '{ print $1 }')"
  for inf in $listofInterfaces; do
    ifc="$(ifconfig "$inf")"
    mac="$(cat "/sys/class/net/${inf}/address")"
    [ -z "$mac" ] && continue
    if [ -z "$(echo "$mac" | grep -Ei "$re_mac")" ]; then
      Send2Log "AddNetworkInterfaces: bad mac --> $mac from $ifc" 1
      continue
    fi
    inet4="$(echo "$ifc" | grep 'inet addr' | cut -d':' -f2 | awk '{ print $1 }')"
    inet6="$(echo "$ifc" | grep 'inet6 addr'| awk '{ print $3 }')"
    [ -z "$inet4" ] && [ -z "$inet6" ] && continue
    iplist="$(echo -e "${inet4}\n${inet6}")"
    Send2Log "AddNetworkInterfaces: $inf --> $mac $(IndentList "$iplist")" 1
    for ip in $iplist; do
      [ -z "$ip" ] && continue
      CheckMAC2IPinUserJS "$mac" "$ip" "$inf"
      CheckMAC2GroupinUserJS "$mac" 'Interfaces'
      CheckIPTableEntry "$ip" "Interfaces"
    done
    interfaceList="${interfaceList},${inf}"
  done
  interfaceList="${interfaceList#,}"
  AddEntry "_interfaces" "$interfaceList"

  IFS=$'\n'
  pnd="$(cat "/proc/net/dev" | grep -E "${interfaceList//,/|}")"
  for line in $pnd; do
    ifn="$(echo "$line" | awk '{ print $1 }' | sed -e 's~-~_~' -e 's~:~~')"
    AddEntry "interface_${ifn}" "$(echo "$line" | awk '{ print $10","$2 }')"
  done
  unset IFS

  CheckMAC2IPinUserJS "$_generic_mac" "$_generic_ipv4" "No Matching Device"
  [ -n "$ip6Enabled" ] && CheckMAC2IPinUserJS "$_generic_mac" "$_generic_ipv6" "No Matching Device"
  CheckMAC2GroupinUserJS "$_generic_mac" "$_defaultGroup"
}
