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

1. Download [fio.yaml](https://raw.githubusercontent.com/savex13/benchmarks/master/fio.yaml) and edit the `storageClassName` to match your Kubernetes provider's Storage Class `kubectl get storageclasses`
2. Deploy fio using: `kubectl apply -f fio.yaml`
3. Once deployed, the fio Job will:
    * provision a Persistent Volume of `1000Gi` (default) using `storageClassName: ssd` (default)
    * run a series of `fio` tests on the newly provisioned disk
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

# Reporting

Full fio output is stored on mounted volume with filename of 'test\_runmode\_operation.log'
Each test run will create 'report.csv' file on mounted volume with test run values collected
```
# hostname,test_run,test_name,read_percent,jobs,offset,block_size,io_depth,size,iops,bw,latency
```
If corresponding value was collected during the run - it will be stored in its respective place

## Notes / Troubleshooting

* If the Persistent Volume Claim is stuck on Pending, it's likely you didn't specify a valid Storage Class. Double check using `kubectl get storageclasses`. Also check that the volume size of `1000Gi` (default) is available for provisioning.
* It can take some time for a Persistent Volume to be Bound and the Kubernetes Dashboard UI will show the Dbench Job as red until the volume is finished provisioning.
* It's useful to test multiple disk sizes as most cloud providers price IOPS per GB provisioned. So a `4000Gi` volume will perform better than a `1000Gi` volume. Just edit the yaml, `kubectl delete -f dbench.yaml` and run `kubectl apply -f dbench.yaml` again after deprovision/delete completes.
* A list of all `fio` tests are in [fio-entrypoint.sh](https://github.com/savex13/benchmarks/blob/master/fio-entrypoint.sh).

## License

* MIT
