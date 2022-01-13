##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021-2022 Ethan Dye
# All rights reserved.
#
# History
# 2021-11-23: 4.0.8 - added helpers.sh to contain more generic universal functions
#
##########################################################################

checkOverflow() {
	local n=1
	local a=9
	local b=9
	local ob=0
	local c

	while true; do
		c=$(( a + b ))
		[ $c -lt $a ] || [ $c -lt $b ] && break # check for sum overflow
		ob=$b
		a=$(( a * 10 + 1 ))
		b=$(( b * 10 + 9 ))
		[ $b -lt $ob ] && break # check for value overflow
		[ $n -eq 32 ] && break # check for max digits
		n=$(( n + 1 ))
	done
	echo $n
}
