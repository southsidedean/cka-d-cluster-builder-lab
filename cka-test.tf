# Terraform code to stand up infrastructure to build
# an Open Source Kubernetes cluster
#
# Tom Dean
# tom@dean33.com
#
# Last edit 10/10/2023
#
# Based on the Terraform module for KVM/Libvirt Virtual Machine
# https://registry.terraform.io/modules/MonolithProjects/vm/libvirt/1.10.0
# Utilizes the dmacvicar/libvirt Terraform provider

# Let's set some variables!

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

# Other node configuration

variable "timezone" {
  type = string
  default = "CST"
}

variable "osimg" {
  type = string
  default = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

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

# Module for building our control plane nodes

data "template_file" "cp_user_data" {
  template = file("${path.module}/cp_cloud_init.cfg")
}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field

resource "libvirt_cloudinit_disk" "cp_commoninit" {
  name           = "cp_commoninit.iso"
  user_data      = data.template_file.cp_user_data.rendered
  pool           = var.cp_diskpool
}

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

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  
  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}

# Module for building our worker nodes

data "template_file" "worker_user_data" {
  template = file("${path.module}/worker_cloud_init.cfg")
}

# for more info about paramater check this out
# https://github.com/dmacvicar/terraform-provider-libvirt/blob/master/website/docs/r/cloudinit.html.markdown
# Use CloudInit to add our ssh-key to the instance
# you can add also meta_data field

resource "libvirt_cloudinit_disk" "worker_commoninit" {
  name           = "worker_commoninit.iso"
  user_data      = data.template_file.worker_user_data.rendered
  pool           = var.worker_diskpool
}

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

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  
  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}


# This resource will destroy (potentially immediately) after null_resource.next
#resource "null_resource" "previous" {}
#
#resource "time_sleep" "wait_30_seconds" {
#  depends_on = [null_resource.previous]
#
#  create_duration = "30s"
#}

# This resource will create (at least) 30 seconds after null_resource.previous
#resource "null_resource" "next" {
#  depends_on = [time_sleep.wait_30_seconds]
#}

# Outputs

output "control-planes" {
  value = module.controlplane
}

output "worker-nodes" {
  value = module.worker
}
