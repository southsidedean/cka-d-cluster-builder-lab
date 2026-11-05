# Back Up and Restore etcd, and Renew Certificates

The CKA's cluster maintenance work includes backing up etcd, restoring it, and keeping the cluster's certificates current.  This page does all three on the lab cluster, with the commands from the Kubernetes docs:

| Task | What you do | Time in testing |
| --- | --- | --- |
| [Back up etcd](#back-up-etcd) | Take a snapshot with `etcdctl` and check it with `etcdutl` | A few seconds |
| [Restore etcd](#restore-etcd) | Delete the test workload, restore the snapshot into a new data directory, and point etcd at it | About 3 minutes, mostly the control plane settling |
| [Renew the certificates](#renew-the-certificates) | Check expiration, renew with `kubeadm`, and restart the control plane on the new certificates | About 2 minutes |

Start with a working cluster from the [README](../README.md), through [Run a Test Workload](../README.md#run-a-test-workload).  It can be before or after the upgrade.  This page works on every size in [`examples`](../examples) with one control plane node.  It was tested on `examples/single-node.tfvars` after the upgrade to 1.37, so the sample output has one node.  With three control plane nodes (`examples/ha.tfvars` and `examples/ha-lean.tfvars`), etcd has three members, and a restore has to stop every API server and restore every member; the [etcd recovery guide](https://etcd.io/docs/v3.7/op-guide/recovery/#restoring-a-cluster) has those steps.

## Install `etcdctl` and `etcdutl`

[kubernetes.io: Operating etcd clusters for Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

`kubeadm` runs etcd as a static pod, so the node doesn't have etcd's command line tools.  `etcdctl` talks to a running etcd, and takes snapshots.  `etcdutl` works on etcd's files directly, and restores snapshots.  Install the ones that match the etcd version the cluster runs.  On the exam, `etcdctl` is usually there already.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Check the etcd version:**

```bash
kubectl -n kube-system get pod etcd-control-plane-01 -o jsonpath="{.spec.containers[0].image}"; echo
```

**SAMPLE OUTPUT:**

```bash
registry.k8s.io/etcd:3.7.0-0
```

Kubernetes 1.36 runs an older etcd, so check before you download.  Use the version without the `-0`.

**Download that release from GitHub and install both tools:**

```bash
ETCD_VER=v3.7.0
curl -fsSL -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar -xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp
sudo install /tmp/etcd-${ETCD_VER}-linux-amd64/etcdctl /tmp/etcd-${ETCD_VER}-linux-amd64/etcdutl /usr/local/bin/
etcdctl version
etcdutl version
```

**SAMPLE OUTPUT:**

```bash
etcdctl version: 3.7.0
API version: 3.7
etcdutl version: 3.7.0
API version: 3.7
```

**Find etcd's address and certificates in its pod spec:**

```bash
kubectl -n kube-system describe pod etcd-control-plane-01 | grep -E -- "--(cert-file|key-file|trusted-ca-file|listen-client-urls|data-dir)"
```

**SAMPLE OUTPUT:**

```bash
      --cert-file=/etc/kubernetes/pki/etcd/server.crt
      --data-dir=/var/lib/etcd
      --key-file=/etc/kubernetes/pki/etcd/server.key
      --listen-client-urls=https://127.0.0.1:2379,https://192.168.122.35:2379
      --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
```

etcd only takes clients with a certificate from its own CA, so every `etcdctl` command below passes the CA, a certificate, and a key.  These are the paths on every `kubeadm` cluster.  The files are readable only by `root`, so the commands run with `sudo`.

**Check that `etcdctl` can reach etcd:**

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key member list -w table
```

**SAMPLE OUTPUT:**

```bash
┌──────────────────┬─────────┬──────────────────┬─────────────────────────────┬─────────────────────────────┬────────────┐
│        ID        │ STATUS  │       NAME       │         PEER ADDRS          │        CLIENT ADDRS         │ IS LEARNER │
├──────────────────┼─────────┼──────────────────┼─────────────────────────────┼─────────────────────────────┼────────────┤
│ d9c04d292348682e │ started │ control-plane-01 │ https://192.168.122.35:2380 │ https://192.168.122.35:2379 │      false │
└──────────────────┴─────────┴──────────────────┴─────────────────────────────┴─────────────────────────────┴────────────┘
```

## Back Up etcd

[kubernetes.io: Operating etcd clusters for Kubernetes, Backing up an etcd cluster](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Check what the cluster has in it now:**

```bash
kubectl get deployments,services
```

**SAMPLE OUTPUT:**

```bash
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   2/2     2            2           5m9s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   6m50s
service/nginx        ClusterIP   10.106.110.71   <none>        80/TCP    5m9s
```

**Take a snapshot:**

```bash
sudo etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /var/lib/etcd-backup.db
```

**SAMPLE OUTPUT:**

```bash
{"level":"info","ts":"2026-11-05T11:20:45.995271-0600","caller":"snapshot/v3_snapshot.go:83","msg":"created temporary db file","path":"/var/lib/etcd-backup.db.part"}
{"level":"info","ts":"2026-11-05T11:20:46.004428-0600","logger":"client","caller":"v3/maintenance.go:236","msg":"opened snapshot stream; downloading"}
{"level":"info","ts":"2026-11-05T11:20:46.008623-0600","caller":"snapshot/v3_snapshot.go:96","msg":"fetching snapshot","endpoint":"https://127.0.0.1:2379"}
{"level":"info","ts":"2026-11-05T11:20:46.229997-0600","logger":"client","caller":"v3/maintenance.go:302","msg":"completed snapshot read; closing"}
{"level":"info","ts":"2026-11-05T11:20:46.347062-0600","caller":"snapshot/v3_snapshot.go:111","msg":"fetched snapshot","endpoint":"https://127.0.0.1:2379","size":"13 MB","took":"351.682184ms","etcd-version":"3.7.0"}
{"level":"info","ts":"2026-11-05T11:20:46.347173-0600","caller":"snapshot/v3_snapshot.go:121","msg":"saved","path":"/var/lib/etcd-backup.db"}
Snapshot saved at /var/lib/etcd-backup.db
Server version 3.7.0
```

**Check the snapshot:**

```bash
sudo etcdutl --write-out=table snapshot status /var/lib/etcd-backup.db
```

**SAMPLE OUTPUT:**

```bash
┌──────────┬──────────┬────────────┬────────────┬─────────┐
│   HASH   │ REVISION │ TOTAL KEYS │ TOTAL SIZE │ VERSION │
├──────────┼──────────┼────────────┼────────────┼─────────┤
│ 979cab6c │     2869 │        890 │      13 MB │   3.7.0 │
└──────────┴──────────┴────────────┴────────────┴─────────┘
```

The snapshot is the whole cluster state: every object in every namespace.  It doesn't include the certificates in `/etc/kubernetes/pki`, so a real backup copies those too.

## Restore etcd

[kubernetes.io: Operating etcd clusters for Kubernetes, Restoring an etcd cluster](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster)

[etcd: Disaster recovery](https://etcd.io/docs/v3.7/op-guide/recovery/)

To see the restore work, delete the test workload first.  The restore brings it back.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Delete the test workload:**

```bash
kubectl delete deployment nginx && kubectl delete service nginx && kubectl get deployments,services
```

**SAMPLE OUTPUT:**

```bash
deployment.apps "nginx" deleted from default namespace
service "nginx" deleted from default namespace
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   6m53s
```

The Kubernetes docs say to stop every API server before you restore etcd, and start them again after.  The API server is a static pod, so moving its manifest out of `/etc/kubernetes/manifests` stops it.

**Stop the API server:**

```bash
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/
```

Wait a few seconds, until `kubectl` can't connect:

```bash
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
The connection to the server 192.168.122.35:6443 was refused - did you specify the right host or port?
```

**Restore the snapshot into a new data directory:**

```bash
sudo etcdutl --data-dir /var/lib/etcd-restore snapshot restore /var/lib/etcd-backup.db --bump-revision 1000000000 --mark-compacted
```

**SAMPLE OUTPUT:**

```bash
2026-11-05T11:20:49-06:00       info    snapshot/v3_snapshot.go:306     restoring snapshot      {"path": "/var/lib/etcd-backup.db", "wal-dir": "/var/lib/etcd-restore/member/wal", "data-dir": "/var/lib/etcd-restore", "snap-dir": "/var/lib/etcd-restore/member/snap", "initial-memory-map-size": 10737418240}
...
2026-11-05T11:20:49-06:00       info    schema/membership.go:125        Trimming membership information from the backend...
...
2026-11-05T11:20:50-06:00       info    snapshot/v3_snapshot.go:397     bumping latest revision {"latest-revision": 2869, "bump-amount": 1000000000, "new-latest-revision": 1000002869}
2026-11-05T11:20:50-06:00       info    snapshot/v3_snapshot.go:414     marking revision compacted      {"revision": 1000002869}
...
2026-11-05T11:20:50-06:00       info    membership/cluster.go:408       added member    {"cluster-id": "cdf818194e3a8c32", "local-member-id": "0", "added-peer-id": "8e9e05c52164694d", "added-peer-peer-urls": ["http://localhost:2380"], "added-peer-is-learner": false}
...
2026-11-05T11:20:50-06:00       info    snapshot/v3_snapshot.go:334     restored snapshot       {"path": "/var/lib/etcd-backup.db", "wal-dir": "/var/lib/etcd-restore/member/wal", "data-dir": "/var/lib/etcd-restore", "snap-dir": "/var/lib/etcd-restore/member/snap", "initial-memory-map-size": 10737418240}
```

`etcdutl` creates `/var/lib/etcd-restore`, which must not exist yet.  The two flags at the end come from etcd's recovery guide, which recommends them for Kubernetes.  They move etcd's revision counter well past where it was and mark the old revisions as gone.  Without them, the restored etcd starts at the snapshot's revision, which is lower than the revisions the kubelet, kube-proxy, and Calico have already seen, and their watches can miss changes.  In testing without the flags, every pod showed `Running`, but the `nginx` service didn't answer, and still didn't 4 minutes later.  With the flags, it answered within 2 minutes.  The Kubernetes docs' example leaves the flags out, so on the exam, use them unless the task gives you its own command.

etcd runs in its pod with its data at `/var/lib/etcd`, which is a `hostPath` volume.  To use the restored data, point that volume at the new folder.  The `--data-dir` flag stays the same, because inside the container the path doesn't change.

**Edit the etcd manifest:**

```bash
sudo vi /etc/kubernetes/manifests/etcd.yaml
```

Near the end, change the `path` of the `etcd-data` volume from `/var/lib/etcd` to `/var/lib/etcd-restore`.

**BEFORE:**

```yaml
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

**AFTER:**

```yaml
  - hostPath:
      path: /var/lib/etcd-restore
      type: DirectoryOrCreate
    name: etcd-data
```

The kubelet sees the change and restarts etcd on the restored data.

**Start the API server again, and restart the kubelet:**

```bash
sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/
sudo systemctl restart kubelet
```

The Kubernetes docs say to restart the kubelet, the scheduler, and the controller manager after a restore, so they don't use stale data, and that they "will lose leader lock and restart themselves" while the restore settles.  On a single node, the kubelet restart covers the kubelet, and the scheduler and controller manager restarted on their own in testing.

**Wait for the API server, then check that the test workload is back:**

```bash
kubectl get nodes
kubectl get deployments,services
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   7m35s   v1.37.2
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   2/2     2            2           5m53s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   7m34s
service/nginx        ClusterIP   10.106.110.71   <none>        80/TCP    5m53s
```

The `nginx` deployment and service are back, with the same cluster IP.

For a minute or two, the control plane pods restart and the cluster's state catches up.  The `nginx` pods may show `Completed`, because the kubelet stopped their containers when you deleted the deployment; the kubelet then starts them again.

**About two minutes later, check every pod:**

```bash
kubectl get pods -A
```

**SAMPLE OUTPUT:**

```bash
NAMESPACE         NAME                                       READY   STATUS    RESTARTS       AGE
calico-system     calico-kube-controllers-6b869f5589-26sqv   1/1     Running   1 (61s ago)    3m11s
calico-system     calico-node-6wm2l                          1/1     Running   0              8m8s
calico-system     calico-typha-5c5b94f69d-h956z              1/1     Running   0              3m11s
calico-system     calico-webhooks-7d655bcb48-2j8w5           1/1     Running   0              3m11s
calico-system     calico-webhooks-7d655bcb48-wz69d           1/1     Running   0              3m11s
calico-system     csi-node-driver-qjq5v                      2/2     Running   2 (97s ago)    8m8s
calico-system     goldmane-7c87b647d7-8gjvp                  1/1     Running   0              3m11s
calico-system     whisker-857c55b45c-qq5bp                   2/2     Running   0              3m11s
default           nginx-7f8fbb96d-54b5t                      1/1     Running   1 (103s ago)   3m11s
default           nginx-7f8fbb96d-5fq6c                      1/1     Running   1 (103s ago)   3m12s
kube-system       coredns-559f6c778d-l2v7m                   1/1     Running   0              3m11s
kube-system       coredns-559f6c778d-sphxp                   1/1     Running   0              3m12s
kube-system       etcd-control-plane-01                      1/1     Running   2 (96s ago)    62s
kube-system       kube-apiserver-control-plane-01            1/1     Running   2 (69s ago)    2m26s
kube-system       kube-controller-manager-control-plane-01   1/1     Running   1 (89s ago)    2m26s
kube-system       kube-proxy-ffw76                           1/1     Running   0              3m14s
kube-system       kube-scheduler-control-plane-01            1/1     Running   1 (90s ago)    2m26s
tigera-operator   tigera-operator-686489b657-d9ppc           1/1     Running   1 (90s ago)    3m12s
```

The ages come from the restored objects, so they don't line up with the restart times.

**Test the service:**

```bash
kubectl run curl --image=curlimages/curl --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}\n" http://nginx
```

**SAMPLE OUTPUT:**

```bash
200
```

### Tell `kubeadm` About the New Data Directory

[kubernetes.io: Reconfiguring a kubeadm cluster, Updating the ClusterConfiguration](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/#updating-the-clusterconfiguration)

`kubeadm` keeps the cluster's configuration in the `kubeadm-config` ConfigMap, and the next `kubeadm upgrade` writes a new etcd manifest from it.  If it still says `/var/lib/etcd`, that upgrade points etcd back at the old data.

**Check the data directory in the ConfigMap:**

```bash
kubectl -n kube-system get configmap kubeadm-config -o jsonpath="{.data.ClusterConfiguration}" | grep -A2 "etcd:"
```

**SAMPLE OUTPUT:**

```bash
etcd:
  local:
    dataDir: /var/lib/etcd
```

**Edit the ConfigMap and change `dataDir` to `/var/lib/etcd-restore`:**

```bash
kubectl -n kube-system edit configmap kubeadm-config
```

**Check it again:**

```bash
kubectl -n kube-system get configmap kubeadm-config -o jsonpath="{.data.ClusterConfiguration}" | grep -A2 "etcd:"
```

**SAMPLE OUTPUT:**

```bash
etcd:
  local:
    dataDir: /var/lib/etcd-restore
```

The old `/var/lib/etcd` is still on the node.  Once the cluster is working, you can delete it with `sudo rm -rf /var/lib/etcd`.

## Renew the Certificates

[kubernetes.io: Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

`kubeadm` makes the cluster's certificates good for one year, and its CAs good for ten.  A `kubeadm upgrade` renews them, so a cluster that's upgraded at least once a year never runs out.  This section renews them by hand.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Check when the certificates expire:**

```bash
sudo kubeadm certs check-expiration
```

**SAMPLE OUTPUT:**

```bash
[check-expiration] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[check-expiration] Use 'kubeadm init phase upload-config kubeadm --config your-config-file' to re-upload it.

CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Nov 05, 2027 17:16 UTC   364d            ca                      no      
apiserver                  Nov 05, 2027 17:16 UTC   364d            ca                      no      
apiserver-etcd-client      Nov 05, 2027 17:16 UTC   364d            etcd-ca                 no      
apiserver-kubelet-client   Nov 05, 2027 17:16 UTC   364d            ca                      no      
controller-manager.conf    Nov 05, 2027 17:16 UTC   364d            ca                      no      
etcd-healthcheck-client    Nov 05, 2027 17:16 UTC   364d            etcd-ca                 no      
etcd-peer                  Nov 05, 2027 17:16 UTC   364d            etcd-ca                 no      
etcd-server                Nov 05, 2027 17:16 UTC   364d            etcd-ca                 no      
front-proxy-client         Nov 05, 2027 17:16 UTC   364d            front-proxy-ca          no      
scheduler.conf             Nov 05, 2027 17:16 UTC   364d            ca                      no      
super-admin.conf           Nov 05, 2027 17:16 UTC   364d            ca                      no      

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Nov 02, 2036 17:13 UTC   9y              no      
etcd-ca                 Nov 02, 2036 17:13 UTC   9y              no      
front-proxy-ca          Nov 02, 2036 17:13 UTC   9y              no      
```

The certificates in this sample are from the upgrade to 1.37, a few minutes before.

**Renew all of them:**

```bash
sudo kubeadm certs renew all
```

**SAMPLE OUTPUT:**

```bash
[renew] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[renew] Use 'kubeadm init phase upload-config kubeadm --config your-config-file' to re-upload it.

certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate the apiserver uses to access etcd renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for liveness probes to healthcheck etcd renewed
certificate for etcd nodes to communicate with each other renewed
certificate for serving etcd renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed
certificate embedded in the kubeconfig file for the super-admin renewed

Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates.
```

To renew only one, name it instead of `all`, for example `sudo kubeadm certs renew apiserver`.

The control plane pods don't pick up the new certificates until they restart.  The Kubernetes docs say to move the manifests out of `/etc/kubernetes/manifests`, wait 20 seconds, which is how often the kubelet checks that folder, and move them back.

**Check when the control plane processes started:**

```bash
for p in kube-apiserver etcd kube-controller-manager kube-scheduler; do printf "%-24s " $p; ps -o lstart= -C $p; done
```

**SAMPLE OUTPUT:**

```bash
kube-apiserver           Thu Nov  5 12:03:59 2026
etcd                     Thu Nov  5 12:03:59 2026
kube-controller-manager  Thu Nov  5 12:03:56 2026
kube-scheduler           Thu Nov  5 12:03:56 2026
```

**Move the manifests out, wait 20 seconds, and move them back:**

```bash
sudo mkdir /etc/kubernetes/manifests-paused
sudo mv /etc/kubernetes/manifests/*.yaml /etc/kubernetes/manifests-paused/
sleep 20
sudo mv /etc/kubernetes/manifests-paused/*.yaml /etc/kubernetes/manifests/
sudo rmdir /etc/kubernetes/manifests-paused
```

`kubectl` can't connect while the API server is down.  After 30 seconds or so it's back.

**Check the start times again:**

```bash
for p in kube-apiserver etcd kube-controller-manager kube-scheduler; do printf "%-24s " $p; ps -o lstart= -C $p; done
```

**SAMPLE OUTPUT:**

```bash
kube-apiserver           Thu Nov  5 12:05:13 2026
etcd                     Thu Nov  5 12:05:11 2026
kube-controller-manager  Thu Nov  5 12:05:11 2026
kube-scheduler           Thu Nov  5 12:05:11 2026
```

All four started again.  `kubectl get pods` isn't a good check here: the pods keep their ages, and in testing one of them still showed 0 restarts.

`kubeadm certs renew` also renewed the certificate in `/etc/kubernetes/admin.conf`.  Your `~/.kube/config` is the copy you made in the README, with the old certificate.  It works until the old one expires, but replace it now so you don't forget.

**Copy the new admin kubeconfig:**

```bash
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   9m49s   v1.37.2
```

**Check expiration again:**

```bash
sudo kubeadm certs check-expiration
```

**SAMPLE OUTPUT:**

```bash
...
CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Nov 05, 2027 17:23 UTC   364d            ca                      no      
apiserver                  Nov 05, 2027 17:23 UTC   364d            ca                      no      
apiserver-etcd-client      Nov 05, 2027 17:23 UTC   364d            etcd-ca                 no      
apiserver-kubelet-client   Nov 05, 2027 17:23 UTC   364d            ca                      no      
controller-manager.conf    Nov 05, 2027 17:23 UTC   364d            ca                      no      
etcd-healthcheck-client    Nov 05, 2027 17:23 UTC   364d            etcd-ca                 no      
etcd-peer                  Nov 05, 2027 17:23 UTC   364d            etcd-ca                 no      
etcd-server                Nov 05, 2027 17:23 UTC   364d            etcd-ca                 no      
front-proxy-client         Nov 05, 2027 17:23 UTC   364d            front-proxy-ca          no      
scheduler.conf             Nov 05, 2027 17:23 UTC   364d            ca                      no      
super-admin.conf           Nov 05, 2027 17:23 UTC   364d            ca                      no      
...
```

Every certificate now expires a year from the renewal.  The CAs didn't change.

The kubelet's own client certificate isn't in this list.  The kubelet renews it by itself before it expires.

## Next Steps

To practice the restore again, take a new snapshot and repeat [Restore etcd](#restore-etcd) with another new data directory, such as `/var/lib/etcd-restore2`.  To start over, see [docs/practice-loop.md](practice-loop.md).
