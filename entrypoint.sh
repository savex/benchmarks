#!/usr/bin/env bash
set -e

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
FIO_TEST_SET=$( get_var $FIO_TEST_SET "bulk")
FIO_MOUNTPOINT=$( get_var $FIO_MOUNTPOINT "/tmp")

if [ $FIO_TEST_SET = 'bulk' ]; then
    /fio-bulk.sh
elif [ $FIO_TEST_SET = 'single' ]; then
    /fio-single.sh
elif [ -f $FIO_TEST_SET ]; then
        # Do a param validation first
        errors=0
        cat $FIO_TEST_SET | while read opts; do
			params=($(echo "$opts" | tr ',' '\n'))
			if [ ${#params[@]} != 5 ]; then
			   echo "# Incorrect number of params (${#params[@]}) in $FIO_TEST_SET, line: '$opts'"
			fi
			(( errors += 1 ))
        done
        if [ $errors > 0 ]; then
            echo "# $errors found in taskfile.conf. Exiting."
            echo
            echo "# Please, use following format:"
            echo "FIO_READWRITE,FIO_RWMIXREAD,FIO_BS,FIO_IODEPTH,FIO_SIZE"
            echo
            echo "# Example:"
            echo "randrw,70,64k,64,5G"
            echo "randread,100,8k,16,5G"
            exit 1
        fi
        # Start an actual run
        # set initial sleep time to 10 min
        export SLEEP_BASE=10
        cat $FIO_TEST_SET | while read opts; do
			params=($(echo "$opts" | tr ',' '\n'))
			echo
			echo "### Running Task: ${params[@]}"
			# Map params to vars and run 'single'
			export FIO_READWRITE="${params[0]}"
			export FIO_RWMIXREAD="${params[1]}"
			export FIO_BS="${params[2]}"
			export FIO_IODEPTH="${params[3]}"
			export FIO_SIZE="${params[4]}"
			# start current task
			/fio-single.sh
			# remove lastrun stopper
			rm $FIO_MOUNTPOINT/lastrun
                        # reset sleep time to 5 min
                        export SLEEP_BASE=5
        done
else
    echo "# Unknown test set of '$FIO_TEST_SET'"
    echo "# Nothing to do, set env var FIO_TEST_SET to either 'bulk', 'single' or a path to mounted ConfigMap for taskfile.conf"
    exit 1
fi

exec "$@"
