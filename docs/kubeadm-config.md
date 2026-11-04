# Initialize the Cluster from a kubeadm Config File

The [README](../README.md#initialize-the-control-plane-node) starts the cluster with two flags: `kubeadm init --kubernetes-version 1.36.6 --pod-network-cidr 10.244.0.0/16`.  `kubeadm` can also read its settings from a YAML file.  The file can hold settings that have no flag, such as the kubelet's own configuration, and you can keep it to build the same cluster again.  The HA control plane, coming later in 0.4.x, uses one too.

This page replaces one step: the README's [Initialize the Control Plane Node](../README.md#initialize-the-control-plane-node).  Do everything in the README before that step, run the steps below instead of the `kubeadm init` command, then carry on with [Configure `kubectl` on the Control Plane Node](../README.md#configure-kubectl-on-the-control-plane-node).  It works on every size in [`examples`](../examples).  If you already ran `kubeadm init` on these nodes, start again with fresh VMs.

During the exam you can open the [kubeadm configuration reference](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/) on kubernetes.io, so you don't need to memorize the field names.

## The Flags and the File

[kubernetes.io: Using kubeadm init with a configuration file](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/#config-file)

A config file holds one or more YAML documents, separated by `---`, and each has its own `kind`:

- `InitConfiguration` covers this node and this `kubeadm init` run: the node's name and address, its container runtime socket, and the bootstrap token that workers join with.
- `ClusterConfiguration` covers the whole cluster: the Kubernetes version, the pod and service networks, and settings for the API server, controller manager, scheduler and etcd.  `kubeadm` stores it in the cluster, and `kubeadm join` and `kubeadm upgrade` read it from there.
- `KubeletConfiguration` covers the kubelet on every node.  `kubeadm` stores it in the cluster too, and each node that joins gets it.

Here's where the README's flags go, plus one setting that has no flag:

| Flag | In the file |
| --- | --- |
| `--kubernetes-version 1.36.6` | `ClusterConfiguration`, `kubernetesVersion: 1.36.6` |
| `--pod-network-cidr 10.244.0.0/16` | `ClusterConfiguration`, `networking.podSubnet: 10.244.0.0/16` |
| `--cri-socket` (the README leaves it out, and `kubeadm` finds the runtime on its own) | `InitConfiguration`, `nodeRegistration.criSocket` |
| (no flag) | `KubeletConfiguration`, `systemReserved.memory: 256Mi` |

## See the Defaults

***Perform the following steps on the Control Plane node, as `root`.***

**Print the settings `kubeadm init` uses when you don't set them:**

```bash
kubeadm config print init-defaults
```

**SAMPLE OUTPUT:**

```bash
apiVersion: kubeadm.k8s.io/v1beta4
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 1.2.3.4
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  imagePullSerial: true
  name: node
  taints: null
timeouts:
  controlPlaneComponentHealthCheck: 4m0s
  discovery: 5m0s
  etcdAPICall: 2m0s
  kubeletHealthCheck: 4m0s
  kubernetesAPICall: 1m0s
  tlsBootstrap: 5m0s
  upgradeManifests: 5m0s
---
apiServer: {}
apiVersion: kubeadm.k8s.io/v1beta4
caCertificateValidityPeriod: 87600h0m0s
certificateValidityPeriod: 8760h0m0s
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
encryptionAlgorithm: RSA-2048
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.k8s.io
kind: ClusterConfiguration
kubernetesVersion: 1.36.0
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
proxy: {}
scheduler: {}
```

This output is a template, not a file to use as it is.  The address `1.2.3.4`, the node name `node`, and the token `abcdef.0123456789abcdef` are placeholders.  A config file only needs the settings you want to change: `kubeadm` fills in the rest, and works out the node's name and address for itself.  Add `--component-configs KubeletConfiguration` to the command to see the kubelet's defaults as well.

## Write the Config File

[kubernetes.io: Reserve Compute Resources for System Daemons](https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/)

The kubelet setting is `systemReserved`.  It holds back 256 MiB of each node's memory for the operating system, so the scheduler doesn't hand all of it to pods.  That's worth having on small nodes.

**Write the file:**

```bash
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: 1.36.6
networking:
  podSubnet: 10.244.0.0/16
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
systemReserved:
  memory: 256Mi
EOF
```

If you installed CRI-O instead of `containerd`, set `criSocket` to `unix:///var/run/crio/crio.sock`.

**Check the file:**

```bash
kubeadm config validate --config kubeadm-config.yaml
```

**SAMPLE OUTPUT:**

```bash
ok
```

`validate` catches misspelled fields and wrong API versions before you start.

## Initialize the Control Plane Node with the File

**Pull the images, then initialize the Control Plane node:**

```bash
kubeadm config images pull --config kubeadm-config.yaml
kubeadm init --config kubeadm-config.yaml
```

**SAMPLE OUTPUT EXCERPT:**

```bash
[config/images] Pulled registry.k8s.io/kube-apiserver:v1.36.6
[config/images] Pulled registry.k8s.io/kube-controller-manager:v1.36.6
[config/images] Pulled registry.k8s.io/kube-scheduler:v1.36.6
[config/images] Pulled registry.k8s.io/kube-proxy:v1.36.6
[config/images] Pulled registry.k8s.io/coredns/coredns:v1.14.2
[config/images] Pulled registry.k8s.io/pause:3.10.2
[config/images] Pulled registry.k8s.io/etcd:3.6.8-0
[init] Using Kubernetes version: v1.36.6
[preflight] Running pre-flight checks
...
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
...
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
...
Your Kubernetes control-plane has initialized successfully!
...
Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.122.9:6443 --token stvgtx.oamd83brq20vo6fu \
    --discovery-token-ca-cert-hash sha256:fc8e4f41b4127a4db7d5d7299fc337254354e9b3f810f96963d159a132ae6d14
```

The two `upload-config` and `kubelet` lines are where `kubeadm` stores the `ClusterConfiguration` and `KubeletConfiguration` in the cluster.  Save the `kubeadm join` command, as in the README.

`kubeadm init` won't take most flags alongside `--config`.  If you try, it stops before it changes anything:

```bash
kubeadm init --config kubeadm-config.yaml --pod-network-cidr 10.244.0.0/16
```

```bash
error: can not mix '--config' with arguments [pod-network-cidr]
To see the stack trace of this error execute with --v=5 or higher
```

Put the setting in the file instead.

Now go back to the README and carry on from [Configure `kubectl` on the Control Plane Node](../README.md#configure-kubectl-on-the-control-plane-node), through installing Calico and joining the workers.  The workers join with the same `kubeadm join` command as before.

## See What kubeadm Stored

With the workers joined, check that the settings from the file reached the cluster.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Read the `ClusterConfiguration` that `kubeadm` stored:**

```bash
kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}'
```

**SAMPLE OUTPUT:**

```bash
apiServer: {}
apiVersion: kubeadm.k8s.io/v1beta4
caCertificateValidityPeriod: 87600h0m0s
certificateValidityPeriod: 8760h0m0s
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
encryptionAlgorithm: RSA-2048
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.k8s.io
kind: ClusterConfiguration
kubernetesVersion: v1.36.6
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
proxy: {}
scheduler: {}
```

That's your two settings, with the defaults filled in around them.  `kubeadm join` reads this ConfigMap, and so does `kubeadm upgrade`, so the README's upgrade works the same on this cluster.  After the upgrade, `kubernetesVersion` reads `v1.37.2`.

**Check the kubelet setting, in the cluster and on the node:**

```bash
kubectl -n kube-system get configmap kubelet-config -o jsonpath='{.data.kubelet}' | grep -A1 systemReserved
sudo grep -A1 systemReserved /var/lib/kubelet/config.yaml
```

**SAMPLE OUTPUT:**

```bash
systemReserved:
  memory: 256Mi
systemReserved:
  memory: 256Mi
```

**See what it did to each node's memory:**

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,CAPACITY:.status.capacity.memory,ALLOCATABLE:.status.allocatable.memory
```

**SAMPLE OUTPUT:**

```bash
NAME               CAPACITY    ALLOCATABLE
control-plane-01   4004540Ki   3639996Ki
worker-node-01     3038656Ki   2674112Ki
```

That's from the lean size, with one worker.  Allocatable memory is what the scheduler can give to pods.  Each node's allocatable is its capacity minus the 256 MiB from `systemReserved` and the kubelet's default eviction threshold of 100 MiB.  When free memory drops below that threshold, the kubelet starts evicting pods.  The worker joined after `kubeadm init`, and it got the setting from the `kubelet-config` ConfigMap.
