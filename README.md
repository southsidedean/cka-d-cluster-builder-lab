# cka-d-cluster-builder-lab
**Tom Dean - 10/10/2023**

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

[Terraform code](cka-test.tf)

I like to K.I.S.S. (Keep It Simple, Stupid!) whenever possible, and this was a case where I could put everything into a single file.  Yeah, yeah, yeah, why all the variables when we could just set them down in the module?  Because, I like to separate the input from the machinery.

You can change all kinds of things in the variables.

**Node count, by node type:**
```bash
# Cluster sizing: minimum one of each!
# We can set the number of control plane and worker nodes here

variable "control_plane_nodes" {
  type = number
  default = 1
}

variable "worker_nodes" {
  type = number
  default = 2
}
```

**Node name prefix, by node type:**
```bash
# Hostname prefixes
# This controls how the hostnames are generated

variable "cp_prefix" {
  type = string
  default = "control-plane-"
}

variable "worker_prefix" {
  type = string
  default = "worker-node-"
}
```

**Node sizing, by node type:**
```bash
# Node sizing
# Start with the control planes

variable "cp_cpu" {
  type = number
  default = 2
}

variable "cp_disk" {
  type = number
  default = 25
}

variable "cp_memory" {
  type = number
  default = 8192
}

# On to the worker nodes

variable "worker_cpu" {
  type = number
  default = 2
}

variable "worker_disk" {
  type = number
  default = 25
}

variable "worker_memory" {
  type = number
  default = 8192
}
```

**Disk pool, by node type:**
```bash
# Disk Pool to use
# Control Plane

variable "cp_diskpool" {
  type = string
  default = "default"
}

# Worker Nodes

variable "worker_diskpool" {
  type = string
  default = "default"
}
```

**User/Key information, all nodes:**
```bash
# User / Key information
# Same across all nodes, customize if you wish

variable "privateuser" {
  type = string
  default = "ubuntu"
}

variable "privatekey" {
  type = string
  default = "~/.ssh/id_ed25519"
}

variable "pubkey" {
  type = string
  default = "~/.ssh/id_ed25519.pub"
}
```

**Other information, all nodes:**
```bash
# Other node configuration

variable "timezone" {
  type = string
  default = "CST"
}

variable "osimg" {
  type = string
  default = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}
```

Feel free to customize as needed.  The virtual machine sizing is based on the requirements for the CNCF LFD259 course, but you might be able to tighten things up on disk and memory and run an acceptable cluster.  Alternatively, if you want to build clusters with more nodes, go for it, if you have the resources!

How does it work?  The rest is the stuff you should never have to touch, just use the variables to change the configuration.

**Configuring the Terraform provider:**
```bash
# Set our Terraform provider here
# We're going to use libvirt on our local machine

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

**Build everything and report the details:**
```bash
# Module for building our control plane nodes

module "controlplane" {
  source  = "MonolithProjects/vm/libvirt"
  version = "1.10.0"

  vm_hostname_prefix = var.cp_prefix
  vm_count    = var.control_plane_nodes
  memory      = var.cp_memory
  vcpu        = var.cp_cpu
  pool        = var.cp_diskpool
  system_volume = var.cp_disk
  dhcp        = true
  ssh_admin   = var.privateuser
  ssh_private_key = var.privatekey
  ssh_keys    = [
    file(var.pubkey),
    ]
  time_zone   = var.timezone
  os_img_url  = var.osimg
}

# Module for building our worker nodes

module "worker" {
  source  = "MonolithProjects/vm/libvirt"
  version = "1.10.0"

  vm_hostname_prefix = var.worker_prefix
  vm_count    = var.worker_nodes
  memory      = var.worker_memory
  vcpu        = var.worker_cpu
  pool        = var.worker_diskpool
  system_volume = var.worker_disk
  dhcp        = true
  ssh_admin   = var.privateuser
  ssh_private_key = var.privatekey
  ssh_keys    = [
    file(var.pubkey),
    ]
  time_zone   = var.timezone
  os_img_url  = var.osimg
}

output "control-planes" {
  value = module.controlplane
}

output "worker-nodes" {
  value = module.worker
}
```

### Hardware Details: Lab in a Box Server

I have a **Dell Precision T5500** workstation sitting under my desk, which I recently upgraded:

- Ubuntu 22.04
- Dual six-core Xeons
- Plenty of storage
    - RAID-1 SSD for system: 250GB
    - RAID-1 HDD for data: 6TB
- Dual 1GB network connections
    - Public/General network
    - Private/Data/Application Network
- 72GB of RAM
- Decent GPU, possible future use?

The workstation was already up and running with Ubuntu 22.04, serving as my "Lab in a Box" server:

- GitLab: *Keep it local!*
    - Place to do primary development
        - Release projects/content on GitHub
    - Local GitLab instance
    - Publically accessible (*by me*)
    - CI/CD
        - KVM/`libvirt` runner
- Terraform
    - Write automation for labs and projects
    - Execute workloads on KVM/`libvirt`
- Packer
    - Create images for projects
    - Also use `virt-builder` and Image Builder as needed
- Ansible
    - Might use in future projects, or for lab infrastructure
- Cockpit
    - Web-based server information and management
    - For when you want to treat your "lab in the box" as an appliance and skip the CLI

Terraform and KVM/`libvirt` are already installed and configured on my server.  All I needed to do was to enable `dnsmasq` and change the subnet on the `default` KVM network.

***Adding the CKA/D Cluster Builder functionality should be rather straightforward.  Let's see how we do it!***

## References

[GitHub: cka-d-cluster-builder-lab](https://github.com/southsidedean/cka-d-cluster-builder-lab)

[Terraform code](cka-test.tf)

[GitHub: self-hosted-gitlab-libvirt](https://github.com/southsidedean/self-hosted-gitlab-libvirt)

[Hashicorp Terraform Registry: Terraform Module for KVM/Libvirt Virtual Machines](https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/latest)

[GitHub: dmacvicar/terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)

[GitHub: MonolithProjects/terraform-libvirt-vm](https://github.com/MonolithProjects/terraform-libvirt-vm/tree/1.10.0)

[Hashicorp Terraform Registry: Libvirt Provider](https://registry.terraform.io/providers/multani/libvirt/latest/docs)

[kubernetes.io: Bootstrapping clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)

[kubernetes.io: Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

[GitHub: CRI-O Installation Instructions](https://github.com/cri-o/cri-o/blob/main/install.md#readme)

[Docker: Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

[kubernetes.io: Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

[tigera.io: Install Calico networking and network policy for on-premises deployments](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

## Prerequisites

Before we get started, we're going to need to confirm that we have some things installed and configured.

### Terraform

[Hashicorp: Official Packaging Guide](https://www.hashicorp.com/official-packaging-guide)

[Install Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

I've written quite a bit of infrastructure-as-code in Terraform, using AWS, for lab environments and projects in the past, so I decided to try my hand with Terraform + KVM/`libvirt` to provide IaC automation for my projects.

To install, you first need to add the repositories for Hashicorp, as described in the link above.  Follow the steps for your operating system.  Once the repositiories have been added, you can install Terraform as instructed in the links above.

**You can verify your installation by checking the version of Terraform:**
```
terraform --version

```

You should get the installed version of Terraform back.

***Ok, Terraform is good to go.  Let's check KVM.***

### KVM / `libvirt`

[Ubuntu: libvirt](https://ubuntu.com/server/docs/virtualization-libvirt)

[How To Install KVM Hypervisor on Ubuntu 22.04|20.04](https://computingforgeeks.com/install-kvm-hypervisor-on-ubuntu-linux/)

[Red Hat: Getting started with virtualization](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_virtualization/getting-started-with-virtualization-in-rhel-8_configuring-and-managing-virtualization#enabling-virtualization-in-rhel8_virt-getting-started)

[Creating a Directory-based Storage Pool with virsh](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/virtualization_administration_guide/sect-virtualization-storage_pools-creating-local_directories-virsh)

At the bottom of the "Lab in a Box" stack, our foundation, is `libvirt`.  We're going to use it to execute our Terraform workloads.

The exact set of steps required to install the KVM/`libvirt` components will vary, based on your Linux distribution.  I've included links for Ubuntu and RHEL variants above, but you should be able to Google it and get instructions.  Remember, make sure you can install GitLab on your distribution as well.  If you're using some obscure distribution, you might be out of luck.

**Once you have KVM/`libvirt` installed, let's give it a test:**
```bash
virsh --help | more

```

You should get help for the `virsh` command-line utility, which is what we use to manage our virtual machine environment.

**Let's check our system for virtual machines:**
```bash
virsh list --all

```

***We shouldn't see any virtual machines at this point, unless you have some running already, of course.  We can move on to configuring our `default` `libvirt` network.***

### KVM: Configure `default` `libvirt` Network

In order for our cluster to work, we need proper name resolution on our `default` bridge network.  We can accomplish this by configuring `dnsmasq` on our `default` bridge network.

**Let's take a look at our `default` bridge network:**
```bash
virsh net-dumpxml default

```

I'm going to show you my 'finished' network configuration below.

**EXAMPLE OUTPUT:**
```bash
<network>
  <name>default</name>
  <uuid>1157d479-7b7b-4c4e-b005-989d13067393</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:06:61:f9'/>
  <domain name='k8s.local' localOnly='yes'/>
  <ip address='10.0.1.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.0.1.2' end='10.0.1.254'/>
    </dhcp>
  </ip>
</network>
```

**My network has the following changes from a 'stock' implementation with `libvirt`:**

- I've changed the network from `192.168.122.0` to `10.0.1.0`, which is not in use on my network.  The requirements for the CKA/D environments for the CNCF CKA/D courses specifies to NOT use the `192.168` network for nodes.
- I've enabled `dnsmasq`, with the line `<domain name='k8s.local' localOnly='yes'/>`
  - Local domain is `k8s.local`

*If you need to edit your network, use the following process.  Use the example configuration above as a guide.*

**Take down the `default` network:**
```bash
virsh net-destroy default

```

**Edit the `default` network:**
```bash
virsh net-edit default

```

*Make your edits as needed.*

**Deploy the new `default` network configuration:**
```bash
virsh net-start default

```

*I would do this without any virtual machines deployed to the `default` network.*

**Again, if you want to do one final check of your `default` network configuration:**
```bash
virsh net-dumpxml default

```

***Okay, our virtual network is configured.  What next?***

### KVM: Configure `default` `libvirt` Storage Pool

[Creating a Directory-based Storage Pool with virsh](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/virtualization_administration_guide/sect-virtualization-storage_pools-creating-local_directories-virsh)

You're going to need a storage pool for your virtual machines.  The Terraform file is configured to use the `default` storage pool by default.  You can change it in the variables if you want to use a different pool.

If you need to create a storage pool, reference [Creating a Directory-based Storage Pool with virsh](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/virtualization_administration_guide/sect-virtualization-storage_pools-creating-local_directories-virsh).  It'll get you up and running in no time.

**Check for the `default` storage pool:**
```bash
virsh pool-list

```

If you have one or more storage pools configured, you will see them in the output.

**SAMPLE OUTPUT:**
```bash
 Name      State    Autostart
-------------------------------
 default   active   yes
 images    active   yes
```

**Checking the `default` storage pool configuration:**
```bash
virsh pool-dumpxml default
```

**SAMPLE OUTPUT:**
```bash
<pool type='dir'>
  <name>default</name>
  <uuid>16e25a71-f1f5-4a15-bad7-b8224ce22a38</uuid>
  <capacity unit='bytes'>494427144192</capacity>
  <allocation unit='bytes'>28672</allocation>
  <available unit='bytes'>494427115520</available>
  <source>
  </source>
  <target>
    <path>/media/virtual-machines</path>
    <permissions>
      <mode>0775</mode>
      <owner>1000</owner>
      <group>141</group>
    </permissions>
  </target>
</pool>
```

You can see that I've configured my `default` storage pool as a directory-based pool, that is backed by a LVM volume mounted at `/media/virtual-machines`:
```bash
Filesystem                                  Size  Used Avail Use% Mounted on
/dev/mapper/monolith_data-virtual_machines  461G   28K  438G   1% /media/virtual-machines
```

***Now that you have everything installed and configured, let's get the code!***

### Git Clone the `cka-d-cluster-builder-lab` Code

[GitHub: cka-d-cluster-builder-lab](https://github.com/southsidedean/cka-d-cluster-builder-lab)

Head on over to the `cka-d-cluster-builder-lab` GitHub repository in the link above.  Go ahead and clone the repository to a directory of your choice.

**Clone repository:**
```bash
git clone https://github.com/southsidedean/cka-d-cluster-builder-lab.git

```

**SAMPLE OUTPUT:**
```bash
Cloning into 'cka-d-cluster-builder-lab'...
remote: Enumerating objects: 18, done.
remote: Counting objects: 100% (18/18), done.
remote: Compressing objects: 100% (13/13), done.
remote: Total 18 (delta 1), reused 18 (delta 1), pack-reused 0
Receiving objects: 100% (18/18), 17.71 KiB | 954.00 KiB/s, done.
Resolving deltas: 100% (1/1), done.
```

**Change directory into the repository directory:**
```bash
cd cka-d-cluster-builder-lab

```

**Let's take a look at the Terraform code:**
```bash
more cka-test.tf

```

[Terraform code](cka-test.tf)

You can see that the code is configurable via the numerous variables at the beginning of the file.  By default, a cluster will be created with a single control plane node and two worker nodes.  Feel free to adjust the values as you see fit.

***Ok, we're all ready to start deploying a cluster.  Let's go!***

## Deploy a Kubernetes Cluster Using Terraform and KVM Virtualization

### Deploy the KVM Virtual Machines Using Terraform

Ok, let's deploy a cluster!

**First, we need to initialize our Terraform environment:**
```bash
terraform init

```

**SAMPLE OUTPUT:**
```bash
Initializing the backend...
Initializing modules...
Downloading registry.terraform.io/MonolithProjects/vm/libvirt 1.10.0 for controlplane...
- controlplane in .terraform/modules/controlplane
Downloading registry.terraform.io/MonolithProjects/vm/libvirt 1.10.0 for worker...
- worker in .terraform/modules/worker

Initializing provider plugins...
- Finding dmacvicar/libvirt versions matching ">= 0.7.0"...
- Installing dmacvicar/libvirt v0.7.4...
- Installed dmacvicar/libvirt v0.7.4 (self-signed, key ID 0833E38C51E74D26)

Partner and community providers are signed by their developers.
If you'd like to know more about provider signing, you can read about it here:
https://www.terraform.io/docs/cli/plugins/signing.html

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

**Next, let's generate a Terraform plan:**
```bash
terraform plan -out cka-plan.plan

```

**SAMPLE OUPUT EXCERPT:**
```bash
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.controlplane.libvirt_cloudinit_disk.commoninit[0] will be created
  + resource "libvirt_cloudinit_disk" "commoninit" {
      + id             = (known after apply)
      + name           = "control-plane-_init01.iso"
      + network_config = <<-EOT
            version: 2
            ethernets:
              ens3:
                dhcp4: true
...
Plan: 11 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + control-planes = {
      + ip_address = [
          + null,
        ]
      + name       = [
          + "control-plane-01",
        ]
    }
  + worker-nodes   = {
      + ip_address = [
          + null,
          + null,
        ]
      + name       = [
          + "worker-node-01",
          + "worker-node-02",
        ]
    }
...
```

This will show us what Terraform is going to build, and will validate our code for errors.  With no errors, let's proceed with a `terraform apply`.

**Deploy cluster:**
```bash
terraform apply -auto-approve cka-plan.plan

```

Terraform will handle all the heavy lifting for us and will build the environment as we requested.

**SAMPLE OUTPUT EXCERPT:**
```bash
...
module.worker.libvirt_domain.virt-machine[1] (remote-exec): Connected!
module.worker.libvirt_domain.virt-machine[0] (remote-exec): Connected!
module.controlplane.libvirt_domain.virt-machine[0] (remote-exec): Connected!
module.controlplane.libvirt_domain.virt-machine[0] (remote-exec): Virtual Machine control-plane-01 is UP!
module.controlplane.libvirt_domain.virt-machine[0] (remote-exec): Thu Apr 13 14:51:10 UTC 2023
module.controlplane.libvirt_domain.virt-machine[0]: Creation complete after 1m18s [id=baf36a1a-7278-4ab8-9e7e-f1e525c566c0]
module.worker.libvirt_domain.virt-machine[1] (remote-exec): Virtual Machine worker-node-02 is UP!
module.worker.libvirt_domain.virt-machine[1] (remote-exec): Thu Apr 13 14:51:10 UTC 2023
module.worker.libvirt_domain.virt-machine[0] (remote-exec): Virtual Machine worker-node-01 is UP!
module.worker.libvirt_domain.virt-machine[0] (remote-exec): Thu Apr 13 14:51:10 UTC 2023
module.worker.libvirt_domain.virt-machine[1]: Creation complete after 1m18s [id=e9b6593e-4af3-4246-8876-7d85badc6021]
module.worker.libvirt_domain.virt-machine[0]: Creation complete after 1m18s [id=7d35804d-f4c8-46ca-9022-da63564d8cca]

Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

control-planes = {
  "ip_address" = [
    "10.0.1.46",
  ]
  "name" = [
    "control-plane-01",
  ]
}
worker-nodes = {
  "ip_address" = [
    "10.0.1.70",
    "10.0.1.67",
  ]
  "name" = [
    "worker-node-01",
    "worker-node-02",
  ]
}
```

With a clean Terraform execution under our belt, we can proceed and check for our virtual machines using the `virsh list` command.

**Let's check our system for virtual machines:**
```bash
virsh list --all

```

**SAMPLE OUTPUT:**
```bash
 Id   Name                                State
----------------------------------------------------
 30   worker-node-01                      running
 31   worker-node-02                      running
 32   control-plane-01                    running
```

**If you'd like to see the IP addresses for the nodes:**
```bash
virsh net-dhcp-leases default

```

**SAMPLE OUTPUT:**
```bash
 Expiry Time           MAC address         Protocol   IP address      Hostname           Client ID or DUID
---------------------------------------------------------------------------------------------------------------------------------------------------
 2023-04-13 18:08:08   52:54:00:52:46:16   ipv4       10.0.1.12/24    worker-node-01     ff:b5:5e:67:ff:00:02:00:00:ab:11:73:21:55:bd:43:84:fe:79
 2023-04-13 18:08:07   52:54:00:9e:4f:d6   ipv4       10.0.1.72/24    control-plane-01   ff:b5:5e:67:ff:00:02:00:00:ab:11:c1:fb:9f:0e:b9:e7:4a:39
 2023-04-13 18:08:08   52:54:00:f6:4a:bf   ipv4       10.0.1.184/24   worker-node-02     ff:b5:5e:67:ff:00:02:00:00:ab:11:e3:34:b8:fb:95:84:e5:82
```

***Our three nodes are ready!  For now, leave your cluster up!***

### EXAMPLE: Tear Down the KVM Virtual Machines Using Terraform

When you're done with the cluster, you use the `terraform destroy` command to tear down the cluster.

**Destroy cluster:**
```bash
terraform destroy -auto-approve

```

**SAMPLE OUTPUT:**
```bash
...
module.worker.libvirt_volume.volume-qcow2[0]: Destruction complete after 0s
module.worker.libvirt_volume.volume-qcow2[1]: Destruction complete after 1s
module.controlplane.libvirt_cloudinit_disk.commoninit[0]: Destruction complete after 1s
module.worker.libvirt_volume.base-volume-qcow2[0]: Destroying... [id=/media/virtual-machines/worker-node--base.qcow2]
module.controlplane.libvirt_volume.volume-qcow2[0]: Destruction complete after 1s
module.controlplane.libvirt_volume.base-volume-qcow2[0]: Destroying... [id=/media/virtual-machines/control-plane--base.qcow2]
module.worker.libvirt_volume.base-volume-qcow2[0]: Destruction complete after 0s
module.controlplane.libvirt_volume.base-volume-qcow2[0]: Destruction complete after 0s

Destroy complete! Resources: 11 destroyed.
```

***Again, for now, leave your cluster up, or deploy a fresh set of nodes.  Let's build a Kubernetes cluster!***

## Deploy a Kubernetes Cluster on Our KVM Virtual Machines (Nodes)

To get started, we're going to log into each of our nodes with a separate connection (window/tab/etc), and become the `root` user.

**Log in to each node using SSH:**
```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<NODE_IP_ADDRESS>
```

**Become the `root` user on all nodes:**
```bash
sudo su
```

When deploying a Kubernetes cluster, you have choices with regard to your container runtime.  I'm writing up TWO options, but feel free to experiment!

***CHOOSE ONE OPTION ONLY!  Option 1 is Docker/`containerd` and Option 2 is CRI-O.  ONE OPTION ONLY!***

### Option 1: Prepare the KVM Nodes Using the `containerd` Runtime

[kubernetes.io: Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

[Docker: Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

***Choose this option to install the Docker/`containerd` runtime!***

#### Install Docker/`containerd` Software

***Perform the following steps on all nodes.***

**Uninstall existing versions of Docker/`containerd`:**
```bash
apt-get update
apt-get remove docker docker.io containerd runc

```

**Install software prerequisites, if needed:**
```bash
apt-get update
apt-get install -y ca-certificates curl gnupg

```

**Add Docker Repository GPG Keys:**
```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

```

**Add Docker Repository:**
```bash
echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

```

**Install Docker/`containerd`:**
```bash
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

```

**Add the `ubuntu` user to the `docker` group:**
```bash
usermod -aG docker ubuntu

```

**Enable/Start Docker:**
```bash
systemctl enable --now docker
systemctl status docker

```

**SAMPLE OUTPUT:**
```bash
Synchronizing state of docker.service with SysV service script with /lib/systemd/systemd-sysv-install.
Executing: /lib/systemd/systemd-sysv-install enable docker
● docker.service - Docker Application Container Engine
     Loaded: loaded (/lib/systemd/system/docker.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2023-04-13 15:12:24 UTC; 37s ago
TriggeredBy: ● docker.socket
       Docs: https://docs.docker.com
   Main PID: 3292 (dockerd)
      Tasks: 9
     Memory: 24.5M
        CPU: 435ms
     CGroup: /system.slice/docker.service
             └─3292 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock

Apr 13 15:12:21 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:21.005925937Z" level=info msg="[core] [Channel #4 SubChannel #5] Subchannel Connectivity change to RE>
Apr 13 15:12:21 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:21.006083496Z" level=info msg="[core] [Channel #4] Channel Connectivity change to READY" module=grpc
Apr 13 15:12:23 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:23.894513044Z" level=info msg="Loading containers: start."
Apr 13 15:12:24 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:24.187671369Z" level=info msg="Default bridge (docker0) is assigned with an IP address 172.17.0.0/16.>
Apr 13 15:12:24 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:24.336796817Z" level=info msg="Loading containers: done."
Apr 13 15:12:24 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:24.400227422Z" level=info msg="Docker daemon" commit=59118bf graphdriver=overlay2 version=23.0.3
Apr 13 15:12:24 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:24.401304837Z" level=info msg="Daemon has completed initialization"
Apr 13 15:12:24 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:24.665348647Z" level=info msg="[core] [Server #7] Server created" module=grpc
Apr 13 15:12:24 control-plane-01 systemd[1]: Started Docker Application Container Engine.
Apr 13 15:12:24 control-plane-01 dockerd[3292]: time="2023-04-13T15:12:24.674931732Z" level=info msg="API listen on /run/docker.sock"
```

We should see the `docker.service` service `enabled` and `active` on all nodes.  Press `q` to exit the `systemctl status docker` command.

There's an issue with the stock `/etc/containerd/config.toml` file and Kubernetes 1.26+.  We need to set the configuration file aside and restart the `containerd` service.

**Backup/disable existing `/etc/containerd/config.toml`:**
```bash
mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
systemctl restart containerd

```

**Configure `/etc/containerd/config.toml`:**
```bash
containerd config default > /etc/containerd/config.toml
sed -i '/SystemdCgroup/s/false/true/' /etc/containerd/config.toml
sed -i '/sandbox_image/s/registry.k8s.io\/pause:3.6/registry.k8s.io\/pause:3.2/' /etc/containerd/config.toml
systemctl restart containerd

```
***Sweet, we have a container runtime installed!  What's next?***

#### Docker/`containerd`: Linux System Configuration Tasks

***Perform the following steps on all nodes.***

**Configure the `systemd` `cgroup` driver:**
```bash
touch /etc/docker/daemon.json
cat <<EOF > /etc/docker/daemon.json
{"exec-opts": ["native.cgroupdriver=systemd"]}
EOF
systemctl restart docker
docker info | grep Cgroup

```

**SAMPLE OUTPUT:**
```bash
 Cgroup Driver: systemd
 Cgroup Version: 2
```

**Load the overlay and br_netfilter modules:**
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
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
bridge                307200  1 br_netfilter
overlay               151552  0
```

**Configure kernel parameters for bridging and IPv4 forwarding:**
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

```

**SAMPLE OUTPUT:**
```bash
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
```

**Apply kernel parameters:**
```bash
sysctl --system
```

**SAMPLE OUTPUT EXCERPT:**
```bash
...
* Applying /etc/sysctl.d/k8s.conf ...
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
...
```

***Ok, node configuration is complete.  Proceed to **Deploy the Kubernetes Cluster Using `kubeadm`** now.***

#### Option 2: Prepare the KVM Nodes Using the CRI-O Runtime

[kubernetes.io: Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

[GitHub: CRI-O Installation Instructions](https://github.com/cri-o/cri-o/blob/main/install.md#readme)

***Choose this option to install the CRI-O runtime!***

##### Install and Configure CRI-O Runtime Software

***Perform the following steps on all nodes.***

**Add CRI-O Repositories:**
```bash
echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.22/xUbuntu_22.04/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:1.22.list

```

**Add CRI-O Repository GPG Keys:**
```bash
mkdir -p /usr/share/keyrings
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.22/xUbuntu_22.04/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

```

**Install CRI-O Packages:**
```bash
apt-get update
apt-get install -y cri-o cri-o-runc

```

**Set the `cgroup` driver:**
```bash
touch /etc/crio/crio.conf.d/02-cgroup-manager.conf
cat <<EOF > /etc/crio/crio.conf.d/02-cgroup-manager.conf
[crio.runtime]
conmon_cgroup = "pod"
cgroup_manager = "systemd"
EOF

```

**Override the Pause Container Image:**
```bash
touch /etc/crio/crio.conf.d/03-cgroup-pause.conf
cat <<EOF > /etc/crio/crio.conf.d/03-cgroup-pause.conf
[crio.image]
pause_image="registry.k8s.io/pause:3.6"
EOF

```

**Sync CRI-O and distribution runc versions:**
```bash
touch /etc/crio/crio.conf.d/04-crio-runtime.conf
cat <<EOF > /etc/crio/crio.conf.d/04-crio-runtime.conf
[crio.runtime.runtimes.runc]
runtime_path = "/usr/lib/cri-o-runc/sbin/runc"
runtime_type = "oci"
runtime_root = "/run/runc"
EOF

```

**Enable/start the CRI-O service:**
```bash
systemctl enable --now crio
systemctl status crio

```

***Sweet, we have a container runtime installed!  What's next?***

#### CRI-O: Linux System Configuration Tasks

*Perform the following steps on all nodes.*

**Load the `overlay` and `br_netfilter` modules:**
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
lsmod | grep -E "overlay|br_netfilter"

```

**Configure kernel parameters for bridging and IPv4 forwarding:**
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

```

**Apply kernel parameters:**
```bash
sysctl --system
```

***Ok, node configuration is complete.  Proceed to 'Deploy the Kubernetes Cluster Using `kubeadm`' now.***

### Deploy the Kubernetes Cluster Using `kubeadm`

[kubernetes.io: Bootstrapping clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)

Now that all our nodes are prepared and have a container runtime installed and running, we can deploy a Kubernetes cluster using `kubeadm`.  We'll start by installing the `kubeadm` packages.

#### Install `kubeadm` Packages

[kubernetes.io: Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

***Perform the following steps on all nodes.***

**Update `apt` index and install prerequisites:**
```bash
apt-get update
apt-get install -y apt-transport-https ca-certificates curl

```
**Download Kubernetes Repository GPG Key:**
```bash
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

```

**Add Kubernetes Repository:**
```bash
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

```

**Let's see which versions of Kubernetes are available, for major version 1.26:**
```bash
apt-get update
apt-cache madison kubeadm | grep 1.26

```

**SAMPLE OUTPUT:**
```bash
   kubeadm |  1.26.4-00 | https://apt.kubernetes.io kubernetes-xenial/main amd64 Packages
   kubeadm |  1.26.3-00 | https://apt.kubernetes.io kubernetes-xenial/main amd64 Packages
   kubeadm |  1.26.2-00 | https://apt.kubernetes.io kubernetes-xenial/main amd64 Packages
   kubeadm |  1.26.1-00 | https://apt.kubernetes.io kubernetes-xenial/main amd64 Packages
   kubeadm |  1.26.0-00 | https://apt.kubernetes.io kubernetes-xenial/main amd64 Packages
```

We'll go ahead and install version 1.26.3.  That will allow us to practice upgrading to version 1.26.4, which is the latest at this time.

**Refresh/install Kubernetes packages:**
```bash
apt-get update
apt-get install -y kubelet=1.26.3-00 kubeadm=1.26.3-00 kubectl=1.26.3-00

```

**Lock down Kubernetes package versions:**
```bash
apt-mark hold kubelet kubeadm kubectl

```

**SAMPLE OUTPUT:**
```bash
kubelet set on hold.
kubeadm set on hold.
kubectl set on hold.
```

#### Pull Kubernetes Container Images on Control Plane Node

***Perform the following step on the Control Plane node.***

**Pull Kubernetes Container Images:**
```bash
kubeadm config images pull --kubernetes-version 1.26.3

```

#### Wrap Up the Installation

Now that all the Linux parts are done, we'll wrap up on all the nodes.

**Exit the `root` user shell:**
```bash
exit
```

***All the Linux work is done!  We can proceed to doing the Kubernetes things!***

### Deploy a Kubernetes Cluster Using `kubeadm`

[kubernetes.io: Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

Now, we're going to use `kubeadm` to configure and deploy Kubernetes on the nodes we've set up.

#### Inititalize the Control Plane Node

***Perform the following steps on the Control Plane node.***

**Initialize Control Plane Node:**
```bash
sudo kubeadm init --kubernetes-version 1.26.3

```

**EXAMPLE OUTPUT:**
```bash
[init] Using Kubernetes version: v1.26.3
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [control-plane-01 kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 10.0.1.37]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [control-plane-01 localhost] and IPs [10.0.1.37 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [control-plane-01 localhost] and IPs [10.0.1.37 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
[apiclient] All control plane components are healthy after 8.502280 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node control-plane-01 as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node control-plane-01 as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: o4v4rg.pqhucyn7ff0qap01
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
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

kubeadm join 10.0.1.37:6443 --token o4v4rg.pqhucyn7ff0qap01 \
	--discovery-token-ca-cert-hash sha256:01fabf406bce39943a486985b96330dda53bf6902700913c4b461b79a9852623
```

#### Configure `kubectl`: On the Control Plane Node

**Configure `kubectl`:**
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

```

**Checking our work:**
```bash
kubectl get nodes

```

**EXAMPLE OUTPUT:**
```bash
NAME               STATUS     ROLES           AGE    VERSION
control-plane-01   NotReady   control-plane   2m2s   v1.26.3
```

***We're going to need to install a networking provider to get things working.***

#### Deploy the Calico Networking CNI

[tigera.io: Install Calico networking and network policy for on-premises deployments](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

***Perform the following steps on the Control Plane node.***

**Download the Calico CNI manifest:**
```bash
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml -O
```

If we wanted to customize our Calico deployment, we could edit the `calico.yaml` manifest.  We're going to use it as-is.

**Deploy the Calico manifest:**
```bash
kubectl apply -f calico.yaml

```

**SAMPLE OUTPUT:**
```bash
poddisruptionbudget.policy/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
serviceaccount/calico-node created
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/bgppeers.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/blockaffinities.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/caliconodestatuses.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/clusterinformations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/felixconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/globalnetworksets.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/hostendpoints.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamblocks.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamconfigs.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipamhandles.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ippools.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/ipreservations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/kubecontrollersconfigurations.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networkpolicies.crd.projectcalico.org created
customresourcedefinition.apiextensions.k8s.io/networksets.crd.projectcalico.org created
clusterrole.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrole.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-kube-controllers created
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
daemonset.apps/calico-node created
deployment.apps/calico-kube-controllers created
```

**Checking our work:**
```bash
watch -n 1 kubectl get nodes

```

**SAMPLE OUTPUT:**
```bash
NAME               STATUS   ROLES           AGE    VERSION
control-plane-01   Ready    control-plane   3m4s   v1.26.3
```

The status of our control plane will change to `Ready` after a minute or so.  Type `CTRL-C` to exit the `watch` command.

***Ok, we have a functional Control Plane!***

#### Join the Worker Nodes to the Cluster

Now that we have a functional Control Plane, we can join the worker nodes to the cluster.  Use the `join` command that you saved when you initialized the Control Plane.  You'll need to use `sudo` to run the command as `root`.

***Perform the following steps on all worker nodes.***

EXAMPLE:
```bash
kubeadm join 10.0.1.37:6443 --token o4v4rg.pqhucyn7ff0qap01 --discovery-token-ca-cert-hash sha256:01fabf406bce39943a486985b96330dda53bf6902700913c4b461b79a9852623
```

**If you can't remember the join command, use the following command to retrieve it:**
```bash
sudo kubeadm token create --print-join-command

```

Join **each worker node** to the cluster, using `sudo`:
```bash
sudo kubeadm join ...  <-- FILL THIS IN WITH YOUR JOIN COMMAND
```

**SAMPLE OUTPUT:**
```bash
d46e1183c8343157924
[preflight] Running pre-flight checks
[preflight] Reading configuration from the cluster...
[preflight] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap...

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

#### Confirm the Worker Nodes Were Joined to the Cluster

***Perform the following steps on the Control Plane node.***

**Checking our work:**
```bash
watch -n 1 kubectl get nodes

```

Wait until all the nodes are in a `Ready` state, as shown below.

**SAMPLE OUTPUT:**
```bash
Every 1.0s: kubectl get nodes       control-plane-01: Thu Apr 13 16:36:41 2023

NAME               STATUS   ROLES           AGE     VERSION
control-plane-01   Ready    control-plane   35m     v1.26.3
worker-node-01     Ready    <none>          8m25s   v1.26.3
worker-node-02     Ready    <none>          9m20s   v1.26.3
```

Once all nodes are in the `Ready` state, exit the `watch` command with `CRTL-C`.

**Taking a look at all the resources in our cluster:**
```bash
kubectl get all -A
```

**EXAMPLE OUTPUT:**
```bash
NAMESPACE     NAME                                           READY   STATUS    RESTARTS   AGE
kube-system   pod/calico-kube-controllers-5857bf8d58-jbpkt   1/1     Running   0          3m26s
kube-system   pod/calico-node-mz8fr                          1/1     Running   0          2m3s
kube-system   pod/calico-node-q475n                          1/1     Running   0          2m6s
kube-system   pod/calico-node-vrcvq                          1/1     Running   0          3m26s
kube-system   pod/coredns-787d4945fb-9hq94                   1/1     Running   0          4m38s
kube-system   pod/coredns-787d4945fb-djd7v                   1/1     Running   0          4m38s
kube-system   pod/etcd-control-plane-01                      1/1     Running   0          4m43s
kube-system   pod/kube-apiserver-control-plane-01            1/1     Running   0          4m42s
kube-system   pod/kube-controller-manager-control-plane-01   1/1     Running   0          4m41s
kube-system   pod/kube-proxy-dpq44                           1/1     Running   0          4m38s
kube-system   pod/kube-proxy-jwnx5                           1/1     Running   0          2m6s
kube-system   pod/kube-proxy-zdhbz                           1/1     Running   0          2m3s
kube-system   pod/kube-scheduler-control-plane-01            1/1     Running   0          4m40s

NAMESPACE     NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
default       service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP                  4m43s
kube-system   service/kube-dns     ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   4m41s

NAMESPACE     NAME                         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/calico-node   3         3         3       3            3           kubernetes.io/os=linux   3m26s
kube-system   daemonset.apps/kube-proxy    3         3         3       3            3           kubernetes.io/os=linux   4m41s

NAMESPACE     NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/calico-kube-controllers   1/1     1            1           3m26s
kube-system   deployment.apps/coredns                   2/2     2            2           4m41s

NAMESPACE     NAME                                                 DESIRED   CURRENT   READY   AGE
kube-system   replicaset.apps/calico-kube-controllers-5857bf8d58   1         1         1       3m26s
kube-system   replicaset.apps/coredns-787d4945fb                   2         2         2       4m39s
```

***There you have it!  A Kubernetes cluster, assembled with `kubeadm`.***

## OPTIONAL: Configure `kubectl`: On Your Virtualzation Host

You might want to manage your cluster using `kubectl` on your virtualization host.  This is a common use case scenario that is easy to implement.

If you don't have `kubectl` installed on your virtualization host, install it now.

**Copy `KUBECONFIG` to KVM host:**
```bash
scp -i ~/.ssh/id_ed25519 ubuntu@<CONTROL_PLANE_IP>:~/.kube/config control-plane-01.conf
KUBECONFIG=control-plane-01.conf ; export KUBECONFIG

```

If you want to get totally fancy and create a context for it, feel free to indulge your fancy.  I'm keeping things on-point here and not going down that rabbit hole.

**Checking our work:**
```bash
kubectl get nodes

```

**EXAMPLE OUTPUT:**
```bash
NAME               STATUS   ROLES           AGE   VERSION
control-plane-01   Ready    control-plane   43m   v1.26.3
worker-node-01     Ready    <none>          17m   v1.26.3
worker-node-02     Ready    <none>          17m   v1.26.3
```

When you're done with the cluster, you can `unset KUBECONFIG` to stop using the configuration.

## Tear Down the KVM Virtual Machines Using Terraform

When you're done with the cluster, you use the `terraform destroy` command to tear down the cluster.

**Destroy cluster:**
```bash
terraform destroy -auto-approve

```

**SAMPLE OUTPUT:**
```bash
...
module.worker.libvirt_volume.volume-qcow2[0]: Destruction complete after 0s
module.worker.libvirt_volume.volume-qcow2[1]: Destruction complete after 1s
module.controlplane.libvirt_cloudinit_disk.commoninit[0]: Destruction complete after 1s
module.worker.libvirt_volume.base-volume-qcow2[0]: Destroying... [id=/media/virtual-machines/worker-node--base.qcow2]
module.controlplane.libvirt_volume.volume-qcow2[0]: Destruction complete after 1s
module.controlplane.libvirt_volume.base-volume-qcow2[0]: Destroying... [id=/media/virtual-machines/control-plane--base.qcow2]
module.worker.libvirt_volume.base-volume-qcow2[0]: Destruction complete after 0s
module.controlplane.libvirt_volume.base-volume-qcow2[0]: Destruction complete after 0s

Destroy complete! Resources: 11 destroyed.
```

**Checking our work:**
```bash
virsh list --all

```

***Our cluster resources have been destroyed.  All cleaned up!***

## Summary

By leveraging the [Terraform Module for KVM/Libvirt Virtual Machines](https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/latest), we can build a set of nodes on a KVM hypervisorr, in a quick and repeatable way, which is perfect for getting hands-on with Kubernetes clusters.  Using the materials in this repository, you can customize the Terraform for your needs and use cases.

*Enjoy!*

**Tom Dean**
