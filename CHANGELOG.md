# Changelog

## 0.2.1 (unreleased)

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
