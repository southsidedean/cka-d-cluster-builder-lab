# HA Control Plane with keepalived and HAProxy

The CKA asks you to "implement and configure a highly-available control plane."  This page builds the cluster with three control plane nodes instead of one.  Each control plane node runs its own API server and etcd member (the "stacked" etcd layout), and the cluster reaches the API servers through one virtual IP address instead of a node's own address, so it keeps working when a control plane node goes down.

Two small services provide the virtual IP, running as static pods on the control plane nodes, the way the [kubeadm guide's static pod option](https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md#option-2-run-the-services-as-static-pods) does it:

- **keepalived** gives the virtual IP, `192.168.122.250`, to one control plane node, and moves it to another if that node stops answering.
- **HAProxy** listens on port `8443` on every control plane node and passes connections to the three API servers on `6443`, skipping any that fail a health check.  It can't use `6443` itself, because the API server on the same node already does.

So the cluster's address is `https://192.168.122.250:8443`.

Use `examples/ha-lean.tfvars` (three control plane nodes with 4 GB each and one worker with 3 GB, 15 GB in all) or `examples/ha.tfvars` (two workers, 20 GB).  This page was tested on `examples/ha-lean.tfvars`, so the sample output has one worker.

[kubernetes.io: Creating Highly Available Clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)

[kubeadm: Options for Software Load Balancing](https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md#options-for-software-load-balancing)

## Keep the Virtual IP Out of libvirt's DHCP Range

libvirt's `default` network hands out `192.168.122.2` to `192.168.122.254` with DHCP.  The virtual IP has to stay outside that range, or libvirt could give it to a VM.  Shorten the range to end at `192.168.122.199`, which leaves `.200` to `.254` for addresses you assign yourself.

***Perform the following steps on your virtualization host.***

**Check the current range:**

```bash
virsh -c qemu:///system net-dumpxml default | grep range
```

**SAMPLE OUTPUT:**

```bash
      <range start='192.168.122.2' end='192.168.122.254'/>
```

**Replace it with a shorter range:**

```bash
virsh -c qemu:///system net-update default delete ip-dhcp-range "<range start='192.168.122.2' end='192.168.122.254'/>" --live --config
virsh -c qemu:///system net-update default add ip-dhcp-range "<range start='192.168.122.2' end='192.168.122.199'/>" --live --config
```

**SAMPLE OUTPUT:**

```bash
Updated network default persistent config and live state
Updated network default persistent config and live state
```

`--live` changes the running network and `--config` keeps the change after a restart.  VMs already on the network keep their addresses.  If you changed the range or the network's address before, adjust the commands to match, and pick a virtual IP outside your range.

**Check that the virtual IP isn't in use:**

```bash
ping -c 2 -W 2 192.168.122.250
```

**SAMPLE OUTPUT:**

```bash
2 packets transmitted, 0 received, 100% packet loss, time 1034ms
```

No answer means it's free.

## Build and Prepare the Nodes

**Deploy the VMs with the HA lean size:**

```bash
terraform apply -var-file=examples/ha-lean.tfvars
```

Follow the README from [Deploy the KVM Virtual Machines Using Terraform](../README.md#deploy-the-kvm-virtual-machines-using-terraform) through [Install the `kubeadm` Packages](../README.md#install-the-kubeadm-packages) on all four nodes, then come back here instead of running `kubeadm init`.

**Note the control plane nodes' addresses from `terraform output`:**

```bash
terraform output control-planes
```

It lists the three control plane nodes in the same format as the README's sample.  In the testing for this page they were `192.168.122.136`, `192.168.122.133`, and `192.168.122.31`, in that order.  Yours will be different, so use yours in the steps below.

## Configure keepalived and HAProxy

[kubeadm: keepalived configuration](https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md#keepalived-configuration)

[kubeadm: haproxy configuration](https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md#haproxy-configuration)

The files in this section are the kubeadm guide's, with its placeholders filled in.  Every control plane node gets the same files, except for two keepalived settings: `control-plane-01` starts as `MASTER` with priority `101`, so it holds the virtual IP first, and the other two are `BACKUP` with `100`.

***Perform the following steps on all three Control Plane nodes, as `root`.***

**Find the node's network interface:**

```bash
ip -br -4 addr show scope global
```

**SAMPLE OUTPUT:**

```bash
ens3             UP             192.168.122.136/24 metric 100
```

**Set the values for this node.**  Use your three control plane addresses, and on `control-plane-02` and `control-plane-03`, use `STATE=BACKUP` and `PRIORITY=100`:

```bash
INTERFACE=ens3
VIP=192.168.122.250
CP1=192.168.122.136
CP2=192.168.122.133
CP3=192.168.122.31
STATE=MASTER
PRIORITY=101
```

**Write the keepalived configuration:**

```bash
mkdir -p /etc/keepalived
cat > /etc/keepalived/keepalived.conf <<EOF
! /etc/keepalived/keepalived.conf
! Configuration File for keepalived
global_defs {
    router_id LVS_DEVEL
}
vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state $STATE
    interface $INTERFACE
    virtual_router_id 51
    priority $PRIORITY
    authentication {
        auth_type PASS
        auth_pass 42
    }
    virtual_ipaddress {
        $VIP
    }
    track_script {
        check_apiserver
    }
}
EOF
```

`virtual_router_id` has to match on all three nodes and be different from any other keepalived group on the network.

**Write keepalived's health check, which checks the API server through HAProxy:**

```bash
cat > /etc/keepalived/check_apiserver.sh <<'EOF'
#!/bin/sh

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl -sfk --max-time 2 https://localhost:8443/healthz -o /dev/null || errorExit "Error GET https://localhost:8443/healthz"
EOF
chmod +x /etc/keepalived/check_apiserver.sh
```

The check goes through this node's HAProxy, so it fails when HAProxy is down or can't reach any API server.  Then keepalived lowers the node's priority by 2, and a backup with a higher priority takes the virtual IP.

**Write the HAProxy configuration:**

```bash
mkdir -p /etc/haproxy
cat > /etc/haproxy/haproxy.cfg <<EOF
# /etc/haproxy/haproxy.cfg
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log stdout format raw local0
    daemon

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 1
    timeout http-request    10s
    timeout queue           20s
    timeout connect         5s
    timeout client          35s
    timeout server          35s
    timeout http-keep-alive 10s
    timeout check           10s

#---------------------------------------------------------------------
# apiserver frontend which proxies to the control plane nodes
#---------------------------------------------------------------------
frontend apiserver
    bind *:8443
    mode tcp
    option tcplog
    default_backend apiserverbackend

#---------------------------------------------------------------------
# round robin balancing for apiserver
#---------------------------------------------------------------------
backend apiserverbackend
    option httpchk

    http-check connect ssl
    http-check send meth GET uri /healthz
    http-check expect status 200

    mode tcp
    balance     roundrobin

    server control-plane-01 $CP1:6443 check verify none
    server control-plane-02 $CP2:6443 check verify none
    server control-plane-03 $CP3:6443 check verify none
EOF
```

**Write the two static pod manifests:**

```bash
mkdir -p /etc/kubernetes/manifests
cat > /etc/kubernetes/manifests/keepalived.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  name: keepalived
  namespace: kube-system
spec:
  containers:
  - image: osixia/keepalived:2.0.20
    name: keepalived
    resources: {}
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_BROADCAST
        - NET_RAW
    volumeMounts:
    - mountPath: /usr/local/etc/keepalived/keepalived.conf
      name: config
    - mountPath: /etc/keepalived/check_apiserver.sh
      name: check
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/keepalived/keepalived.conf
    name: config
  - hostPath:
      path: /etc/keepalived/check_apiserver.sh
    name: check
status: {}
EOF
cat > /etc/kubernetes/manifests/haproxy.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: haproxy
  namespace: kube-system
spec:
  containers:
  - image: haproxy:2.8
    name: haproxy
    livenessProbe:
      failureThreshold: 8
      httpGet:
        host: localhost
        path: /healthz
        port: 8443
        scheme: HTTPS
    volumeMounts:
    - mountPath: /usr/local/etc/haproxy/haproxy.cfg
      name: haproxyconf
      readOnly: true
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/haproxy/haproxy.cfg
      type: FileOrCreate
    name: haproxyconf
status: {}
EOF
ls /etc/kubernetes/manifests
```

**SAMPLE OUTPUT:**

```bash
haproxy.yaml
keepalived.yaml
```

Nothing runs yet.  The kubelet doesn't start static pods until `kubeadm init` or `kubeadm join` gives it a configuration, so keepalived and HAProxy start along with the rest of the control plane.

## Initialize the First Control Plane Node

***Perform the following steps on `control-plane-01`, as `root`.***

Compared with the README's `kubeadm init`, two flags are new:

- `--control-plane-endpoint 192.168.122.250:8443` puts the virtual IP and HAProxy's port in every kubeconfig and join command, instead of this node's address.
- `--upload-certs` stores the control plane's certificates in the cluster, encrypted, so the other control plane nodes can download them when they join.

**Initialize the cluster:**

```bash
kubeadm init --kubernetes-version 1.36.6 --control-plane-endpoint 192.168.122.250:8443 --upload-certs --pod-network-cidr 10.244.0.0/16
```

**SAMPLE OUTPUT EXCERPT:**

```bash
...
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes running the following command on each as root:

  kubeadm join 192.168.122.250:8443 --token f2sk9f.oy9aov7dmqvvoigr \
        --discovery-token-ca-cert-hash sha256:c89d931303df4867a545743b155829156c27c4f82b5f5057ba59050727474678 \
        --control-plane --certificate-key ea31556bdcd6875167acd742fd899d4a40316449f4395683504c8e704ec669d4

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.122.250:8443 --token f2sk9f.oy9aov7dmqvvoigr \
        --discovery-token-ca-cert-hash sha256:c89d931303df4867a545743b155829156c27c4f82b5f5057ba59050727474678
```

There are two join commands now: the first, with `--control-plane --certificate-key`, is for control plane nodes, and the second is for workers.  Both go through the virtual IP.  Save them.

Configure `kubectl` for `ubuntu` as in [Configure `kubectl` on the Control Plane Node](../README.md#configure-kubectl-on-the-control-plane-node).  The kubeconfig now points at the virtual IP:

```bash
grep server: /home/ubuntu/.kube/config
```

**SAMPLE OUTPUT:**

```bash
    server: https://192.168.122.250:8443
```

***Perform the following steps on `control-plane-01`, as `ubuntu`.***

`kubectl` needs keepalived to have taken the virtual IP.  In testing that happened between a few seconds and a minute after `kubeadm init` finished.  Until then, `kubectl` fails with `connect: no route to host`.

**Wait for the virtual IP on `ens3`:**

```bash
ip -br -4 addr show ens3
```

**SAMPLE OUTPUT:**

```bash
ens3             UP             192.168.122.136/24 metric 100 192.168.122.250/32
```

**Check the control plane pods:**

```bash
kubectl -n kube-system get pods -o wide
```

**SAMPLE OUTPUT:**

```bash
NAME                                       READY   STATUS    RESTARTS   AGE   IP                NODE               NOMINATED NODE   READINESS GATES
coredns-589f44dc88-pz447                   0/1     Pending   0          6s    <none>            <none>             <none>           <none>
coredns-589f44dc88-r9t4h                   0/1     Pending   0          6s    <none>            <none>             <none>           <none>
etcd-control-plane-01                      0/1     Running   0          14s   192.168.122.136   control-plane-01   <none>           <none>
haproxy-control-plane-01                   1/1     Running   0          14s   192.168.122.136   control-plane-01   <none>           <none>
keepalived-control-plane-01                1/1     Running   0          14s   192.168.122.136   control-plane-01   <none>           <none>
kube-apiserver-control-plane-01            0/1     Running   0          14s   192.168.122.136   control-plane-01   <none>           <none>
kube-controller-manager-control-plane-01   0/1     Running   0          14s   192.168.122.136   control-plane-01   <none>           <none>
kube-proxy-cphtn                           1/1     Running   0          6s    192.168.122.136   control-plane-01   <none>           <none>
kube-scheduler-control-plane-01            0/1     Running   0          14s   192.168.122.136   control-plane-01   <none>           <none>
```

`haproxy` and `keepalived` run beside the other control plane pods.

Now install Calico, as in [Deploy the Calico Networking CNI](../README.md#deploy-the-calico-networking-cni), and wait for `control-plane-01` to be `Ready`.

## Join the Other Control Plane Nodes

***Perform the following step on `control-plane-02`, then on `control-plane-03`, as `root`.***

**Run the control plane join command from `kubeadm init`:**

```bash
kubeadm join 192.168.122.250:8443 --token f2sk9f.oy9aov7dmqvvoigr \
        --discovery-token-ca-cert-hash sha256:c89d931303df4867a545743b155829156c27c4f82b5f5057ba59050727474678 \
        --control-plane --certificate-key ea31556bdcd6875167acd742fd899d4a40316449f4395683504c8e704ec669d4
```

**SAMPLE OUTPUT EXCERPT:**

```bash
...
* Certificate signing request was sent to apiserver and approval was received.
* The Kubelet was informed of the new secure connection details.
* Control plane label and taint were applied to the new node.
* The Kubernetes control plane instances scaled up.
* A new etcd member was added to the local/stacked etcd cluster.

To start administering your cluster from this node, you need to run the following as a regular user:

        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config

Run 'kubectl get nodes' to see this node join the cluster.
```

The token lasts 24 hours and the uploaded certificates 2 hours.  If either has run out, make a new control plane join command on `control-plane-01`, as `root`:

```bash
echo "$(kubeadm token create --print-join-command) --control-plane --certificate-key $(kubeadm init phase upload-certs --upload-certs | tail -1)"
```

Configure `kubectl` for `ubuntu` on `control-plane-02` and `control-plane-03` too, with the commands from the join output.  You'll use it from `control-plane-02` when `control-plane-01` is down.

***Perform the following steps on `control-plane-01`, as `ubuntu`.***

**Check the nodes:**

```bash
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   4m36s   v1.36.6
control-plane-02   Ready    control-plane   2m2s    v1.36.6
control-plane-03   Ready    control-plane   47s     v1.36.6
```

**Check that etcd has three members:**

```bash
kubectl -n kube-system exec etcd-control-plane-01 -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key member list -w table
```

**SAMPLE OUTPUT:**

```bash
+------------------+---------+------------------+------------------------------+------------------------------+------------+
|        ID        | STATUS  |       NAME       |          PEER ADDRS          |         CLIENT ADDRS         | IS LEARNER |
+------------------+---------+------------------+------------------------------+------------------------------+------------+
|  113e006a5cf22ff | started | control-plane-03 |  https://192.168.122.31:2380 |  https://192.168.122.31:2379 |      false |
| f5882a397f7c7c77 | started | control-plane-01 | https://192.168.122.136:2380 | https://192.168.122.136:2379 |      false |
| f659fb01d798538c | started | control-plane-02 | https://192.168.122.133:2380 | https://192.168.122.133:2379 |      false |
+------------------+---------+------------------+------------------------------+------------------------------+------------+
```

The etcd image includes `etcdctl`, so `kubectl exec` can run it without installing anything on the node.  Three members can lose one and keep a majority.

## Join the Worker and Spread CoreDNS

***Perform the following step on the worker node, as `root`.***

**Run the worker join command from `kubeadm init`:**

```bash
kubeadm join 192.168.122.250:8443 --token f2sk9f.oy9aov7dmqvvoigr \
        --discovery-token-ca-cert-hash sha256:c89d931303df4867a545743b155829156c27c4f82b5f5057ba59050727474678
```

Then check the nodes as in [Confirm the Worker Nodes Joined the Cluster](../README.md#confirm-the-worker-nodes-joined-the-cluster).

CoreDNS started when `control-plane-01` was the only node, so both of its pods are there.  If that node goes down, so does the cluster's DNS.  Restarting the deployment lets the scheduler spread them.

***Perform the following steps on `control-plane-01`, as `ubuntu`.***

**Restart CoreDNS:**

```bash
kubectl -n kube-system rollout restart deployment coredns
kubectl -n kube-system rollout status deployment coredns
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
```

**SAMPLE OUTPUT:**

```bash
deployment.apps/coredns restarted
Waiting for deployment spec update to be observed...
...
deployment "coredns" successfully rolled out
NAME                       READY   STATUS        RESTARTS   AGE     IP               NODE               NOMINATED NODE   READINESS GATES
coredns-589f44dc88-r9t4h   1/1     Terminating   0          5m39s   10.244.173.198   control-plane-01   <none>           <none>
coredns-6b9569bf9b-fm9nc   1/1     Running       0          7s      10.244.126.194   worker-node-01     <none>           <none>
coredns-6b9569bf9b-p7dcl   1/1     Running       0          6s      10.244.39.130    control-plane-02   <none>           <none>
```

Then run the README's [test workload](../README.md#run-a-test-workload).

## Take Down the Node with the Virtual IP

Now shut down the node that holds the virtual IP, and check that the cluster keeps working.

***Perform the following step on `control-plane-01`, as `ubuntu`.***

**Check that `control-plane-01` holds the virtual IP:**

```bash
ip -br -4 addr show ens3
```

**SAMPLE OUTPUT:**

```bash
ens3             UP             192.168.122.136/24 metric 100 192.168.122.250/32
```

***Perform the following step on your virtualization host.***

**Shut it down:**

```bash
virsh -c qemu:///system shutdown control-plane-01
```

**SAMPLE OUTPUT:**

```bash
Domain 'control-plane-01' is being shutdown
```

***Perform the following steps on `control-plane-02`, as `ubuntu`.***

In testing, a backup took the virtual IP within a second of `control-plane-01` shutting off.  The two backups have the same priority, so either can take it.

**Check which node has it:**

```bash
ip -br -4 addr show ens3
```

**SAMPLE OUTPUT:**

```bash
ens3             UP             192.168.122.133/24 metric 100 192.168.122.250/32
```

If it isn't here, it's on `control-plane-03`.

**Use the cluster through the virtual IP:**

```bash
kubectl get nodes
kubectl get pods -o wide
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   6m29s   v1.36.6
control-plane-02   Ready    control-plane   3m55s   v1.36.6
control-plane-03   Ready    control-plane   2m40s   v1.36.6
worker-node-01     Ready    <none>          107s    v1.36.6
NAME                    READY   STATUS    RESTARTS   AGE   IP               NODE             NOMINATED NODE   READINESS GATES
nginx-7f8fbb96d-jkxsd   1/1     Running   0          40s   10.244.126.195   worker-node-01   <none>           <none>
nginx-7f8fbb96d-lh6x2   1/1     Running   0          40s   10.244.126.196   worker-node-01   <none>           <none>
```

`control-plane-01` still shows `Ready` right after the shutdown.  It changes to `NotReady` once Kubernetes notices it stopped reporting.

**Check etcd's health:**

```bash
kubectl -n kube-system exec etcd-control-plane-02 -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint health --cluster -w table
```

**SAMPLE OUTPUT:**

```bash
+------------------------------+--------+--------------+---------------------------+
|           ENDPOINT           | HEALTH |     TOOK     |           ERROR           |
+------------------------------+--------+--------------+---------------------------+
| https://192.168.122.133:2379 |   true |  13.628657ms |                           |
|  https://192.168.122.31:2379 |   true |  20.080421ms |                           |
| https://192.168.122.136:2379 |  false | 5.004165613s | context deadline exceeded |
+------------------------------+--------+--------------+---------------------------+
```

`etcdctl` also prints a retry warning before the table, and `Error: unhealthy cluster` after it, because one member is down.  Two of three are healthy, which is a majority, so etcd keeps working.

**Test the workload:**

```bash
kubectl run curl --image=curlimages/curl --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}\n" http://nginx
```

**SAMPLE OUTPUT:**

```bash
000
```

In testing, the `nginx` service's cluster IP answered the whole time, but looking it up by name failed for about the first minute after the shutdown: `000` from `curl`, or `no servers could be reached` from `nslookup`.  A minute later, the same command returned `200`.  If you see `000`, wait a minute and run it again.

***Perform the following step on your virtualization host.***

**The virtual IP answers from outside the cluster too:**

```bash
curl -k https://192.168.122.250:8443/livez; echo
```

**SAMPLE OUTPUT:**

```bash
ok
```

**Start `control-plane-01` again:**

```bash
virsh -c qemu:///system start control-plane-01
```

Once it's back, keepalived on `control-plane-01` takes the virtual IP back, because its priority is higher.  In testing, it held the virtual IP again within a minute of starting, and its pods restarted once.

## Upgrade the HA Cluster

[kubernetes.io: Upgrading kubeadm clusters, Upgrading control plane nodes](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/#upgrading-control-plane-nodes)

The README's [Upgrade the Cluster from 1.36 to 1.37](../README.md#upgrade-the-cluster-from-136-to-137) works on this cluster, with one change: only `control-plane-01` runs `kubeadm upgrade apply`.  Upgrade the nodes one at a time:

1. `control-plane-01`: the README's control plane steps, with `kubeadm upgrade apply v1.37.2`.
2. `control-plane-02`, then `control-plane-03`: the same steps, but with `kubeadm upgrade node` in place of `kubeadm upgrade plan` and `kubeadm upgrade apply`.
3. The worker: the README's worker steps.

Drain and uncordon each node from any control plane node.  When `control-plane-01` restarts its kubelet, its static pods restart too, and while it holds the virtual IP, `kubectl` can fail for a few seconds with `TLS handshake timeout`.  Run it again.

**SAMPLE OUTPUT EXCERPT** from `kubeadm upgrade node` on `control-plane-02`:

```bash
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
[upgrade/addon] Skipping upgrade of addons because control plane instances [control-plane-03] have not been upgraded
```

**SAMPLE OUTPUT EXCERPT** from `kubeadm upgrade node` on `control-plane-03`:

```bash
[upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
[addons] Applied essential addon: CoreDNS
W1105 13:13:41.579903   13884 endpoint.go:56] [endpoint] WARNING: port specified in controlPlaneEndpoint overrides bindPort in the controlplane address
[addons] Applied essential addon: kube-proxy
```

`kubeadm` upgrades CoreDNS and kube-proxy only once every control plane node is on the new version, so the last control plane node does it.  The warning is about the virtual IP's port `8443` being different from the API server's `6443`, which is what we want.

**Check the cluster after the upgrade:**

```bash
kubectl get nodes
kubectl -n kube-system get pods | grep -E "keepalived|haproxy"
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE   VERSION
control-plane-01   Ready    control-plane   21m   v1.37.2
control-plane-02   Ready    control-plane   18m   v1.37.2
control-plane-03   Ready    control-plane   17m   v1.37.2
worker-node-01     Ready    <none>          16m   v1.37.2
haproxy-control-plane-01                   1/1     Running   0               9m31s
haproxy-control-plane-02                   1/1     Running   0               5m3s
haproxy-control-plane-03                   1/1     Running   1 (63s ago)     45s
keepalived-control-plane-01                1/1     Running   0               9m31s
keepalived-control-plane-02                1/1     Running   0               5m3s
keepalived-control-plane-03                1/1     Running   1 (63s ago)     45s
```

`kubeadm upgrade` leaves the keepalived and HAProxy manifests alone, since it only manages its own.

## Undo the DHCP Change

When you're done with the HA cluster, destroy it as in [Tear Down the KVM Virtual Machines Using Terraform](../README.md#tear-down-the-kvm-virtual-machines-using-terraform), with `-var-file=examples/ha-lean.tfvars`.  The shorter DHCP range doesn't affect the other sizes, so you can keep it.  To put the original range back:

***Perform the following steps on your virtualization host.***

```bash
virsh -c qemu:///system net-update default delete ip-dhcp-range "<range start='192.168.122.2' end='192.168.122.199'/>" --live --config
virsh -c qemu:///system net-update default add ip-dhcp-range "<range start='192.168.122.2' end='192.168.122.254'/>" --live --config
```
