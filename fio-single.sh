#!/usr/bin/env bash
set -e

SLEEP_BASE=$( get_var $SLEEP_BASE 10)

# Round down time to nearest 5 min and get time +10 min in future
function get_time() {
    # 10 min gives 6 min for pod to start in most critical circumstances
    # I.e. when scheduled from 8:50 to 9:00 (down to 8:50 and up to 9:00)
    h=$( date +"%H" )
    m=$( date +"%M" )
    (( i = m/5, i *= 5, m = 10-(m-i) ))
    date +"%H:%M" -d"+$m min"
}

# Credits to F.Hauri
# https://stackoverflow.com/questions/645992/sleep-until-a-specific-time-date
function sleepUntil() { # args [-q] <HH[:MM[:SS]]> [more days]
    local slp tzoff now quiet=false
    [ "$1" = "-q" ] && shift && quiet=true
    local -a hms=(${1//:/ })
    printf -v now '%(%s)T' -1
    printf -v tzoff '%(%z)T\n' $now
    tzoff=$((0${tzoff:0:1}(3600*${tzoff:1:2}+60*${tzoff:3:2})))
    slp=$((
       ( 86400+(now-now%86400) + 10#$hms*3600 + 10#${hms[1]}*60 + 
         ${hms[2]}-tzoff-now ) %86400 + ${2:-0}*86400
    ))
    $quiet || printf 'sleep %ss, -> %(%c)T\n' $slp $((now+slp))
    sleep $slp
}

# Fancy "get default value" function
function get_var() {
    # if $1 and $2 exists, then we must use $1
    # if there is only $1, then $1 is actually empty and it is a $2 shown as $1
    # if nothing, then just break exit
    if [ -z $2 ]; then
        if [ -z $1 ]; then
            echo "Error in script while setting vars"
            exit 1
        else
            echo $1
        fi
    else
       echo $1
    fi
}

# Global vars
# Run mode "synced" schedules run to +3-5 min to sync between pods
# Run mode "normal" starts right away
RUN_MODE=$( get_var $RUN_MODE "synced")
FIO_RANDREPEAT=$( get_var $FIO_RANDREPEAT 0)
FIO_VERIFY=$( get_var $FIO_VERIFY 0)
FIO_IOENGINE=$( get_var $FIO_IOENGINE libaio)
FIO_DIRECT=$( get_var $FIO_DIRECT "1")
FIO_GTOD_REDUCE=$( get_var $FIO_GTOD_REDUCE 0)
FIO_NAME=$( get_var $FIO_NAME "single_run")
FIO_MOUNTPOINT=$( get_var $FIO_MOUNTPOINT "/tmp")
FIO_BS=$( get_var $FIO_BS "4k")
FIO_IODEPTH=$( get_var $FIO_IODEPTH 64)
FIO_SIZE=$( get_var $FIO_SIZE "2G")
# test modes: 'randread', 'randwrite', 'read', 'write', 'randrw'
FIO_READWRITE=$( get_var $FIO_READWRITE "randrw")

FIO_RAMP_TIME=$( get_var $FIO_RAMP_TIME "5s")
FIO_RUNTIME=$( get_var $FIO_RUNTIME "30s")

# Sequential specific
FIO_OFFSET_INCREMENT=$( get_var $FIO_OFFSET_INCREMENT "500M")
FIO_JOBS=$( get_var $FIO_JOBS "4")

# Mixed specific
FIO_RWMIXREAD=$( get_var $FIO_RWMIXREAD "50")

# Option builders
function get_options() {
    echo "--randrepeat=$FIO_RANDREPEAT "\
"--verify=$FIO_VERIFY "\
"--ioengine=$FIO_IOENGINE "\
"--direct=$FIO_DIRECT "\
"--gtod_reduce=$FIO_GTOD_REDUCE "\
"--name=$FIO_NAME "\
"--filename=$FIO_MOUNTPOINT/fiotest "\
"--bs=$FIO_BS "\
"--iodepth=$FIO_IODEPTH "\
"--size=$FIO_SIZE "\
"--readwrite=$FIO_READWRITE "\
"--time_based "\
"--ramp_time=$FIO_RAMP_TIME "\
"--runtime=$FIO_RUNTIME "
}

function get_seq_options() {
    echo "--thread "\
"--numjobs=$FIO_JOBS "\
"--offset_increment=$FIO_OFFSET_INCREMENT "
}

function get_mix_options() {
    echo "--rwmixread=$FIO_RWMIXREAD "
}

# Parsers
function get_iops_read() {
    echo "$1"|grep -E 'read ?:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2
}

function get_iops_write() {
    echo "$1"|grep -E 'write:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2
}

function get_bw_read() {
    echo "$1"|grep -E 'read ?:'|grep -Eoi 'BW=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

function get_bw_write() {
    echo "$1"|grep -E 'write:'|grep -Eoi 'BW=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

function get_latency() {
    echo "$1"|grep ' lat.*avg'|grep -Eoi 'avg=[0-9.]+'|cut -d'=' -f2
}

function get_seq_read() {
    echo "$1"|grep -E 'READ:'|grep -Eoi '(aggrb|bw)=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

function get_seq_write() {
    echo "$1"|grep -E 'WRITE:'|grep -Eoi '(aggrb|bw)=[0-9GMKiBs/.]+'|cut -d'=' -f2
}


# Main
TIMESTAMP=$( date +"%Y-%m-%d-%H-%M" )
if [ -f "$FIO_MOUNTPOINT/lastrun" ]; then
   # we already done with this test, sleep for 15 min and exit
   # sleep is used to prevent frequent reruns if this used in StateFulSet
   echo "# Last run was completed on $(cat $FIO_MOUNTPOINT/lastrun). Test skipped."
   sleep 900
   exit 1
fi

echo "# Running $RUN_MODE single fio test: $FIO_READWRITE"
FIO_CMD="fio $( get_options )"
if [ $FIO_READWRITE = 'randrw' ]; then
    echo "# Mixed read %: $FIO_RWMIXREAD"
    FIO_CMD+="$( get_mix_options )"
elif [ $FIO_READWRITE = 'read' ] || [ $FIO_READWRITE = 'write' ]; then
    echo "# Jobs: $FIO_JOBS"
    echo "# Offset increment: ${FIO_OFFSET_INCREMENT}"
    FIO_CMD+="$( get_seq_options )"
fi
echo
echo "# Working dir: ${FIO_MOUNTPOINT}"
echo "# Size: ${FIO_SIZE}"
echo "# Direct flag set to ${FIO_DIRECT}"
echo "# Block size: $FIO_BS" 
echo "# IO Depth: $FIO_IODEPTH"
echo

echo "cmd: '$FIO_CMD'"
echo

# Run fio
if [ $RUN_MODE = 'synced' ]; then
    # run synced, i.e. wait for specific time
    target_time=$( get_time )
    echo "Scheduled 'sync' time is $target_time"
    sleepUntil $target_time
fi
FIO_OUT=$( $FIO_CMD )
echo "$FIO_OUT" >$FIO_MOUNTPOINT/test-$RUN_MODE-$FIO_READWRITE-$FIO_BS-$FIO_IODEPTH-$FIO_SIZE-$TIMESTAMP.log

echo "Single test complete."
echo
echo "=================="
echo "==== Summary ====="
echo "=================="

# Parse output and write a report
LATENCY_VAL=( $(get_latency "$FIO_OUT") )

# Prepare 'report.csv'
REPORT_FILE=$FIO_MOUNTPOINT/$HOSTNAME"-report.csv"
if [ ! -f $REPORTFILE ]; then
    touch $REPORT_FILE
    echo "# hostname,timestamp,test_run,test_name,read_percent,jobs,offset,block_size,io_depth,size,iops,bw,latency" >>$REPORT_FILE
fi

if [ $FIO_READWRITE = 'randrw' ]; then
    # get both read and write
    echo "Mixed R($FIO_RWMIXREAD%)/W"
	READ_IOPS_VAL=$(get_iops_read "$FIO_OUT")
	WRITE_IOPS_VAL=$(get_iops_write "$FIO_OUT")
	READ_BW_VAL=$(get_bw_read "$FIO_OUT")
	WRITE_BW_VAL=$(get_bw_write "$FIO_OUT")
    echo "IOPS: $READ_IOPS_VAL/$WRITE_IOPS_VAL"
    echo "BW: $READ_BW_VAL / $WRITE_BW_VAL"
	echo "Average Latency (usec): $LATENCY_VAL"
	# save values as csv
	(( FIO_RWMIXWRITE = 100 - FIO_RWMIXREAD ))
	echo "$HOSTNAME,$TIMESTAMP,$FIO_TEST_SET,${FIO_READWRITE}_read,$FIO_RWMIXREAD,1,no,$FIO_BS,$FIO_IODEPTH,$FIO_SIZE,$READ_IOPS_VAL,$READ_BW_VAL,${LATENCY_VAL[0]}" >>$REPORT_FILE	
	echo "$HOSTNAME,$TIMESTAMP,$FIO_TEST_SET,${FIO_READWRITE}_write,$FIO_RWMIXWRITE,1,no,$FIO_BS,$FIO_IODEPTH,$FIO_SIZE,$WRITE_IOPS_VAL,$WRITE_BW_VAL,${LATENCY_VAL[1]}" >>$REPORT_FILE	
elif [ $FIO_READWRITE = 'read' ]; then
    # get read values
    echo "Sequential Read"
    READ_IOPS_VAL=$(get_iops_read "$FIO_OUT")
    READ_SEQ_VAL=$(get_seq_read "$FIO_OUT")
    echo "IOPS: $READ_IOPS_VAL"
    echo "BW: $READ_SEQ_VAL"
	# save values as csv
	echo "$HOSTNAME,$TIMESTAMP,$FIO_TEST_SET,$FIO_READWRITE,no,$FIO_JOBS,$FIO_OFFSET_INCREMENT,$FIO_BS,$FIO_IODEPTH,$FIO_SIZE,$READ_IOPS_VAL,$READ_SEQ_VAL,$LATENCY_VAL" >>$REPORT_FILE
elif [ $FIO_READWRITE = 'write' ]; then
    # get write values
    echo "Sequential Write"
    WRITE_IOPS_VAL=$(get_iops_write "$FIO_OUT")
    WRITE_SEQ_VAL=$(get_seq_write "$FIO_OUT")
    echo "IOPS: $WRITE_IOPS_VAL"
    echo "BW: $WRITE_SEQ_VAL"
	# save values as csv
	echo "$HOSTNAME,$TIMESTAMP,$FIO_TEST_SET,$FIO_READWRITE,no,$FIO_JOBS,$FIO_OFFSET_INCREMENT,$FIO_BS,$FIO_IODEPTH,$FIO_SIZE,$WRITE_IOPS_VAL,$WRITE_SEQ_VAL,$LATENCY_VAL" >>$REPORT_FILE
elif [ $FIO_READWRITE = 'randread' ]; then
    # get read values
    echo "Random Read"
    READ_IOPS_VAL=$(get_iops_read "$FIO_OUT")
    READ_BW_VAL=$(get_bw_read "$FIO_OUT")
    echo "IOPS: $READ_IOPS_VAL"
    echo "BW: $READ_BW_VAL"
	# save values as csv
	echo "$HOSTNAME,$TIMESTAMP,$FIO_TEST_SET,$FIO_READWRITE,no,1,no,$FIO_BS,$FIO_IODEPTH,$FIO_SIZE,$READ_IOPS_VAL,$READ_BW_VAL,$LATENCY_VAL" >>$REPORT_FILE	
elif [ $FIO_READWRITE = 'randwrite' ]; then
    # get write values
    echo "Random Write"
    WRITE_IOPS_VAL=$(get_iops_write "$FIO_OUT")
    WRITE_BW_VAL=$(get_bw_write "$FIO_OUT")
    echo "IOPS: $WRITE_IOPS_VAL"
    echo "BW: $WRITE_BW_VAL"
	# save values as csv
	echo "$HOSTNAME,$TIMESTAMP,$FIO_TEST_SET,$FIO_READWRITE,no,1,no,$FIO_BS,$FIO_IODEPTH,$FIO_SIZE,$WRITE_IOPS_VAL,$WRITE_BW_VAL,$LATENCY_VAL" >>$REPORT_FILE	
fi

rm $FIO_MOUNTPOINT/fiotest
# Set "stopper" before next run
echo "$TIMESTAMP" >$FIO_MOUNTPOINT/lastrun
exit 0

exec "$@"
