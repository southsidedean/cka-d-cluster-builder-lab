<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/cka-d-logo-dark.svg">
    <img src="images/cka-d-logo.svg" alt="cka-d-cluster-builder-lab logo: a control plane node linked to two worker nodes" width="128">
  </picture>
</p>

# cka-d-cluster-builder-lab

**Tom Dean - 10/10/2023, refreshed 10/2026**

Build a `kubeadm` practice cluster for the CKA and CKAD exams on your own KVM host: Terraform creates the nodes, and this walkthrough takes you from bare VMs to a working cluster, then through an upgrade.

> **Tested in 0.3.0** on an Ubuntu 24.04 host with Terraform 1.17.1, libvirt provider 0.8.3, and the VM module 1.12.0: Ubuntu 26.04 nodes, Kubernetes 1.36.6 upgraded to 1.37.2, `containerd` 2.2.2 (or CRI-O 1.36.7 to 1.37.2), and Calico 3.33.0. The Terraform part was also tested on Rocky Linux 9.8 and 10.2 hosts in 0.2.1. [CHANGELOG.md](CHANGELOG.md) has what changed in each release.

## Introduction

### The Need: A Quick and Repeatable Local Kubernetes Cluster Using KVM

I've been studying for the Cloud Native Computing Foundation's CKA and CKAD certification exams for a while now.  Anyone who is familiar with these exams knows that, in order to practice, you're going to need a cluster.  Hands-on experience with Kubernetes clusters, of the `kubeadm` variety, is key to passing these exams.

For the past year and a half, I've had access to an AWS environment, with a GitLab repository, flashy CI/CD and Terraform/Packer to deliver one or more pre-provisioned Kubernetes environments for me to teach Kubernetes to students, or to practice Kubernetes solo.

Now that I'm out on my own, and that fancy AWS lab environment is a thing of the past, I've been imagining a replacement of my own.

I had a few requirements:

- Keep the code in GitLab for development and personal use
  - Use CI/CD: Adding this after the initial release
    - Working this out in my GitLab environment in my home lab
  - Periodically push the updated code to GitHub to share with the world
- Use Terraform for automation
  - Flexibility in configuration of cluster via variables
- Leverage KVM/libvirt
  - Execute workloads locally
  - Avoid Cloud expenses
- Keep the project simple and straightforward
  - Iterate as needed
- Build something I can use with the CNCF CKA/D courses
  - Test and evaluate cluster build process/scripts
    - LFS258 (CKA)
    - LFD259 (CKAD)

***So, how do we get from here to there?***

### The Solution: Terraform Module for KVM/Libvirt Virtual Machines

During my research for this project, I stumbled across the [Terraform Module for KVM/Libvirt Virtual Machines](https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/latest).

**From the Hashicorp Terraform Registry:**

"What it provides

- creates one or more VMs
- one NIC per domain, connected to the network using the bridge interface
- setup network interface using DHCP or static configuration
- cloud_init VM(s) configuration (Ubuntu+Netplan complient)
- optionally add multiple extra disks
- test the ssh connection"

***Sounds good to me!***

So, by using one invocation of the module for Control Plane hosts, and one for Worker nodes, we can build a flexible cluster configuration that we can configure for clusters of varying sizes and node counts.

***So, how will we implement this?***

### The Details: A Single-File Terraform Solution

[Terraform code](cka-builder.tf)

I like to K.I.S.S. (Keep It Simple, Stupid!) whenever possible, and this was a case where I could put everything into a single file.  Yeah, yeah, yeah, why all the variables when we could just set them down in the module?  Because, I like to separate the input from the machinery.

You can change all kinds of things in the variables at the top of `cka-builder.tf`:

| Variable | Default | What it sets |
|---|---|---|
| `control_plane_nodes`, `worker_nodes` | `1`, `2` | How many nodes of each kind (at least one of each) |
| `cp_prefix`, `worker_prefix` | `control-plane-`, `worker-node-` | Hostname prefixes; nodes are numbered from `01` |
| `cp_cpu`, `worker_cpu` | `2` | vCPUs per node |
| `cp_memory`, `worker_memory` | `8192` | Memory per node, in MB |
| `cp_disk`, `worker_disk` | `25` | Disk per node, in GB |
| `cp_diskpool`, `worker_diskpool` | `default` | The libvirt storage pool for the node disks |
| `privateuser`, `privatekey`, `pubkey` | `ubuntu`, `~/.ssh/id_ed25519`, `~/.ssh/id_ed25519.pub` | The login user and the SSH key Terraform puts on every node |
| `timezone` | `America/Chicago` | The nodes' time zone, a name from `timedatectl list-timezones` |
| `osimg` | Ubuntu 26.04 cloud image | The image every node starts from |
| `graphics` | `vnc` | The VM console type. RHEL 9 and later dropped SPICE, and VNC works everywhere |

Below the variables, the `libvirt` provider is pinned to 0.8.x (0.9 is a rewrite the VM module doesn't support), and the module is called twice: once for the control plane nodes and once for the workers.

### What You Need

- A Linux host with KVM: Ubuntu 24.04, or RHEL, Rocky Linux, or AlmaLinux 9 or 10. Check that the CPU's virtualization extensions are on with `grep -cE 'vmx|svm' /proc/cpuinfo` (anything above `0` is fine).
- Enough room for the nodes. The defaults (one control plane and two workers, each with 2 vCPUs and 8 GB of memory) need 6 vCPUs and 24 GB of memory free, and the disks used about 13 GB once the cluster was built. You can make the nodes smaller in the variables, but `kubeadm` wants at least 2 vCPUs and 2 GB of memory per node.
- Internet access from the nodes, for packages and container images.
- An SSH key pair at `~/.ssh/id_ed25519`, or change `privatekey` and `pubkey`.

## References

[GitHub: cka-d-cluster-builder-lab](https://github.com/southsidedean/cka-d-cluster-builder-lab)

[Terraform code](cka-builder.tf)

[Hashicorp Terraform Registry: Terraform Module for KVM/Libvirt Virtual Machines](https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/latest)

[GitHub: MonolithProjects/terraform-libvirt-vm](https://github.com/MonolithProjects/terraform-libvirt-vm/tree/1.12.0)

[Hashicorp Terraform Registry: Libvirt Provider](https://registry.terraform.io/providers/dmacvicar/libvirt/0.8.3/docs)

[kubernetes.io: Bootstrapping clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)

[kubernetes.io: Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

[kubernetes.io: Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

[kubernetes.io: Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)

[kubernetes.io: Changing the Kubernetes package repository](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/)

[GitHub: CRI-O packages](https://github.com/cri-o/packaging/blob/main/README.md)

[tigera.io: Install Calico networking and network policy for on-premises deployments](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

## Prerequisites

Before we get started, we're going to need to confirm that we have some things installed and configured.

### Terraform

[Hashicorp: Install Terraform](https://developer.hashicorp.com/terraform/install)

I've written quite a bit of infrastructure-as-code in Terraform, using AWS, for lab environments and projects in the past, so I decided to try my hand with Terraform + KVM/`libvirt` to provide IaC automation for my projects.

To install, add HashiCorp's package repository for your distribution, as described in the link above, then install the `terraform` package.

**You can verify your installation by checking the version of Terraform:**

```bash
terraform version
```

**SAMPLE OUTPUT:**

```bash
Terraform v1.17.1
on linux_amd64
```

***Ok, Terraform is good to go.  Let's check KVM.***

### KVM / `libvirt`

[Ubuntu: libvirt](https://ubuntu.com/server/docs/virtualization-libvirt)

[libvirt documentation](https://libvirt.org/docs.html)

At the bottom of the stack, our foundation, is `libvirt`.  We're going to use it to run the virtual machines Terraform builds.

**Ubuntu:**

```bash
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst
sudo usermod -aG libvirt,kvm $USER
```

**RHEL, Rocky Linux, or AlmaLinux 9 and 10:**

```bash
sudo dnf install -y qemu-kvm libvirt virt-install
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
```

Log out and back in so the new group takes effect.

**Once you have KVM/`libvirt` installed, let's give it a test:**

```bash
virsh -c qemu:///system list --all
```

***We shouldn't see any virtual machines at this point, unless you have some running already, of course.***

### `mkisofs` and `xsltproc`

The libvirt provider builds each node's cloud-init disk with `mkisofs`, and the VM module uses `xsltproc` to adjust each VM's definition. Install both before you run Terraform.

**Ubuntu:**

```bash
sudo apt-get install -y genisoimage xsltproc
```

**RHEL, Rocky Linux, or AlmaLinux 9 and 10** (`xorriso` provides `mkisofs` there):

```bash
sudo dnf install -y xorriso libxslt
```

### KVM: The `default` `libvirt` Network

The nodes use libvirt's `default` NAT network, and it works as installed: the nodes get `192.168.122.x` addresses from libvirt's DHCP, and they can reach each other and the internet.

**Check that the `default` network is active and starts on boot:**

```bash
virsh -c qemu:///system net-list --all
```

**SAMPLE OUTPUT:**

```bash
 Name      State    Autostart   Persistent
--------------------------------------------
 default   active   yes         yes
```

If it isn't active, start it with `virsh -c qemu:///system net-start default` and `virsh -c qemu:///system net-autostart default`.

The 2023 version of this lab moved the network to `10.0.1.0/24`, because Calico's default pod network is `192.168.0.0/16`, which overlaps libvirt's `192.168.122.0/24`.  This version gives the pods `10.244.0.0/16` when we initialize the cluster instead, so the stock network is fine.  If you do change it with `virsh net-edit default`, keep it clear of `10.244.0.0/16` (pods) and `10.96.0.0/12` (services).

**If the network won't start on a host that also runs a DNS server** (`dnsmasq: failed to create listening socket for 192.168.122.1: Address already in use` in the `libvirtd` log), that DNS server is listening on every address, including libvirt's bridge.  With BIND, for example, keep it off the bridge in `/etc/bind/named.conf.options` with `listen-on { !192.168.122.0/24; any; };`, restart it, and start the network.

***Okay, our virtual network is ready.  What next?***

### KVM: The `default` `libvirt` Storage Pool

You're going to need a storage pool for your virtual machines.  The Terraform file uses the `default` storage pool, and you can change it in the variables if you want to use a different pool.

**Check for the `default` storage pool:**

```bash
virsh -c qemu:///system pool-list --all
```

**If there isn't one, create it.** This puts it in libvirt's usual folder; use any folder with enough space:

```bash
virsh -c qemu:///system pool-define-as default dir --target /var/lib/libvirt/images
virsh -c qemu:///system pool-build default
virsh -c qemu:///system pool-start default
virsh -c qemu:///system pool-autostart default
```

**SAMPLE OUTPUT** (`pool-list` afterward):

```bash
 Name      State    Autostart
-------------------------------
 default   active   yes
```

**Ubuntu with a storage pool outside `/var/lib/libvirt/images`:** AppArmor only lets QEMU read VM images from libvirt's own folders, so the VMs fail to start with "Permission denied" on the `-base.qcow2` image. Allow your pool's folder (here `/media/content/virtual-machines`) with a local rule:

```bash
sudo mkdir -p /etc/apparmor.d/local/abstractions
echo '/media/content/virtual-machines/** rwk,' | sudo tee /etc/apparmor.d/local/abstractions/libvirt-qemu
sudo systemctl reload apparmor
```

RHEL, Rocky Linux, and AlmaLinux use SELinux instead, and a pool in `/var/lib/libvirt/images` needs no change there.

***Now that you have everything installed and configured, let's get the code!***

### Git Clone the `cka-d-cluster-builder-lab` Code

**Clone the repository and change into it:**

```bash
git clone https://github.com/southsidedean/cka-d-cluster-builder-lab.git
cd cka-d-cluster-builder-lab
```

To use a specific release instead of the latest code, check out its tag, for example `git checkout v0.3.0`.

[Terraform code](cka-builder.tf)

By default, a cluster will be created with a single control plane node and two worker nodes.  Feel free to adjust the values in the variables as you see fit.

***Ok, we're all ready to start deploying a cluster.  Let's go!***

## Deploy the KVM Virtual Machines Using Terraform

Ok, let's deploy some nodes!

**First, we need to initialize our Terraform environment:**

```bash
terraform init
```

**SAMPLE OUTPUT EXCERPT:**

```bash
Initializing modules...
Downloading registry.terraform.io/MonolithProjects/vm/libvirt 1.12.0 for worker...
- worker in .terraform/modules/worker
Downloading registry.terraform.io/MonolithProjects/vm/libvirt 1.12.0 for controlplane...
- controlplane in .terraform/modules/controlplane

Initializing provider plugins...
- Finding dmacvicar/libvirt versions matching ">= 0.7.0, ~> 0.8.3"...
- Installing dmacvicar/libvirt v0.8.3...
- Installed dmacvicar/libvirt v0.8.3 (self-signed, key ID 0833E38C51E74D26)
...
Terraform has been successfully initialized!
```

**Next, let's generate a Terraform plan:**

```bash
terraform plan -out cka-plan.plan
```

**SAMPLE OUTPUT EXCERPT:**

```bash
...
Plan: 11 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + control-planes = {
      + ip_address = [
          + (known after apply),
        ]
      + name       = [
          + "control-plane-01",
        ]
    }
  + worker-nodes   = {
      + ip_address = [
          + (known after apply),
          + (known after apply),
        ]
      + name       = [
          + "worker-node-01",
          + "worker-node-02",
        ]
    }

Saved the plan to: cka-plan.plan
```

This will show us what Terraform is going to build, and will validate our code for errors.  With no errors, let's proceed with a `terraform apply`.

**Deploy the nodes:**

```bash
terraform apply cka-plan.plan
```

Terraform downloads the Ubuntu image, builds a disk and a cloud-init disk for each node, starts the VMs, and waits until it can log in to each one.

**SAMPLE OUTPUT EXCERPT:**

```bash
...
module.worker.libvirt_domain.virt-machine[0] (remote-exec): Virtual Machine worker-node-01 is UP!
module.worker.libvirt_domain.virt-machine[0]: Creation complete after 48s [id=dda66c0b-d69a-4f26-8bf2-6693207713db]
module.controlplane.libvirt_domain.virt-machine[0] (remote-exec): Virtual Machine control-plane-01 is UP!
module.controlplane.libvirt_domain.virt-machine[0]: Creation complete after 49s [id=4c99a48e-1f83-48f3-aa81-96d2dc5a7b71]
module.worker.libvirt_domain.virt-machine[1] (remote-exec): Virtual Machine worker-node-02 is UP!
module.worker.libvirt_domain.virt-machine[1]: Creation complete after 49s [id=31689208-e599-46d4-996b-eb24e1a2034b]

Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

control-planes = {
  "ip_address" = [
    "192.168.122.189",
  ]
  "name" = [
    "control-plane-01",
  ]
}
worker-nodes = {
  "ip_address" = [
    "192.168.122.32",
    "192.168.122.144",
  ]
  "name" = [
    "worker-node-01",
    "worker-node-02",
  ]
}
```

The outputs list each node's IP address.  Run `terraform output` any time to see them again.

**If `terraform apply` fails partway,** the provider can leave the VMs defined in libvirt, and the next apply stops with "domain ... already exists". Run `terraform destroy`, then remove the leftovers with `virsh -c qemu:///system undefine <name>` (`virsh -c qemu:///system list --all` shows them) before you try again.

**Let's check our system for virtual machines:**

```bash
virsh -c qemu:///system list --all
```

**SAMPLE OUTPUT:**

```bash
 Id   Name               State
-----------------------------------
 4    worker-node-02     running
 5    worker-node-01     running
 6    control-plane-01   running
```

***Our three nodes are ready!  Let's build a Kubernetes cluster!***

## Deploy a Kubernetes Cluster on Our KVM Virtual Machines (Nodes)

To get started, we're going to log into each of our nodes with a separate connection (window/tab/etc), and become the `root` user.  Use the addresses from `terraform output`.

**Log in to each node using SSH:**

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<NODE_IP_ADDRESS>
```

**Become the `root` user on all nodes:**

```bash
sudo -i
```

### Prepare the Nodes

[kubernetes.io: Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

***Perform the following steps on all nodes.***

**Load the `overlay` and `br_netfilter` modules, now and at every boot:**

```bash
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
lsmod | grep -E "overlay|br_netfilter"
```

**SAMPLE OUTPUT:**

```bash
overlay
br_netfilter
br_netfilter           32768  0
bridge                425984  1 br_netfilter
overlay               233472  0
```

**Configure kernel parameters for bridging and IPv4 forwarding:**

```bash
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

**SAMPLE OUTPUT:**

```bash
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

The Ubuntu cloud image has no swap, which `kubeadm` requires, so there's nothing to turn off.

### Install the `containerd` Runtime

When deploying a Kubernetes cluster, you have choices with regard to your container runtime.  We'll use `containerd`, which Ubuntu 26.04 packages itself.  If you'd rather use CRI-O, skip this section and follow [OPTIONAL: Use the CRI-O Runtime Instead](#optional-use-the-cri-o-runtime-instead), then come back to [Install the `kubeadm` Packages](#install-the-kubeadm-packages).

***Perform the following steps on all nodes.***

**Install `containerd` and write out its default configuration:**

```bash
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
```

The kubelet uses the `systemd` cgroup driver, and `containerd` has to match it.  The default configuration says `SystemdCgroup = false`.

**Switch `containerd` to the `systemd` cgroup driver and restart it:**

```bash
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep SystemdCgroup /etc/containerd/config.toml
systemctl restart containerd
systemctl is-active containerd
containerd --version
```

**SAMPLE OUTPUT:**

```bash
            SystemdCgroup = true
active
containerd github.com/containerd/containerd/v2 2.2.2
```

***Sweet, we have a container runtime installed!  What's next?***

### Install the `kubeadm` Packages

[kubernetes.io: Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

Kubernetes packages come from `pkgs.k8s.io`, which has a separate repository for each minor version.  We'll install 1.36, so that we can practice upgrading to 1.37 later, the way the CKA exam expects.

***Perform the following steps on all nodes.***

**Install prerequisites and add the Kubernetes 1.36 repository:**

```bash
apt-get install -y apt-transport-https ca-certificates curl gpg
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
```

**Let's see which versions of Kubernetes 1.36 are available:**

```bash
apt-get update
apt-cache madison kubeadm
```

**SAMPLE OUTPUT:**

```bash
   kubeadm | 1.36.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
   kubeadm | 1.36.5-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
   kubeadm | 1.36.4-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
   kubeadm | 1.36.3-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
   kubeadm | 1.36.2-2.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
   kubeadm | 1.36.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
   kubeadm | 1.36.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
```

We'll install the newest one, 1.36.6 at the time of writing.  Use the newest version your list shows, here and in the `kubeadm` commands below.

**Install the Kubernetes packages and lock their versions:**

```bash
K8S_VERSION=1.36.6-1.1
apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet
```

**SAMPLE OUTPUT EXCERPT:**

```bash
kubelet set on hold.
kubeadm set on hold.
kubectl set on hold.
```

The kubelet restarts every few seconds until `kubeadm` configures it.  That's expected.

#### Pull the Kubernetes Container Images on the Control Plane Node

***Perform the following step on the Control Plane node.***

```bash
kubeadm config images pull --kubernetes-version 1.36.6
```

**SAMPLE OUTPUT:**

```bash
[config/images] Pulled registry.k8s.io/kube-apiserver:v1.36.6
[config/images] Pulled registry.k8s.io/kube-controller-manager:v1.36.6
[config/images] Pulled registry.k8s.io/kube-scheduler:v1.36.6
[config/images] Pulled registry.k8s.io/kube-proxy:v1.36.6
[config/images] Pulled registry.k8s.io/coredns/coredns:v1.14.2
[config/images] Pulled registry.k8s.io/pause:3.10.2
[config/images] Pulled registry.k8s.io/etcd:3.6.8-0
```

***All the Linux work is done!  We can proceed to doing the Kubernetes things!***

## Deploy a Kubernetes Cluster Using `kubeadm`

[kubernetes.io: Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

Now, we're going to use `kubeadm` to configure and deploy Kubernetes on the nodes we've set up.

### Initialize the Control Plane Node

***Perform the following steps on the Control Plane node, still as `root`.***

`--pod-network-cidr` gives the pods their own address range, `10.244.0.0/16`, away from the nodes' `192.168.122.0/24`.  Calico picks it up from `kubeadm` automatically.

**Initialize the Control Plane node:**

```bash
kubeadm init --kubernetes-version 1.36.6 --pod-network-cidr 10.244.0.0/16
```

**SAMPLE OUTPUT EXCERPT:**

```bash
[init] Using Kubernetes version: v1.36.6
[preflight] Running pre-flight checks
...
[certs] apiserver serving cert is signed for DNS names [control-plane-01 kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 192.168.122.171]
...
[control-plane-check] kube-scheduler is healthy after 4.131731ms
[control-plane-check] kube-controller-manager is healthy after 8.49546ms
[control-plane-check] kube-apiserver is healthy after 2.50316737s
...
[addons] Applied essential addon: CoreDNS
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

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.122.171:6443 --token yj34yd.0jo818naam72d1r6 \
    --discovery-token-ca-cert-hash sha256:d71403662f6e7749fc0c11c7d2b65bb397fbef0bab6990448938f33a16a13591
```

Save the `kubeadm join` command from your output.  You'll need it for the worker nodes.

### Configure `kubectl` on the Control Plane Node

**Exit the `root` shell, then configure `kubectl` as the `ubuntu` user:**

```bash
exit
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Checking our work:**

```bash
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS     ROLES           AGE   VERSION
control-plane-01   NotReady   control-plane   17s   v1.36.6
```

***We're going to need to install a networking provider to get things working.***

### Deploy the Calico Networking CNI

[tigera.io: Install Calico networking and network policy for on-premises deployments](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

***Perform the following steps on the Control Plane node.***

**Download and deploy the Calico CNI manifest:**

```bash
curl -sSO https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
kubectl apply -f calico.yaml
```

If we wanted to customize our Calico deployment, we could edit the `calico.yaml` manifest.  We're going to use it as-is.

**SAMPLE OUTPUT EXCERPT:**

```bash
poddisruptionbudget.policy/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
serviceaccount/calico-node created
serviceaccount/calico-cni-plugin created
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
...
daemonset.apps/calico-node created
deployment.apps/calico-kube-controllers created
```

**Wait for the Control Plane node to become `Ready`:**

```bash
kubectl wait --for=condition=Ready node/control-plane-01 --timeout=300s
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
node/control-plane-01 condition met
NAME               STATUS   ROLES           AGE   VERSION
control-plane-01   Ready    control-plane   42s   v1.36.6
```

***Ok, we have a functional Control Plane!***

### Join the Worker Nodes to the Cluster

Now that we have a functional Control Plane, we can join the worker nodes to the cluster.  Use the `join` command that you saved when you initialized the Control Plane.

**If you can't find the join command, print a new one on the Control Plane node:**

```bash
sudo kubeadm token create --print-join-command
```

***Perform the following step on each worker node, as `root`.***

```bash
kubeadm join ...  <-- FILL THIS IN WITH YOUR JOIN COMMAND
```

**SAMPLE OUTPUT EXCERPT:**

```bash
[preflight] Running pre-flight checks
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
...
[kubelet-check] The kubelet is healthy after 509.733734ms
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

You may also see a warning that the recommended `bindAddress` for kube-proxy is `::`.  It's harmless on this IPv4-only network.

### Confirm the Worker Nodes Joined the Cluster

***Perform the following steps on the Control Plane node.***

**Wait until all the nodes are `Ready`:**

```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o wide
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE    VERSION   INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION             CONTAINER-RUNTIME
control-plane-01   Ready    control-plane   118s   v1.36.6   192.168.122.171   <none>        Ubuntu 26.04.1 LTS   7.0.0-38-generic (amd64)   containerd://2.2.2
worker-node-01     Ready    <none>          66s    v1.36.6   192.168.122.228   <none>        Ubuntu 26.04.1 LTS   7.0.0-38-generic (amd64)   containerd://2.2.2
worker-node-02     Ready    <none>          60s    v1.36.6   192.168.122.22    <none>        Ubuntu 26.04.1 LTS   7.0.0-38-generic (amd64)   containerd://2.2.2
```

**Taking a look at the pods in our cluster:**

```bash
kubectl get pods -A
```

**SAMPLE OUTPUT:**

```bash
NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-6ffffbccff-z58dm   1/1     Running   0          2m3s
kube-system   calico-node-68tcz                          1/1     Running   0          92s
kube-system   calico-node-mmsq8                          1/1     Running   0          2m3s
kube-system   calico-node-xblhv                          1/1     Running   0          97s
kube-system   coredns-589f44dc88-282rx                   1/1     Running   0          2m3s
kube-system   coredns-589f44dc88-zcvs5                   1/1     Running   0          2m3s
kube-system   etcd-control-plane-01                      1/1     Running   0          2m10s
kube-system   kube-apiserver-control-plane-01            1/1     Running   0          2m10s
kube-system   kube-controller-manager-control-plane-01   1/1     Running   0          2m10s
kube-system   kube-proxy-2wvwh                           1/1     Running   0          2m3s
kube-system   kube-proxy-8l8sc                           1/1     Running   0          97s
kube-system   kube-proxy-znfqj                           1/1     Running   0          92s
kube-system   kube-scheduler-control-plane-01            1/1     Running   0          2m10s
```

The `calico-node` pods on the workers can take a minute to finish starting.  `kubectl wait --for=condition=Ready pods --all -n kube-system` waits for all of them.

### Run a Test Workload

**Deploy two `nginx` pods behind a Service, then reach the Service from another pod:**

```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --port 80
kubectl rollout status deployment nginx
kubectl get pods -o wide
kubectl run curl --image=curlimages/curl --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}\n" http://nginx
```

**SAMPLE OUTPUT EXCERPT:**

```bash
deployment "nginx" successfully rolled out
NAME                    READY   STATUS    RESTARTS   AGE   IP               NODE             NOMINATED NODE   READINESS GATES
nginx-7f8fbb96d-fljjf   1/1     Running   0          9s    10.244.2.129     worker-node-02   <none>           <none>
nginx-7f8fbb96d-kjjvk   1/1     Running   0          9s    10.244.126.193   worker-node-01   <none>           <none>
...
200
pod "curl" deleted from default namespace
```

A `200` means pod networking, the Service, and cluster DNS all work.

***There you have it!  A Kubernetes cluster, assembled with `kubeadm`.***

## Upgrade the Cluster from 1.36 to 1.37

[kubernetes.io: Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)

Upgrading one minor version at a time is part of the CKA.  The order is: the Control Plane first, then each worker, one at a time.  On every node, `kubeadm` goes first, then the node is drained and the kubelet and `kubectl` are upgraded.

Because `pkgs.k8s.io` has a repository per minor version, each node also has to switch its repository from `v1.36` to `v1.37`.  Without that, `apt-cache madison kubeadm` only ever shows 1.36 versions.

### Upgrade the Control Plane Node

***Perform the following steps on the Control Plane node, as `root`.***

**Switch to the Kubernetes 1.37 repository:**

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sed -i 's/v1.36/v1.37/' /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm
```

**SAMPLE OUTPUT:**

```bash
   kubeadm | 1.37.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
   kubeadm | 1.37.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
   kubeadm | 1.37.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
```

**Upgrade `kubeadm`, then check the upgrade plan:**

```bash
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.37.2-1.1
apt-mark hold kubeadm
kubeadm upgrade plan
```

**SAMPLE OUTPUT EXCERPT:**

```bash
[upgrade/versions] Cluster version: 1.36.6
[upgrade/versions] kubeadm version: v1.37.2
[upgrade/versions] Target version: v1.37.2
[upgrade/versions] Latest version in the v1.36 series: v1.36.6

Components that must be upgraded manually after you have upgraded the control plane with 'kubeadm upgrade apply':
COMPONENT   NODE               CURRENT   TARGET
kubelet     control-plane-01   v1.36.6   v1.37.2
kubelet     worker-node-01     v1.36.6   v1.37.2
kubelet     worker-node-02     v1.36.6   v1.37.2

Upgrade to the latest stable version:

COMPONENT                 NODE               CURRENT   TARGET
kube-apiserver            control-plane-01   v1.36.6   v1.37.2
kube-controller-manager   control-plane-01   v1.36.6   v1.37.2
kube-scheduler            control-plane-01   v1.36.6   v1.37.2
kube-proxy                                   1.36.6    v1.37.2
CoreDNS                                      v1.14.2   v1.14.6
etcd                      control-plane-01   3.6.8-0   3.7.0-0

You can now apply the upgrade by executing the following command:

    kubeadm upgrade apply v1.37.2
```

**Apply the upgrade:**

```bash
kubeadm upgrade apply v1.37.2
```

It asks you to confirm, then upgrades etcd and the control plane components one at a time.  It takes a few minutes.

**SAMPLE OUTPUT EXCERPT:**

```bash
[upgrade/staticpods] Component "etcd" upgraded successfully!
...
[upgrade/staticpods] Component "kube-apiserver" upgraded successfully!
...
[upgrade/staticpods] Component "kube-controller-manager" upgraded successfully!
...
[upgrade/staticpods] Component "kube-scheduler" upgraded successfully!
[upgrade/control-plane] The control plane instance for this node was successfully upgraded!
...
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

[upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.37.2".
```

You may see an `Unexpected error when reading response body` line while etcd restarts.  `kubeadm` retries and carries on.

**Drain the node, upgrade the kubelet and `kubectl`, and restart the kubelet:**

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf drain control-plane-01 --ignore-daemonsets
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
```

**SAMPLE OUTPUT EXCERPT:**

```bash
node/control-plane-01 cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/calico-node-g4hf6, kube-system/kube-proxy-g957r
evicting pod kube-system/coredns-589f44dc88-c7hs4
evicting pod kube-system/calico-kube-controllers-6ffffbccff-9mdt2
evicting pod kube-system/coredns-589f44dc88-99mvr
...
node/control-plane-01 drained
```

Restarting the kubelet briefly restarts the API server.  If the next command says `The connection to the server ... was refused`, wait a few seconds and try again.

**Bring the node back into service:**

```bash
kubectl --kubeconfig /etc/kubernetes/admin.conf uncordon control-plane-01
kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes
```

**SAMPLE OUTPUT:**

```bash
node/control-plane-01 uncordoned
NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   7m24s   v1.37.2
worker-node-01     Ready    <none>          6m32s   v1.36.6
worker-node-02     Ready    <none>          6m26s   v1.36.6
```

### Upgrade the Worker Nodes

Do one worker at a time, so the cluster always has somewhere to run your pods.

***On the worker node, as `root`:*** switch the repository, upgrade `kubeadm`, and upgrade the node's configuration.

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sed -i 's/v1.36/v1.37/' /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.37.2-1.1
apt-mark hold kubeadm
kubeadm upgrade node
```

**SAMPLE OUTPUT EXCERPT:**

```bash
[upgrade/preflight] Running pre-flight checks
[upgrade/preflight] Skipping prepull. Not a control plane node.
...
[upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
[upgrade/addon] Skipping the addon/coredns phase. Not a control plane node.
[upgrade/addon] Skipping the addon/kube-proxy phase. Not a control plane node.
```

***On the Control Plane node, as `ubuntu`:*** drain the worker.

```bash
kubectl drain worker-node-01 --ignore-daemonsets
```

**SAMPLE OUTPUT:**

```bash
node/worker-node-01 cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/calico-node-bcnq5, kube-system/kube-proxy-n6ts9
evicting pod kube-system/coredns-559f6c778d-m5jh9
evicting pod default/nginx-7f8fbb96d-kjjvk
pod/nginx-7f8fbb96d-kjjvk evicted
pod/coredns-559f6c778d-m5jh9 evicted
node/worker-node-01 drained
```

***On the worker node, as `root`:*** upgrade the kubelet and `kubectl`, and restart the kubelet.

```bash
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
```

***On the Control Plane node, as `ubuntu`:*** bring the worker back.

```bash
kubectl uncordon worker-node-01
```

Then do the same for `worker-node-02`.

### Confirm the Upgrade

```bash
kubectl get nodes
kubectl run curl --image=curlimages/curl --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}\n" http://nginx
```

**SAMPLE OUTPUT EXCERPT:**

```bash
NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   9m12s   v1.37.2
worker-node-01     Ready    <none>          8m20s   v1.37.2
worker-node-02     Ready    <none>          8m14s   v1.37.2
...
200
```

***Every node is on 1.37, and the test workload kept working through the upgrade.***

## OPTIONAL: Use the CRI-O Runtime Instead

[GitHub: CRI-O packages](https://github.com/cri-o/packaging/blob/main/README.md)

CRI-O is a container runtime built only for Kubernetes.  Use it in place of `containerd`: on fresh nodes, follow [Prepare the Nodes](#prepare-the-nodes), then this section instead of [Install the `containerd` Runtime](#install-the-containerd-runtime), then carry on from [Install the `kubeadm` Packages](#install-the-kubeadm-packages).  Everything after that is the same, with one addition during the upgrade.

***Perform the following steps on all nodes, as `root`.***

CRI-O's versions track Kubernetes, with a repository per minor version, so we'll use CRI-O 1.36 with Kubernetes 1.36.

**Add the CRI-O 1.36 repository and install CRI-O:**

```bash
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v1.36/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v1.36/deb/ /' | tee /etc/apt/sources.list.d/cri-o.list
apt-get update
apt-get install -y cri-o
systemctl enable --now crio
systemctl is-active crio
crio --version | head -1
```

**SAMPLE OUTPUT EXCERPT:**

```bash
active
crio version 1.36.7
```

CRI-O uses the `systemd` cgroup driver out of the box, so there's nothing to configure.  When the nodes join, `kubectl get nodes -o wide` shows `cri-o://1.36.7` as the runtime.

**During the upgrade,** switch the CRI-O repository along with the Kubernetes one, and upgrade CRI-O with the kubelet.  On each node, as `root`, add these to the repository step:

```bash
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v1.37/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
sed -i 's/v1.36/v1.37/' /etc/apt/sources.list.d/cri-o.list
```

Then, after draining the node, upgrade and restart CRI-O together with the kubelet:

```bash
apt-mark unhold kubelet kubectl
apt-get install -y cri-o kubelet=1.37.2-1.1 kubectl=1.37.2-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart crio kubelet
```

**SAMPLE OUTPUT** (`kubectl get nodes -o wide`, after the upgrade, trimmed):

```bash
NAME               STATUS   ROLES           AGE   VERSION   ...   CONTAINER-RUNTIME
control-plane-01   Ready    control-plane   10m   v1.37.2   ...   cri-o://1.37.2
worker-node-01     Ready    <none>          10m   v1.37.2   ...   cri-o://1.37.2
worker-node-02     Ready    <none>          10m   v1.37.2   ...   cri-o://1.37.2
```

## OPTIONAL: Configure `kubectl` on Your Virtualization Host

You might want to manage your cluster using `kubectl` on your virtualization host.  This is a common use case scenario that is easy to implement.

If you don't have `kubectl` installed on your virtualization host, install it now.

**Copy the `kubeconfig` to the KVM host:**

```bash
scp -i ~/.ssh/id_ed25519 ubuntu@<CONTROL_PLANE_IP>:~/.kube/config control-plane-01.conf
export KUBECONFIG=$PWD/control-plane-01.conf
```

If you want to get totally fancy and create a context for it, feel free to indulge your fancy.  I'm keeping things on-point here and not going down that rabbit hole.

**Checking our work:**

```bash
kubectl get nodes
```

**SAMPLE OUTPUT:**

```bash
NAME               STATUS   ROLES           AGE   VERSION
control-plane-01   Ready    control-plane   11m   v1.37.2
worker-node-01     Ready    <none>          11m   v1.37.2
worker-node-02     Ready    <none>          11m   v1.37.2
```

When you're done with the cluster, you can `unset KUBECONFIG` to stop using the configuration.

## Tear Down the KVM Virtual Machines Using Terraform

When you're done with the cluster, use `terraform destroy` to tear it down.

**Destroy the nodes:**

```bash
terraform destroy -auto-approve
```

**SAMPLE OUTPUT EXCERPT:**

```bash
...
module.controlplane.libvirt_volume.base-volume-qcow2[0]: Destroying... [id=/media/content/virtual-machines/control-plane--base.qcow2]
module.worker.libvirt_volume.volume-qcow2[0]: Destruction complete after 1s
module.worker.libvirt_volume.volume-qcow2[1]: Destruction complete after 2s
module.worker.libvirt_cloudinit_disk.commoninit[0]: Destruction complete after 2s
module.worker.libvirt_volume.base-volume-qcow2[0]: Destroying... [id=/media/content/virtual-machines/worker-node--base.qcow2]
module.controlplane.libvirt_volume.base-volume-qcow2[0]: Destruction complete after 2s
module.worker.libvirt_volume.base-volume-qcow2[0]: Destruction complete after 0s

Destroy complete! Resources: 11 destroyed.
```

**Checking our work:**

```bash
virsh -c qemu:///system list --all
```

***Our cluster resources have been destroyed.  All cleaned up!***

Run `terraform apply` again any time you want a fresh set of nodes to practice on.

## Summary

By leveraging the [Terraform Module for KVM/Libvirt Virtual Machines](https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/latest), we can build a set of nodes on a KVM hypervisor, in a quick and repeatable way, which is perfect for getting hands-on with Kubernetes clusters.  Using the materials in this repository, you can customize the Terraform for your needs and use cases, build a cluster with `kubeadm`, and practice upgrading it.

*Enjoy!*

**Tom Dean**
