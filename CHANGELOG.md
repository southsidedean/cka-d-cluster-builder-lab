# Changelog

## 0.4.0 (unreleased)

### New

- Smaller lab sizes in `examples/`, for smaller hosts: a single node, a lean one control plane and one worker, and two HA layouts with three control plane nodes. The lean sizes give workers 3 GB and the control plane 4 GB; the README says how to run the control plane on 3 GB and what that leaves free. Use one with `terraform apply -var-file=examples/lean.tfvars`.
- Terraform checks the node counts and sizes before it builds anything: an odd number of control plane nodes, 0 or more workers, and at least 2 vCPUs and 2048 MB per node.
- [docs/helm-kustomize.md](docs/helm-kustomize.md) installs metrics-server on the cluster with Helm, then with Kustomize, and uses it for `kubectl top`. The CKA covers both tools.
- [docs/kubeadm-config.md](docs/kubeadm-config.md) runs `kubeadm init` from a config file instead of flags, with an `InitConfiguration`, a `ClusterConfiguration`, and a `KubeletConfiguration` that reserves memory for the OS. It also shows where `kubeadm` stores those settings in the cluster.
- [docs/practice-loop.md](docs/practice-loop.md) has three ways to practice the cluster build again on the same VMs: remove and re-join a worker, reset the whole cluster with `kubeadm reset`, and revert the nodes to a libvirt snapshot taken before `kubeadm init`.
- [docs/etcd-and-certs.md](docs/etcd-and-certs.md) backs up etcd with `etcdctl`, restores it with `etcdutl` after deleting the test workload, and renews the cluster's certificates with `kubeadm certs renew`. The restore uses the `--bump-revision` and `--mark-compacted` flags from etcd's recovery guide; without them, the restored cluster's services stopped answering in testing.
- [docs/ha-control-plane.md](docs/ha-control-plane.md) builds a cluster with three control plane nodes on the HA sizes. keepalived and HAProxy run as static pods on the control plane nodes, following the kubeadm guide, and hold a virtual IP that the page keeps out of libvirt's DHCP range. It joins the other control plane nodes with `--control-plane --certificate-key`, shuts down the node holding the virtual IP to check that `kubectl` and the test workload keep working, and upgrades the HA cluster to 1.37.
- The README's introduction has a table from each CKA v1.37 curriculum item the lab covers to the section or page that covers it, and says which parts of the CKA and CKAD it leaves for you to practice on the finished cluster.
- The weekly upstream check also watches the CNCF's CKA and CKAD curricula, and posts a notice when one comes out for a newer Kubernetes than the README ends on.

### Changes

- Calico is installed with the Tigera operator, which Calico recommends, instead of the `calico.yaml` manifest, which its docs now call legacy. The README sets the pod network in the operator's `Installation` resource, and Calico's pods run in the `calico-system` namespace. The upgrade section's notes and sample output are updated to match.
- Nodes get 4 GB of memory by default instead of 8 GB, so the default lab needs 12 GB instead of 24 GB. With the cluster, the test workload, and metrics-server running, the control plane node used about 1.4 GB and each worker 1 GB at most. To keep 8 GB, set `cp_memory` and `worker_memory` to `8192`.
- The README's introduction says why the lab exists, without the old AWS backstory, and its requirements now name the cluster-building parts of the CKA and CKAD and the LFS258 and LFD259 courses.

## 0.3.1 (2026-11-03)

Documentation only: no Terraform or command changes.

### Fixes

- The README says what to expect from two messages during the upgrade: draining a node can retry for about 45 seconds on Calico's disruption budget, and with CRI-O, `kubeadm upgrade plan` warns about the `pause` image until CRI-O is upgraded.
- The README's introduction is shorter in a few places and no longer describes a GitLab workflow the lab doesn't use.

### Testing

- The 0.3.0 Terraform was tested on Rocky Linux 9.8 and 10.2 hosts, and the CRI-O path was run end to end a second time, from 1.36 to 1.37.

## 0.3.0 (2026-10-29)

The walkthrough is current again: Ubuntu 26.04 nodes, Kubernetes 1.36 from `pkgs.k8s.io`, and a new section on upgrading the cluster to 1.37. Every step was run end to end on fresh nodes, and the sample output comes from those runs.

### Upgrading from 0.2.1

Run `terraform destroy` on any nodes built with 0.2.1 before you pull this release, then `terraform apply` for fresh 26.04 nodes. The only Terraform change is the `osimg` default.

### New

- The nodes run Ubuntu 26.04 instead of 22.04.
- Kubernetes installs from the `pkgs.k8s.io` repository for 1.36, replacing `apt.kubernetes.io`, which has shut down.
- An upgrade section takes the cluster from 1.36 to 1.37 the way the CKA expects: the Control Plane first, then each worker, switching each node's package repository to the new minor version.
- `containerd` comes from Ubuntu's own package, with the `systemd` cgroup driver. CRI-O is now a short optional section that uses CRI-O's current repositories and covers its part of the upgrade.
- Calico 3.33.0, with the pods on `10.244.0.0/16`, so libvirt's stock `192.168.122.0/24` network works without changes.
- A test workload (two `nginx` pods behind a Service) to check the cluster before and after the upgrade.
- A table of the Terraform variables, a "What You Need" section, and install commands for KVM and `libvirt` on Ubuntu and on RHEL, Rocky Linux, and AlmaLinux.
- A logo.

### Fixes

- The README's storage pool and KVM links pointed to RHEL 6 and RHEL 8 documentation. It now gives the `virsh` commands directly.
- The README covers a DNS server on the host that holds libvirt's address and keeps the `default` network from starting.

### Removed

- The 2023 notes about the "Lab in a Box" server, and the Docker steps that came with the old `containerd` setup.

## 0.2.1 (2026-10-29)

The Terraform builds the lab's VMs again, on Ubuntu and on RHEL-family hosts. The Kubernetes steps in the README are still the 2023 ones; 0.3.0 updates them.

### Fixes

- `terraform init` no longer pulls libvirt provider 0.9, a rewrite the VM module doesn't support. The provider is pinned to 0.8.x.
- The VMs start on RHEL 9 and 10, Rocky Linux, and AlmaLinux hosts, which dropped SPICE graphics ([#1](https://github.com/southsidedean/cka-d-cluster-builder-lab/issues/1)). The VM module is now 1.12.0, and the lab uses VNC by default (`graphics`).
- The default time zone is `America/Chicago`. The old default, `CST`, made cloud-init fail on every node.
- The README links to `cka-builder.tf` instead of the old file name, and lists `mkisofs` and `xsltproc`, which Terraform needs. It also covers the AppArmor rule Ubuntu needs when the storage pool is outside `/var/lib/libvirt/images`, and how to clear VMs a failed apply leaves behind.

### New

- The lab is MIT licensed.
- Checks on every pull request: Terraform formatting and validation, TFLint, a Trivy scan, Markdown lint, spelling, and the workflows themselves. A weekly check reports when the Kubernetes, Calico, or Ubuntu versions the lab uses fall behind.

## 0.2.0 (2023-10-11)

The lab as published in October 2023: Terraform that builds one control plane node and two worker nodes as KVM virtual machines, and a README that walks through building a Kubernetes 1.26 cluster with kubeadm. Tagged in 2026 as a snapshot from before the refresh.

## 0.1 (2023-04-13)

The first version.
