# Terraform code to stand up infrastructure to build
# an Open Source Kubernetes cluster
#
# Tom Dean
# tom@southsidedean.com
#
#
# Based on the Terraform module for KVM/Libvirt Virtual Machine
# https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/1.12.0
# Utilizes the dmacvicar/libvirt Terraform provider

# Let's set some variables!

# Cluster sizing
# We can set the number of control plane and worker nodes here
# One control plane node is the minimum, and 0 workers makes a single-node cluster
# The examples folder has ready-made sizes: terraform apply -var-file=examples/lean.tfvars

variable "control_plane_nodes" {
  type    = number
  default = 1

  validation {
    condition     = var.control_plane_nodes >= 1 && var.control_plane_nodes % 2 == 1
    error_message = "control_plane_nodes must be an odd number, 1 or more, because etcd needs a majority of the control plane nodes to keep working."
  }
}

variable "worker_nodes" {
  type    = number
  default = 2

  validation {
    condition     = var.worker_nodes >= 0 && floor(var.worker_nodes) == var.worker_nodes
    error_message = "worker_nodes must be a whole number, 0 or more."
  }
}

# Hostname prefixes
# This controls how the hostnames are generated

variable "cp_prefix" {
  type    = string
  default = "control-plane-"
}

variable "worker_prefix" {
  type    = string
  default = "worker-node-"
}

# Node sizing
# Start with the control planes

variable "cp_cpu" {
  type    = number
  default = 2

  validation {
    condition     = var.cp_cpu >= 2 && floor(var.cp_cpu) == var.cp_cpu
    error_message = "cp_cpu must be a whole number, 2 or more, because kubeadm needs at least 2 vCPUs per node."
  }
}

variable "cp_disk" {
  type    = number
  default = 25
}

variable "cp_memory" {
  type    = number
  default = 4096

  validation {
    condition     = var.cp_memory >= 2048
    error_message = "cp_memory must be 2048 (MB) or more, because kubeadm needs at least 2 GB per node."
  }
}

# On to the worker nodes

variable "worker_cpu" {
  type    = number
  default = 2

  validation {
    condition     = var.worker_cpu >= 2 && floor(var.worker_cpu) == var.worker_cpu
    error_message = "worker_cpu must be a whole number, 2 or more, because kubeadm needs at least 2 vCPUs per node."
  }
}

variable "worker_disk" {
  type    = number
  default = 25
}

variable "worker_memory" {
  type    = number
  default = 4096

  validation {
    condition     = var.worker_memory >= 2048
    error_message = "worker_memory must be 2048 (MB) or more, because kubeadm needs at least 2 GB per node."
  }
}

# Disk Pool to use
# Control Plane

variable "cp_diskpool" {
  type    = string
  default = "default"
}

# Worker Nodes

variable "worker_diskpool" {
  type    = string
  default = "default"
}

# User / Key information
# Same across all nodes, customize if you wish

variable "privateuser" {
  type    = string
  default = "ubuntu"
}

variable "privatekey" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

variable "pubkey" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

# Other node configuration
# The time zone is a name from "timedatectl list-timezones"

variable "timezone" {
  type    = string
  default = "America/Chicago"
}

variable "osimg" {
  type    = string
  default = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

# Graphics type for the VM consoles: "vnc" or "spice"
# RHEL 9 and later (and Rocky and AlmaLinux) dropped SPICE, and VNC works everywhere

variable "graphics" {
  type    = string
  default = "vnc"
}

# Set our Terraform provider here
# We're going to use libvirt on our local machine

terraform {
  required_version = ">= 1.0"

  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      # 0.9 is a rewrite that the VM module doesn't support
      version = "~> 0.8.3"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Module for building our control plane nodes

module "controlplane" {
  source  = "MonolithProjects/vm/libvirt"
  version = "1.12.0"

  vm_hostname_prefix = var.cp_prefix
  vm_count           = var.control_plane_nodes
  memory             = var.cp_memory
  vcpu               = var.cp_cpu
  pool               = var.cp_diskpool
  system_volume      = var.cp_disk
  dhcp               = true
  ssh_admin          = var.privateuser
  ssh_private_key    = var.privatekey
  ssh_keys = [
    file(var.pubkey),
  ]
  time_zone  = var.timezone
  os_img_url = var.osimg
  graphics   = var.graphics
}

# Module for building our worker nodes

module "worker" {
  source  = "MonolithProjects/vm/libvirt"
  version = "1.12.0"

  vm_hostname_prefix = var.worker_prefix
  vm_count           = var.worker_nodes
  memory             = var.worker_memory
  vcpu               = var.worker_cpu
  pool               = var.worker_diskpool
  system_volume      = var.worker_disk
  dhcp               = true
  ssh_admin          = var.privateuser
  ssh_private_key    = var.privatekey
  ssh_keys = [
    file(var.pubkey),
  ]
  time_zone  = var.timezone
  os_img_url = var.osimg
  graphics   = var.graphics
}

# Outputs

output "control-planes" {
  value = module.controlplane
}

output "worker-nodes" {
  value = module.worker
}
