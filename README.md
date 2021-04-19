# fio container
Benchmark Kubernetes persistent disk volumes with `fio`: Read/write IOPS, bandwidth MB/s and latency.

Based on the excellent work of
* Lee Liu (LogDNA)
* [Alexis Turpin](https://github.com/alexis-turpin)

# Updates and changes
Here is the list of updates made so far
 * Removed Alpine linux dependency, based on Ubuntu:20.04
 * Clone-n-make of fio every time when docker container is built
 * Cleaner output of tests
 * fio output stored in mounted folder
 * Current versions are 'docker-fio-2-17' and 'docker-fio-3.26'

# Usage

### 'Synced' and 'Normal' run modes
Default RUN\_MODE is 'synced'. It will round current time to nearest 5 min in the past, add 10 min and will wait for that time before starting the test.
It is handy if you want to run a number of Replicas of the test and see what happens (Sum, Average, etc)

Normal mode starts the test right away.

### 'Bulk' run
1. Download [fio-bulk.yaml](https://raw.githubusercontent.com/savex/benchmarks/master/fio-bulk.sh) and edit the `storageClassName` to match your Kubernetes provider's Storage Class `kubectl get storageclasses`
   Change test parameters if needed.
2. Deploy fio using: `kubectl apply -f fio-bulk.yaml`
3. Once deployed, the fio Job will:
    * provision a Persistent Volume of `1000Gi` (default) using `storageClassName: ssd` (default)
    * run a series of `fio` tests on the newly provisioned disk according to parameters set
    * currently there are 9 tests, 15s per test - total runtime is ~2.5 minutes
    * each test can be configured with specific block size and depth instead of defaults
4. Follow benchmarking progress using: `kubectl logs -f job/dbench` (empty output means the Job not yet created, or `storageClassName` is invalid, see Troubleshooting below)
5. At the end of all tests, you'll see a summary that looks similar to this:
```
==================
==== Summary =====
==================
Random Read/Write IOPS: 75.7k/59.7k. BW: 523MiB/s / 500MiB/s
Average Latency (usec) Read/Write: 183.07/76.91
Sequential Read/Write: 536MiB/s / 512MiB/s
Mixed Random Read/Write IOPS: 43.1k/14.4k
```
If latency is not shown for you, then it is probably something wrong with measuring it via kernel/device
6. Once the tests are finished, clean up using: `kubectl delete -f dbench.yaml` and that should deprovision the persistent disk and delete it to minimize storage billing.

### 'Single' run
A single fio run with all major parameters mapped as Environment variables.
See [fio-job-single.yaml](https://raw.githubusercontent.com/savex/benchmarks/master/fio-job-single.yaml) for details.

It can be used in StatefulSet when running in 'synced'. See [fio-statefulset-single.yaml](https://raw.githubusercontent.com/savex/benchmarks/master/fio-statefulset-single.yaml)

Make sure that you set FIO\_GTOD\_REDUCE to '0' when measuring latency.

### 'Taskfile' run

Also, FIO\_TEST\_SET can point to mounted file to do multiple 'synced' or 'normal' single runs.
See [fio-statefulset-taskfile.yaml](https://raw.githubusercontent.com/savex/benchmarks/master/fio-statefulset-taskfile.yaml)

# Reporting

Full fio output is stored on mounted volume with filename of 'test-runmode-operation-blocksize-iodepth-size-timestamp.log'
Each test run will create 'hostname-report.csv' file on mounted volume with test run values collected
```
# hostname,test_run,test_name,read_percent,jobs,offset,block_size,io_depth,size,iops,bw,latency
```
If corresponding value was collected during the run - it will be stored in its respective place. Each subsequent run adds record to the report.

## Notes / Troubleshooting

* If the Persistent Volume Claim is stuck on Pending, it's likely you didn't specify a valid Storage Class. Double check using `kubectl get storageclasses`. Also check that the volume size of `1000Gi` (default) is available for provisioning.
* It can take some time for a Persistent Volume to be Bound and the Kubernetes Dashboard UI will show the Dbench Job as red until the volume is finished provisioning.
* It's useful to test multiple disk sizes as most cloud providers price IOPS per GB provisioned. So a `4000Gi` volume will perform better than a `1000Gi` volume. Just edit the yaml, `kubectl delete -f dbench.yaml` and run `kubectl apply -f dbench.yaml` again after deprovision/delete completes.
* A list of all `fio` tests are in [fio-entrypoint.sh](https://github.com/savex13/benchmarks/blob/master/fio-entrypoint.sh).

## License

* MIT
