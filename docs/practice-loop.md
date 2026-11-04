# Practice Loop: Reset and Rebuild the Cluster

The CKA asks you to "create and manage Kubernetes clusters using kubeadm," and the way to get fast at that is to build the cluster more than once.  Tearing the lab down with Terraform and building it again works, but then you prepare every node from scratch.  This page has three shorter loops that reuse the VMs you already have:

| Loop | What you redo | Time in testing |
| --- | --- | --- |
| [Remove and re-join a worker](#remove-and-re-join-a-worker) | One worker's `kubeadm join` | About 2 minutes |
| [Reset the whole cluster](#reset-the-whole-cluster) | `kubeadm init`, Calico, and the joins, on the same VMs | About 10 minutes, mostly Calico starting |
| [Revert to a snapshot](#snapshot-the-prepared-nodes-and-revert) | Everything from `kubeadm init` on, on nodes rolled back to before it | A few seconds per node, then the same as a reset |

Start with a working cluster from the [README](../README.md), through [Run a Test Workload](../README.md#run-a-test-workload).  These loops work on every size in [`examples`](../examples).  They were tested on `examples/lean.tfvars`, so the sample output has one worker.  With more workers, repeat the worker steps on each one.

## Remove and Re-join a Worker

[kubernetes.io: Creating a cluster with kubeadm, Remove the node](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#remove-the-node)

This follows the order in the Kubernetes docs: drain the node, reset it, delete it from the cluster, then join it again.

***Perform the following step on the Control Plane node, as `ubuntu`.***

**Drain the worker, so its pods move off it:**

```bash
kubectl drain worker-node-01 --delete-emptydir-data --force --ignore-daemonsets
```

**SAMPLE OUTPUT:**

```bash
node/worker-node-01 cordoned
Warning: ignoring DaemonSet-managed Pods: calico-system/calico-node-cmkk5, calico-system/csi-node-driver-thnff, kube-system/kube-proxy-mrgvl
evicting pod default/nginx-7f8fbb96d-jjw9x
evicting pod default/nginx-7f8fbb96d-f5bqq
pod/nginx-7f8fbb96d-jjw9x evicted
pod/nginx-7f8fbb96d-f5bqq evicted
node/worker-node-01 drained
```

With only one worker, the test workload's pods have nowhere to go, because the control plane node is tainted.  They wait as `Pending` until the worker is back.

***Perform the following steps on the worker node, as `root`.***

**Reset the worker:**

```bash
kubeadm reset -f
```

**SAMPLE OUTPUT:**

```bash
[preflight] Running pre-flight checks
[reset] Deleted contents of the etcd data directory: /var/lib/etcd
W1104 14:57:39.859082    6918 removeetcdmember.go:105] [reset] No kubeadm config, using etcd pod spec to get data directory
[reset] Stopping the kubelet service
[reset] Unmounting mounted directories in "/var/lib/kubelet"
E1104 14:57:49.186499    6918 remote_runtime.go:287] "RemovePodSandbox from runtime service failed" err="rpc error: code = DeadlineExceeded desc = context deadline exceeded" podSandboxID="da44bb0c852e599a03c46672b1086d71193008b270dd7249a7810967e2d11f66"
...
[reset] Deleting contents of directories: [/etc/kubernetes/manifests /var/lib/kubelet /etc/kubernetes/pki]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]

The reset process does not perform cleanup of CNI plugin configuration,
network filtering rules and kubeconfig files.

For information on how to perform this cleanup manually, please see:
    https://k8s.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/
```

The `RemovePodSandbox` and `StopPodSandbox` errors come from pods that were still stopping when the kubelet went away.  They're harmless, and `kubeadm` cleans up anyway.

[kubernetes.io: kubeadm reset](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/)

As the message says, `kubeadm reset` leaves three things behind: the CNI configuration in `/etc/cni/net.d`, the network rules that kube-proxy wrote, and kubeconfig files.  The `kubeadm reset` docs say the network rules are fine to leave, because kube-proxy keeps them in sync when the node rejoins.  The worker has no kubeconfig file in this lab.  That leaves Calico's files.

**Remove Calico's CNI configuration, but keep the folder:**

```bash
rm -rf /etc/cni/net.d/*
```

The `kubeadm reset` docs remove the folder itself, with `rm -rf /etc/cni/net.d`.  Don't do that here: `containerd` 2.2 watches that folder and stops when it disappears.  systemd starts it again a few seconds later, but a `kubeadm join` in those few seconds fails with `could not connect to the container runtime`.  Removing what's in the folder doesn't stop `containerd`.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Delete the worker from the cluster:**

```bash
kubectl delete node worker-node-01
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
node "worker-node-01" deleted
NAME               STATUS   ROLES           AGE   VERSION
control-plane-01   Ready    control-plane   14m   v1.36.6
```

**Print a new join command:**

```bash
sudo kubeadm token create --print-join-command
```

Run the `kubeadm join` command it prints on the worker, as `root`, the same way as in [Join the Worker Nodes to the Cluster](../README.md#join-the-worker-nodes-to-the-cluster).

**Check that the worker is back:**

```bash
kubectl get nodes -o wide
kubectl get pods -o wide
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE   VERSION   INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION             CONTAINER-RUNTIME
control-plane-01   Ready    control-plane   15m   v1.36.6   192.168.122.200   <none>        Ubuntu 26.04.1 LTS   7.0.0-38-generic (amd64)   containerd://2.2.2
worker-node-01     Ready    <none>          23s   v1.36.6   192.168.122.143   <none>        Ubuntu 26.04.1 LTS   7.0.0-38-generic (amd64)   containerd://2.2.2
NAME                    READY   STATUS    RESTARTS   AGE   IP               NODE             NOMINATED NODE   READINESS GATES
nginx-7f8fbb96d-xlfzr   1/1     Running   0          85s   10.244.126.193   worker-node-01   <none>           <none>
nginx-7f8fbb96d-zv5hw   1/1     Running   0          85s   10.244.126.194   worker-node-01   <none>           <none>
```

The worker can show `Ready` while Calico's pods on it are still starting.  Give the test workload a minute before you test it.

## Reset the Whole Cluster

To redo `kubeadm init`, reset every node, workers first, and start the cluster again on the same VMs.

***Perform the following steps on each worker node, and then on the Control Plane node, as `root`.***

**Reset the node and remove Calico's CNI configuration:**

```bash
kubeadm reset -f
rm -rf /etc/cni/net.d/*
```

The workers print the same output as in the last section.  On the Control Plane node, expect a lot more errors, like these:

**SAMPLE OUTPUT EXCERPT:**

```bash
E1104 15:00:45.972580   12210 remote_runtime.go:267] "StopPodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to destroy network for sandbox \"c9574317957af6697dc457704719c87ca710614542097fb33fdf2252c4a68ef4\": plugin type=\"calico\" failed (delete): error getting ClusterInformation: Get \"https://10.96.0.1:443/apis/projectcalico.org/v3/clusterinformations/default\": dial tcp 10.96.0.1:443: connect: connection refused" podSandboxID="c9574317957af6697dc457704719c87ca710614542097fb33fdf2252c4a68ef4"
...
[reset] Deleting contents of directories: [/etc/kubernetes/manifests /var/lib/kubelet /etc/kubernetes/pki]
W1104 15:00:50.297347   12210 cleanupnode.go:105] [reset] Failed to remove containers: [failed to stop running pod c6c928b219757d29f6e3e87bb450609d5c5d12a9d3c068d3a368f2b334f40478: rpc error: code = DeadlineExceeded desc = context deadline exceeded, ...]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]
```

To tear down a pod's network, Calico asks the API server about the cluster, and the reset has just stopped the API server.  So Calico can't clean up those pods, and `kubeadm` says it couldn't remove some containers.  In testing, this didn't get in the way of the next `kubeadm init`.

**Exit the `root` shell, and remove the old kubeconfig on the Control Plane node, as `ubuntu`:**

```bash
rm -rf $HOME/.kube
```

Its credentials are for the cluster you just reset, and the README copies a new one in after `kubeadm init`.

Now start again at [Initialize the Control Plane Node](../README.md#initialize-the-control-plane-node), or use [docs/kubeadm-config.md](kubeadm-config.md) for that step, and carry on through Calico and joining the workers.  The images are already pulled, so `kubeadm init` goes faster the second time.  The new cluster is empty, so run the [test workload](../README.md#run-a-test-workload) again too.

## Snapshot the Prepared Nodes and Revert

[libvirt: virsh snapshot commands](https://www.libvirt.org/manpages/virsh.html#snapshot-commands)

A reset leaves bits of the old cluster behind: Calico's network interfaces, the old network rules, and anything the reset couldn't remove.  A libvirt snapshot gets the nodes back to exactly where they were before `kubeadm init`.  The nodes' disks are qcow2 files, which can hold snapshots inside them.

Take the snapshots right after the README's [Install the `kubeadm` Packages](../README.md#install-the-kubeadm-packages), before you pull the images and run `kubeadm init`.

***Perform the following steps on your virtualization host.***

**Shut the nodes down, and wait until they're off:**

```bash
virsh -c qemu:///system shutdown control-plane-01
virsh -c qemu:///system shutdown worker-node-01
virsh -c qemu:///system list --all
```

**SAMPLE OUTPUT EXCERPT:**

```bash
Domain 'control-plane-01' is being shutdown

Domain 'worker-node-01' is being shutdown

 Id   Name               State
-----------------------------------
 -    control-plane-01   shut off
 -    worker-node-01     shut off
```

Run `list --all` again until both show `shut off`.

**Take a snapshot of each node, then start them again:**

```bash
virsh -c qemu:///system snapshot-create-as control-plane-01 prepared --description "Nodes prepared, before kubeadm init" --atomic
virsh -c qemu:///system snapshot-create-as worker-node-01 prepared --description "Nodes prepared, before kubeadm init" --atomic
virsh -c qemu:///system snapshot-list control-plane-01
virsh -c qemu:///system start control-plane-01
virsh -c qemu:///system start worker-node-01
```

**SAMPLE OUTPUT:**

```bash
Domain snapshot prepared created
Domain snapshot prepared created
 Name       Creation Time               State
-------------------------------------------------
 prepared   2026-11-04 14:38:24 -0600   shutoff

Domain 'control-plane-01' started

Domain 'worker-node-01' started
```

Now carry on with the README.  Whenever you want to go back, revert.

**Power the nodes off, revert them to the snapshot, and start them:**

```bash
virsh -c qemu:///system destroy control-plane-01
virsh -c qemu:///system destroy worker-node-01
virsh -c qemu:///system snapshot-revert control-plane-01 prepared
virsh -c qemu:///system snapshot-revert worker-node-01 prepared
virsh -c qemu:///system start control-plane-01
virsh -c qemu:///system start worker-node-01
```

**SAMPLE OUTPUT:**

```bash
Domain 'control-plane-01' destroyed

Domain 'worker-node-01' destroyed

Domain snapshot prepared reverted

Domain snapshot prepared reverted

Domain 'control-plane-01' started

Domain 'worker-node-01' started
```

In `virsh`, `destroy` means power off.  It doesn't delete the VM or its disk.  There's no need to shut down cleanly first, because the revert throws away everything since the snapshot anyway.

Give the nodes a minute to boot, then log in again.  They kept the same IP addresses in testing.  Pick up the README at [Pull the Kubernetes Container Images on the Control Plane Node](../README.md#pull-the-kubernetes-container-images-on-the-control-plane-node), and build the cluster from there.

**When you're done with the snapshots, delete them:**

```bash
virsh -c qemu:///system snapshot-delete control-plane-01 prepared
virsh -c qemu:///system snapshot-delete worker-node-01 prepared
virsh -c qemu:///system snapshot-list worker-node-01
```

**SAMPLE OUTPUT:**

```bash
Domain snapshot prepared deleted

Domain snapshot prepared deleted

 Name   Creation Time   State
-------------------------------
```

`terraform destroy` removed the VMs with their snapshots still in place in testing, so you only need this to tidy up a lab you're keeping.

`terraform destroy` does need the nodes running.  With them shut off, it fails with `Error: Invalid index` on the module's `ip_address` output, because a stopped VM has no address to read.  Start them with `virsh -c qemu:///system start`, give them a minute, and run `terraform destroy` again.
