#!/bin/bash
export FIO_MOUNTPOINT="/data"
export FIO_TEST_SET="/opt/ceph-bench/fio-tasks-64.list"

export FIO_NAME="batch_run"

export FIO_BS="4k"
export FIO_IODEPTH="64"
export FIO_SIZE="5G"
export FIO_RAMP_TIME="5s"
export FIO_RUNTIME="90s"

/opt/ceph-bench/run-fio-batch.sh
