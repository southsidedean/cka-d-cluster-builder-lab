# Changelog

## 0.3.1 (unreleased)

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
