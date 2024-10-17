# dsp-patch-swf

This script is a workaround for https://issues.redhat.com/browse/RHOAIENG-14265.
It patches the `ScheduledWorkflow` instances so they are compatible with RHOAI 2.14 RC3.

## How to use

Run the script passing the namespace as an argument.
For example, given you want to patch the `ScheduledWorkflow` instances in the `dspa-example1` namespace, you need to run the following:

```shell
./patch_swf.sh --namespace dspa-example1
```
