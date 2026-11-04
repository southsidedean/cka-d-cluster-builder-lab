# Lean: one control plane node and one worker
# 4 vCPUs and 7 GB in total
# For 6 GB, set cp_memory to 3072 (see the README's note on memory)

control_plane_nodes = 1
worker_nodes        = 1
cp_memory           = 4096
worker_memory       = 3072
