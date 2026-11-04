# HA lean: three control plane nodes and one worker
# 8 vCPUs and 15 GB in total
# For 12 GB, set cp_memory to 3072 (see the README's note on memory)

control_plane_nodes = 3
worker_nodes        = 1
cp_memory           = 4096
worker_memory       = 3072
