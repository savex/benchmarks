#!/usr/bin/env bash
set -e

# Round down time to nearest 5 min and get time +7 min in future
function get_time() {
    # 7 min gives 3 min for pod to start in most critical circumstances
    # I.e. when scheduled from 8:54 to 8:57 (down to 8:50 and up to 8:57)
    h=$( date +"%H" )
    m=$( date +"%M" )
    (( m /= 5, m *= 5, m += 7 )) && echo "$h:$m"
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
FIO_MOUNTPOINT=$( get_var $FIO_MOUNTPOINT "/tmp")
FIO_SIZE=$( get_var $FIO_SIZE "2G")
FIO_OFFSET_INCREMENT=$( get_var $FIO_OFFSET_INCREMENT "500M")
FIO_DIRECT=$( get_var $FIO_DIRECT "1")
FIO_IODEPTH=$( get_var $FIO_IODEPTH "64")

# IOPS test
IOPS_BS=$( get_var $IOPS_BS "4k")
IOPS_DP=$( get_var $IOPS_DP $FIO_IODEPTH)

# Bandwidth test
BW_BS=$( get_var $BW_BS "128k")
BW_DP=$( get_var $BW_DP $FIO_IODEPTH)

# Latency test
LAT_BS=$( get_var $LAT_BS "4k")
LAT_DP=$( get_var $LAT_DP "4")

# Sequential test
SEQ_BS=$( get_var $SEQ_BS "1M")
SEQ_DP=$( get_var $SEQ_DP "16")
SEQ_JOBS=$( get_var $SEQ_JOBS "4")

# Mixed test
MIX_BS=$( get_var $MIX_BS "4k")
MIX_DP=$( get_var $MIX_DP $FIO_IODEPTH)
MIX_RWMIXREAD=$( get_var $MIX_RWMIXREAD "75")

function run_fio() {
    fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=$FIO_DIRECT --gtod_reduce=1 --name=$1 --filename=$FIO_MOUNTPOINT/fiotest --bs=$2 --iodepth=$3 --size=$FIO_SIZE --readwrite=$4 --time_based --ramp_time=2s --runtime=15s
}

function run_fio_seq() {
    fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=$FIO_DIRECT --gtod_reduce=1 --name=$1 --filename=$FIO_MOUNTPOINT/fiotest --bs=$2 --iodepth=$3 --size=$FIO_SIZE --readwrite=$4 --time_based --ramp_time=2s --runtime=15s --thread --numjobs=${SEQ_JOBS} --offset_increment=$FIO_OFFSET_INCREMENT
}

# Tests
function test_iops_read() {
    READ_IOPS=$(run_fio read_iops $IOPS_BS $IOPS_DP randread)
    echo "$READ_IOPS" >$FIO_MOUNTPOINT/test_iops_read.log
    echo "$READ_IOPS"|grep -E 'read ?:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2
}

function test_iops_write() {
    WRITE_IOPS=$(run_fio write_iops $IOPS_BS $IOPS_DP randwrite)
    echo "$WRITE_IOPS" >$FIO_MOUNTPOINT/test_iops_write.log
    echo "$WRITE_IOPS"|grep -E 'write:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2
}

function test_bw_read() {
    READ_BW=$(run_fio read_bw $BW_BS $BW_DP randread)
    echo "$READ_BW" >$FIO_MOUNTPOINT/test_bw_read.log
    echo "$READ_BW"|grep -E 'read ?:'|grep -Eoi 'BW=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

function test_bw_write() {
    WRITE_BW=$(run_fio write_bw $BW_BS $BW_DP randwrite)
    echo "$WRITE_BW" >$FIO_MOUNTPOINT/test_bw_write.log
    echo "$WRITE_BW"|grep -E 'write:'|grep -Eoi 'BW=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

function test_latency_read() {
    READ_LATENCY=$(run_fio read_latency $LAT_BS $LAT_DP randread)
    echo "$READ_LATENCY" >$FIO_MOUNTPOINT/test_latency_read.log
    echo "$READ_LATENCY"|grep ' lat.*avg'|grep -Eoi 'avg=[0-9.]+'|cut -d'=' -f2
}

function test_latency_write() {
    WRITE_LATENCY=$(run_fio write_latency $LAT_BS $LAT_DP randwrite)
    echo "$WRITE_LATENCY" >$FIO_MOUNTPOINT/test_latency_write.log
    echo "$WRITE_LATENCY"|grep ' lat.*avg'|grep -Eoi 'avg=[0-9.]+'|cut -d'=' -f2
}

function test_seq_read() {
    READ_SEQ=$(run_fio_seq read_seq $SEQ_BS $SEQ_DP read)
    echo "$READ_SEQ" >$FIO_MOUNTPOINT/test_seq_read.log
    echo "$READ_SEQ"|grep -E 'READ:'|grep -Eoi '(aggrb|bw)=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

function test_seq_write() {
    WRITE_SEQ=$(run_fio_seq write_seq $SEQ_BS $SEQ_DP write)
    echo "$WRITE_SEQ" >$FIO_MOUNTPOINT/test_seq_write.log
    echo "$WRITE_SEQ"|grep -E 'WRITE:'|grep -Eoi '(aggrb|bw)=[0-9GMKiBs/.]+'|cut -d'=' -f2
}

# Main
echo "# Running $RUN_MODE bulk fio tests"
echo "Working dir: ${FIO_MOUNTPOINT}"
echo "Size: ${FIO_SIZE}"
echo "Offset increment: ${FIO_OFFSET_INCREMENT}"
echo "Direct flag set to ${FIO_DIRECT}"
echo "Default iodepth: $FIO_IODEPTH"
if [ "$FIO_QUICK" == "" ] || [ "$FIO_QUICK" == "no" ]; then
    echo "Quick test: no"
else
    echo "Quick test: yes"
fi
echo

# Handle synced mode
if [ $RUN_MODE = 'synced' ]; then
    # run synced, i.e. wait for specific time
    target_time=$( get_time )
    echo "Scheduled 'sync' time is $target_time"
    sleepUntil $target_time
fi

echo "# Testing Read IOPS ($IOPS_BS/$IOPS_DP/$FIO_SIZE)"
READ_IOPS_VAL=$(test_iops_read)

echo "# Testing Write IOPS ($IOPS_BS/$IOPS_DP/$FIO_SIZE)"
WRITE_IOPS_VAL=$(test_iops_write)

echo "# Testing Read Bandwidth ($BW_BS/$BW_DP/$FIO_SIZE)"
READ_BW_VAL=$(test_bw_read)

echo "# Testing Write Bandwidth ($BW_BS/$BW_DP/$FIO_SIZE)"
WRITE_BW_VAL=$(test_bw_write)

if [ "$FIO_QUICK" == "" ] || [ "$FIO_QUICK" == "no" ]; then
    echo "# Testing Read Latency ($LAT_BS/$LAT_DP/$FIO_SIZE)"
    READ_LATENCY_VAL=$(test_latency_read)

    echo "# Testing Write Latency ($LAT_BS/$LAT_DP/$FIO_SIZE)"
    WRITE_LATENCY_VAL=$(test_latency_write)

    echo "# Testing Read Sequential Speed ($SEQ_BS/$SEQ_DP/$FIO_SIZE, $SEQ_JOBS jobs, offset $FIO_OFFSET_INCREMENT)"
    READ_SEQ_VAL=$(test_seq_read)

    echo "# Testing Write Sequential Speed ($SEQ_BS/$SEQ_DP/$FIO_SIZE, $SEQ_JOBS jobs, offset $FIO_OFFSET_INCREMENT)"
    WRITE_SEQ_VAL=$(test_seq_write)

    echo "# Testing Read/Write Mixed ($MIX_BS/$MIX_DP/$FIO_SIZE, rwmixread at $MIX_RWMIXREAD%)"
    RW_MIX=$(fio --randrepeat=0 --verify=0 --ioengine=libaio --direct=$FIO_DIRECT --gtod_reduce=1 --name=rw_mix --filename=$FIO_MOUNTPOINT/fiotest --bs=$MIX_BS --iodepth=$MIX_DP --size=$FIO_SIZE --readwrite=randrw --rwmixread=$MIX_RWMIXREAD --time_based --ramp_time=2s --runtime=15s)
    echo "$RW_MIX" >$FIO_MOUNTPOINT/test_mix_readwrite.log
    RW_MIX_R_IOPS=$(echo "$RW_MIX"|grep -E 'read ?:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2)
    RW_MIX_W_IOPS=$(echo "$RW_MIX"|grep -E 'write:'|grep -Eoi 'IOPS=[0-9k.]+'|cut -d'=' -f2)
fi

echo "Bulk tests complete."
echo
echo "=================="
echo "==== Summary ====="
echo "=================="
echo "Random Read/Write IOPS: $READ_IOPS_VAL/$WRITE_IOPS_VAL. BW: $READ_BW_VAL / $WRITE_BW_VAL"
if [ -z $FIO_QUICK ] || [ "$FIO_QUICK" == "no" ]; then
    echo "Average Latency (usec) Read/Write: $READ_LATENCY_VAL/$WRITE_LATENCY_VAL"
    echo "Sequential Read/Write: $READ_SEQ_VAL / $WRITE_SEQ_VAL"
    echo "Mixed Random Read/Write IOPS: $RW_MIX_R_IOPS/$RW_MIX_W_IOPS"
fi

rm $FIO_MOUNTPOINT/fiotest
exit 0

exec "$@"
