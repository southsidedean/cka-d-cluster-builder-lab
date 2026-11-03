# Single node: one control plane node and no workers
# 2 vCPUs and 4 GB in total
# Remove the control plane taint after kubeadm init so pods can run on it

control_plane_nodes = 1
worker_nodes        = 0
cp_memory           = 4096
