#!/bin/sh

##########################################################################
# Yet Another Monitor (YAMon)
# Copyright (c) 2013-2020 Al Caughey
# Copyright (c) 2021-2022 Ethan Dye
# All rights reserved.
#
# appends current contents of tmplogFile to dailyLogFile
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

Send2Log "Manually copying temp log to permanent" 2

cat "$tmplogFile" | sed -E -e 's~^ ([^<].*$)~<pre>\1</pre>~g' -e 's~(^[^<].*$)~<p class="err">\1</p>~g' >> "$dailyLogFile"
true > "$tmplogFile"
