#!/bin/bash
#set -x
if [ $# -gt 0 ]; then
  NAME=$1
else
  NAME=`basename $PWD`
fi
DATE=`cat global.time | grep start | cut -d ' ' -f 2`
START="`cat global.time | grep start | cut -d ' ' -f 3`"
END=`cat global.time | grep end | cut -d ' ' -f 3`
TICS=`echo $END | cut -d ':' -f 1`
TICS=`expr $TICS + 1`

# ToDo: these should be taken from Trinity commandline
if [ $# -gt 1 ]; then
  NCPU=$2
#  MAXRAM=$3
else
  NCPU=64
#  MAXRAM=100
fi


echo "#generated gnuplot file" >defs.gnu
echo "set xrange ['$DATE $START':'$DATE $END']" >>defs.gnu
echo -n "set xtics (" >>defs.gnu
INT=0
while [ $INT -lt $((TICS-1)) ]; 
do
  printf "\"${INT}\" \'$DATE %02d:00:00\', " $INT >>defs.gnu 
  ((INT++))
done
printf "\"${INT}\" \'$DATE %02d:00:00\' )\n" $INT >>defs.gnu
#echo "set out \'plot_${NAME}.eps\'" >>defs.gnu
echo "ncpu=$NCPU" >>defs.gnu
#echo "cpu_ytics=4" >>defs.gnu
#echo "maxram=$MAXRAM" >>defs.gnu
#echo "ram_ytics=4" >>defs.gnu
echo "" >>defs.gnu



echo "
set terminal postscript color eps \"Times\" 14 
#set termoption enhanced

set style data points

# ram and cpu
mypt1=7
mylw1=0
#myps1=0.3
myps1=0.6

set key below
set timefmt \"%Y%m%d %H:%M:%S\"
set xdata time
set format x \"%k\"
set xrange [*:*]
unset grid
set grid x
unset title
#set title \"${NAME}\" noenhanced
set title \"${NAME}\"

fm=1./(1024.0)
fg=1./(1024.0)/(1024.0)

#set multiplot layout 3,1
#set tmargin 0
#set tmargin 0.8
#set bmargin 0.8

#set tics nomirror scale 0.66
#set xtics scale 0

#myvertoffset=0.02
">common.gnu



#sorted color sets
colset1="#f800ff"
colset2="#ff00e3 #f100ff"
colset3="#ffa900 #00ffdc #0096ff"
colset4="#ff005d #19ff00 #00ffc8 #c200ff"
colset5="#ff00c7 #9cff00 #00ff61 #0042ff #5700ff"
colset6="#ff00cb #ff1500 #59ff00 #00ffb5 #00b4ff #4f00ff"
colset7="#ff00f2 #ff000f #c0ff00 #0bff00 #00ffdd #0007ff #7800ff"
colset8="#ff004d #ff0100 #ffe800 #64ff00 #00ff94 #00daff #0070ff #c800ff"
colset9="#ff0081 #ff0031 #ffa500 #6aff00 #23ff00 #00ffb5 #0058ff #1300ff #ab00ff"
colset10="#ff00af #ff003b #ff4b00 #fff900 #6aff00 #00ff98 #00feff #00b6ff #3c00ff #8700ff"
colset11="#ff00de #ff1100 #ff7d00 #fff600 #59ff00 #1bff00 #00ff64 #00e7ff #009cff #7100ff #bc00ff"
colset12="#ff00b7 #ff0062 #ff5200 #ffdb00 #baff00 #54ff00 #00ff5e #00ff87 #0087ff #0083ff #7800ff #cc00ff"
colset13="#ff00b9 #ff0037 #ff2600 #ffa500 #bbff00 #84ff00 #00ff03 #00ff64 #00ffb5 #00cfff #0048ff #2b00ff #ba00ff"
colset14="#ff00d8 #ff0047 #ff0007 #ff7f00 #ffee00 #88ff00 #32ff00 #00ff67 #00ff75 #00c9ff #0070ff #0005ff #6c00ff #8f00ff"
colset15="#ff00db #ff0066 #ff2d00 #ff3400 #fff600 #adff00 #7eff00 #00ff03 #00ff72 #00ffc5 #00c6ff #0052ff #002fff #9500ff #bb00ff"
colset16="#ff00c8 #ff009b #ff0004 #ff7600 #ffbe00 #ffef00 #98ff00 #54ff00 #00ff2c #00ff6a #00ffbf #0088ff #004fff #0010ff #8900ff #b300ff"
colset17="#ff00ed #ff0053 #ff0005 #ff4200 #ffc200 #f9ff00 #aaff00 #52ff00 #14ff00 #00ff74 #00ffb5 #00ffe6 #00b4ff #0025ff #0003ff #6300ff #be00ff"
colset18="#ff00a9 #ff006c #ff004a #ff4000 #ff5a00 #ffae00 #e8ff00 #9bff00 #36ff00 #00ff3a #00ff7a #00fff4 #00bdff #007cff #0017ff #2a00ff #5d00ff #be00ff"
colset19="#ff00cb #ff007f #ff0054 #ff0b00 #ff7d00 #ffa700 #ffe400 #aaff00 #7cff00 #18ff00 #00ff41 #00ffb1 #00ffe1 #009cff #0071ff #001eff #1900ff #8a00ff #b400ff"
colset20="#ff00e1 #ff0086 #ff0037 #ff0400 #ff6f00 #ff8400 #fff100 #aeff00 #71ff00 #05ff00 #00ff22 #00ff56 #00ffd2 #00ecff #00c4ff #003eff #001cff #3300ff #8000ff #c700ff"
colset21="#ff00f0 #ff009c #ff004e #ff0004 #ff3300 #ff7400 #ffcc00 #f4ff00 #9fff00 #53ff00 #13ff00 #00ff3a #00ff9c #00ffb5 #00f1ff #00b4ff #0078ff #0007ff #3700ff #8a00ff #eb00ff"
colset22="#ff00d4 #ff00a1 #ff0064 #ff001f #ff3100 #ff9d00 #ffa200 #ffeb00 #a5ff00 #80ff00 #43ff00 #02ff00 #00ff49 #00ff88 #00ffe4 #00e6ff #008fff #004fff #001dff #4300ff #7900ff #b000ff"
colset23="#ff00f6 #ff00af #ff0047 #ff0012 #ff2e00 #ff6300 #ffc700 #fffc00 #bcff00 #6bff00 #63ff00 #0fff00 #00ff29 #00ff8b #00ffc5 #00fff1 #00c5ff #0072ff #0053ff #0200ff #3600ff #7700ff #bd00ff"
colset24="#ff00d7 #ff009e #ff0061 #ff0037 #ff3000 #ff7200 #ffaa00 #ffec00 #cfff00 #94ff00 #4eff00 #10ff00 #08ff00 #00ff59 #00ff86 #00ffc1 #00dcff #00b5ff #006cff #0041ff #1d00ff #5100ff #9800ff #d100ff"
colset25="#ff00e4 #ff0094 #ff007e #ff003b #ff0000 #ff4e00 #ff9100 #ffb000 #ffec00 #ccff00 #76ff00 #28ff00 #00ff17 #00ff50 #00ff5c #00ffa9 #00fff1 #00e6ff #008bff #005bff #0005ff #1b00ff #7000ff #8a00ff #c500ff"
colset26="#ff00ed #ff00a9 #ff0059 #ff0034 #ff0009 #ff4d00 #ff6200 #ffab00 #fffe00 #e3ff00 #8bff00 #7aff00 #41ff00 #00ff06 #00ff45 #00ff7c #00ffb5 #00fff7 #00b2ff #00a4ff #0067ff #0033ff #2e00ff #5a00ff #9d00ff #d500ff"
colset27="#ff00e2 #ff00af #ff0059 #ff0033 #ff1000 #ff2c00 #ff7500 #ffb100 #ffe600 #faff00 #c9ff00 #94ff00 #50ff00 #17ff00 #00ff39 #00ff74 #00ffad #00ffe6 #00fff9 #00c8ff #0089ff #004cff #0019ff #1700ff #6e00ff #9400ff #d600ff"
colset28="#ff00cd #ff00af #ff008a #ff003a #ff0020 #ff2f00 #ff6c00 #ff8300 #ffc200 #ffea00 #b5ff00 #82ff00 #71ff00 #12ff00 #00ff16 #00ff58 #00ff69 #00ffb6 #00ffd5 #00d0ff #00bcff #0077ff #002cff #0020ff #3c00ff #5900ff #9e00ff #be00ff"
colset29="#ff00d6 #ff00b4 #ff007e #ff005d #ff0013 #ff0f00 #ff4400 #ff8a00 #ffb300 #fff100 #e1ff00 #beff00 #6eff00 #31ff00 #03ff00 #00ff28 #00ff68 #00ff83 #00ffad #00ffe7 #00deff #0099ff #0053ff #0038ff #0011ff #4100ff #6d00ff #8800ff #e800ff"
colset30="#ff00d8 #ff00ae #ff0078 #ff0036 #ff0003 #ff0400 #ff5500 #ff8600 #ffb100 #ffd100 #cfff00 #b4ff00 #7dff00 #65ff00 #1cff00 #00ff0c #00ff4b #00ff86 #00ffb9 #00ffe5 #00f5ff #00a2ff #0086ff #0064ff #0014ff #2d00ff #4a00ff #8200ff #b100ff #de00ff"

#shuffled color sets
colset1="#f800ff"
colset2="#ff00e3 #f100ff"
colset3="#ffa900 #00ffdc #0096ff"
colset4="#ff005d #c200ff #00ffc8 #19ff00"
colset5="#0042ff #ff00c7 #5700ff #9cff00 #00ff61"
colset6="#00b4ff #4f00ff #ff1500 #59ff00 #ff00cb #00ffb5"
colset7="#ff000f #0007ff #0bff00 #ff00f2 #c0ff00 #00ffdd #7800ff"
colset8="#00ff94 #ff0100 #c800ff #ff004d #00daff #0070ff #ffe800 #64ff00"
colset9="#00ffb5 #ff0081 #0058ff #1300ff #6aff00 #ffa500 #23ff00 #ab00ff #ff0031"
colset10="#00feff #3c00ff #fff900 #00ff98 #ff003b #ff00af #8700ff #00b6ff #6aff00 #ff4b00"
colset11="#bc00ff #fff600 #ff7d00 #ff00de #00e7ff #009cff #7100ff #59ff00 #ff1100 #00ff64 #1bff00"
colset12="#0083ff #54ff00 #cc00ff #0087ff #ff0062 #ffdb00 #00ff5e #baff00 #00ff87 #ff00b7 #7800ff #ff5200"
colset13="#ffa500 #0048ff #00cfff #00ffb5 #bbff00 #00ff64 #2b00ff #ba00ff #00ff03 #ff0037 #ff2600 #ff00b9 #84ff00"
colset14="#ffee00 #00c9ff #0070ff #ff7f00 #ff00d8 #6c00ff #32ff00 #00ff75 #ff0007 #8f00ff #0005ff #00ff67 #88ff00 #ff0047"
colset15="#ff0066 #00c6ff #fff600 #bb00ff #7eff00 #002fff #00ff72 #00ffc5 #ff2d00 #9500ff #0052ff #00ff03 #adff00 #ff00db #ff3400"
colset16="#00ff2c #ffef00 #004fff #ffbe00 #b300ff #00ff6a #ff00c8 #8900ff #0010ff #98ff00 #54ff00 #ff009b #00ffbf #ff7600 #ff0004 #0088ff"
colset17="#ffc200 #00ff74 #6300ff #be00ff #00b4ff #14ff00 #ff00ed #ff4200 #52ff00 #ff0053 #aaff00 #f9ff00 #00ffb5 #00ffe6 #ff0005 #0003ff #0025ff"
colset18="#007cff #ff006c #ffae00 #ff00a9 #9bff00 #e8ff00 #ff004a #0017ff #5d00ff #ff5a00 #00fff4 #00bdff #00ff7a #2a00ff #00ff3a #be00ff #ff4000 #36ff00"
colset19="#ff7d00 #ffe400 #00ffe1 #00ffb1 #7cff00 #ff0054 #009cff #0071ff #ff0b00 #ffa700 #aaff00 #18ff00 #1900ff #001eff #ff00cb #b400ff #00ff41 #8a00ff #ff007f"
colset20="#00ff56 #ff0400 #003eff #8000ff #ff0037 #ff8400 #00ff22 #3300ff #ff6f00 #05ff00 #ff00e1 #001cff #00ecff #c700ff #00ffd2 #aeff00 #71ff00 #00c4ff #fff100 #ff0086"
colset21="#00f1ff #00ffb5 #ff7400 #ff0004 #0007ff #00ff9c #53ff00 #0078ff #ff009c #3700ff #ff004e #f4ff00 #ff3300 #13ff00 #9fff00 #eb00ff #00b4ff #ff00f0 #8a00ff #ffcc00 #00ff3a"
colset22="#4300ff #ff0064 #008fff #ff001f #ff9d00 #ff00a1 #ff3100 #7900ff #02ff00 #00ffe4 #a5ff00 #80ff00 #004fff #ffa200 #00ff49 #00ff88 #ff00d4 #43ff00 #b000ff #00e6ff #001dff #ffeb00"
colset23="#00ff29 #ffc700 #ff0012 #ff00af #fffc00 #6bff00 #00ffc5 #ff00f6 #ff0047 #3600ff #0053ff #7700ff #0200ff #63ff00 #ff6300 #ff2e00 #0fff00 #00ff8b #00fff1 #bcff00 #bd00ff #00c5ff #0072ff"
colset24="#ff009e #5100ff #0041ff #00b5ff #ff0061 #ff3000 #08ff00 #006cff #9800ff #10ff00 #4eff00 #1d00ff #94ff00 #ff00d7 #00dcff #00ff59 #00ffc1 #ff7200 #ffaa00 #d100ff #cfff00 #ff0037 #ffec00 #00ff86"
colset25="#00e6ff #76ff00 #28ff00 #00fff1 #00ff17 #ff00e4 #ff4e00 #ff007e #00ffa9 #ff9100 #005bff #ccff00 #00ff50 #008bff #ffb000 #ff0000 #8a00ff #1b00ff #c500ff #7000ff #0005ff #ff003b #00ff5c #ff0094 #ffec00"
colset26="#ff00ed #ff4d00 #0033ff #00a4ff #5a00ff #41ff00 #00ff06 #00ffb5 #0067ff #9d00ff #ff0059 #00b2ff #2e00ff #d500ff #fffe00 #7aff00 #ff00a9 #8bff00 #ffab00 #ff6200 #ff0034 #00ff7c #ff0009 #e3ff00 #00ff45 #00fff7"
colset27="#00c8ff #ffb100 #00ff39 #ff1000 #9400ff #faff00 #00fff9 #ff00e2 #0089ff #0019ff #c9ff00 #ff2c00 #94ff00 #ff0059 #d600ff #ffe600 #17ff00 #ff00af #50ff00 #6e00ff #00ff74 #1700ff #00ffad #ff0033 #ff7500 #00ffe6 #004cff"
colset28="#ff00af #ff8300 #9e00ff #0077ff #00d0ff #71ff00 #00ffd5 #ffc200 #ffea00 #ff008a #5900ff #b5ff00 #ff00cd #82ff00 #ff003a #be00ff #00ff58 #ff2f00 #3c00ff #ff6c00 #002cff #00bcff #00ff69 #ff0020 #12ff00 #0020ff #00ffb6 #00ff16"
colset29="#ff8a00 #6d00ff #6eff00 #e1ff00 #ff4400 #00ff28 #00ffe7 #31ff00 #ff00d6 #ff00b4 #ff0013 #00ff68 #ffb300 #00ff83 #00deff #beff00 #ff007e #0099ff #0038ff #fff100 #ff0f00 #0011ff #ff005d #03ff00 #4100ff #00ffad #0053ff #8800ff #e800ff"
colset30="#2d00ff #00ff4b #ff00d8 #b100ff #ff0003 #00f5ff #0064ff #ff0078 #b4ff00 #00ff0c #0014ff #ff5500 #0086ff #cfff00 #00ffe5 #7dff00 #00a2ff #ff0036 #1cff00 #ff8600 #ffd100 #de00ff #8200ff #4a00ff #ff00ae #65ff00 #00ff86 #ff0400 #00ffb9 #ffb100"

# calc the number of Files
FILES=(`find . -maxdepth 1 -size +1c -iname "*.sum" | sort --numeric-sort`)
SIZE=${#FILES[@]}

#colset now gets assigned the value of colset$SIZE
colset="colset$SIZE" 
eval colset=\$$colset

INT=1
for COLOR in $colset; do
  #echo "set style line ${INT} lt 1 lc rgb \"${COLOR}\" lw mylw1 pt mypt1 ps myps1" >>common.gnu
  ## above color sets are not used per default (usefull in papers etc)
  echo "set style line ${INT} lw mylw1 pt mypt1 ps myps1" >>common.gnu
  ((INT++))
done



echo "load 'common.gnu'
load 'defs.gnu'

set out 'ram.eps'

set xlabel \"Runtime [h] $END\"
set ylabel \"RAM usage GiB\"
set yrange [0:]
" >ram.gnu
echo -n "plot ">>ram.gnu

INT=1
for FILE in ${FILES[@]}; do
  FILE=`basename $FILE`
  app_name=`echo $FILE | cut -d '.' -f 3`
  echo -n "     '${FILE}' using 1:(fg*\$11) title \"$app_name\"  ls ${INT}" >>ram.gnu
  if [ $INT -lt $SIZE ]; then echo " ,\\" >>ram.gnu; fi
  ((INT++))
done
echo "" >>ram.gnu



echo "load 'common.gnu'
load 'defs.gnu'

set out 'cpu.eps'

set xlabel \"Runtime [h] $END\"
set ylabel \"Core Utilization\"
set yrange [0:ncpu]
" >cpu.gnu
echo -n "plot ">>cpu.gnu

INT=1
for FILE in ${FILES[@]}; do
  FILE=`basename $FILE`
  app_name=`echo $FILE | cut -d '.' -f 3`
  echo -n "     '${FILE}' using 1:(\$19/100) title \"$app_name\" ls ${INT}" >>cpu.gnu
  if [ $INT -lt $SIZE ]; then echo " ,\\" >>cpu.gnu; fi
  ((INT++))
done
echo "" >>cpu.gnu


echo "load 'common.gnu'
load 'defs.gnu'

set out 'io.eps'

set xlabel \"Runtime [h] $END\"
set ylabel \"I/O MiB/s\"
set yrange [0.005:2000]
set logscale y
set ytics (\"10^{-3}\" 0.001, \"10^{-2}\" 0.01, \"10^{-1}\" 0.1, \"10^{0}\" 1, \"10^{1}\" 10, \"10^{2}\" 100, \"10^{3}\" 1000)
" >io.gnu
echo -n "plot ">>io.gnu

INT=1
for FILE in ${FILES[@]}; do
  FILE=`basename $FILE`
  app_name=`echo $FILE | cut -d '.' -f 3`
  echo -n "     '${FILE}' using 1:(fm*(\$23+\$24)) title \"$app_name\" ls ${INT}" >>io.gnu
  if [ $INT -lt $SIZE ]; then echo " ,\\" >>io.gnu; fi
  ((INT++))
done
echo "" >>io.gnu


gnuplot ram.gnu
gnuplot cpu.gnu
gnuplot io.gnu
