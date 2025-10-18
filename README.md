# Kubernetes Cluster Automated Setup

## 📋 Overview

This automated bash script provides a streamlined deployment of a production-ready Kubernetes cluster using **kubeadm**, **containerd** as the container runtime, and **Calico** as the CNI (Container Network Interface) plugin. The script handles all prerequisites, installations, and configurations across multiple nodes with minimal manual intervention.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌───────────────┐                                       │
│  │  Master Node  │  192.168.100.17                      │
│  │               │                                       │
│  │  • API Server │                                       │
│  │  • Scheduler  │                                       │
│  │  • Controller │                                       │
│  │  • etcd       │                                       │
│  └───────────────┘                                       │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Worker Node  │  │ Worker Node  │  │ Worker Node  │  │
│  │              │  │              │  │              │  │
│  │ 192.168.     │  │ 192.168.     │  │ 192.168.     │  │
│  │ 100.15       │  │ 100.16       │  │ 100.18       │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                           │
│  Pod Network: 10.1.0.0/16 (Calico CNI)                  │
└─────────────────────────────────────────────────────────┘
```

## ✨ Features

- **Fully Automated**: One-command deployment of entire cluster
- **Container Runtime**: containerd with CRI support
- **Network Plugin**: Calico v3.25.0 with custom CIDR configuration
- **Multi-Node Support**: 1 master + 3 worker nodes (easily scalable)
- **Production Ready**: Proper system configurations and security settings
- **Idempotent**: Safe to re-run without breaking existing setup
- **Error Handling**: Validates installations and waits for components to be ready

## 📦 Prerequisites

### System Requirements

**Minimum per Node:**
- CPU: 2 cores
- RAM: 2GB (4GB recommended for master)
- Disk: 20GB free space
- Network: Static IP addresses

**Operating System:**
- Ubuntu 24.04 LTS (xUbuntu_24.04)
- Other Debian-based distributions (may require modifications)

### Network Requirements

- All nodes must be able to communicate with each other
- SSH root access configured between control machine and all nodes
- Network interface: `ens33` (configurable)
- Required ports open (see Port Requirements section)

### Pre-Installation Checklist

- [ ] SSH keys configured for passwordless root access
- [ ] Static IP addresses assigned to all nodes
- [ ] Hostnames properly configured
- [ ] Internet connectivity available on all nodes
- [ ] No existing Kubernetes installation

## 🚀 Quick Start

### 1. Clone or Download the Script

```bash
# Download the script
wget https://your-repo/kubernetes-setup.sh
chmod +x kubernetes-setup.sh
```

### 2. Configure Node IPs

Edit the script to match your infrastructure:

```bash
# Master node
master_ip=192.168.100.17

# Worker nodes
worker1_ip=192.168.100.15
worker2_ip=192.168.100.16
worker3_ip=192.168.100.18

# Network configuration
pod_cidr="10.1.0.0/16"
interface="ens33"
```

### 3. Execute the Script

```bash
./kubernetes-setup.sh
```

Expected runtime: **10-15 minutes** depending on network speed and system performance.

## 🔧 Configuration Options

### Network Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pod_cidr` | `10.1.0.0/16` | Pod network CIDR range |
| `interface` | `ens33` | Network interface name |
| `VERSION` | `1.28` | Kubernetes version |

### Node Configuration

Easily add or remove nodes by modifying the arrays:

```bash
masters=("192.168.100.17")
workers=("192.168.100.15" "192.168.100.16" "192.168.100.18")
```

## 📝 What the Script Does

### Phase 1: Node Preparation (All Nodes)

1. **Kernel Module Configuration**
   - Loads `overlay` and `br_netfilter` modules
   - Persists modules across reboots

2. **Network Configuration**
   - Enables IP forwarding
   - Configures bridge netfilter settings
   - Applies sysctl parameters

3. **Swap Management**
   - Disables swap (Kubernetes requirement)
   - Removes swap from `/etc/fstab`

### Phase 2: Container Runtime (All Nodes)

1. **containerd Installation**
   - Installs containerd package
   - Generates default configuration
   - Enables SystemdCgroup for proper resource management
   - Updates pause container image to v3.9

2. **Service Management**
   - Enables containerd service
   - Starts and verifies containerd

### Phase 3: Kubernetes Components (All Nodes)

1. **Repository Setup**
   - Adds Kubernetes APT repository
   - Imports GPG keys for package verification

2. **Package Installation**
   - Installs `kubelet`, `kubeadm`, `kubectl`
   - Holds packages at specific version
   - Installs `jq` for JSON processing

3. **Kubelet Configuration**
   - Detects node IP address automatically
   - Configures `--node-ip` flag
   - Restarts kubelet service

### Phase 4: Master Initialization

1. **Cluster Initialization**
   - Runs `kubeadm init` with proper parameters
   - Sets up API server advertise address
   - Configures pod network CIDR

2. **Kubeconfig Setup**
   - Configures kubectl for root user
   - Optionally configures for `esraa` user

3. **Network Plugin Deployment**
   - Downloads Calico manifests
   - Customizes CIDR configuration
   - Applies Calico resources
   - Waits for Calico pods to be ready (300s timeout)

### Phase 5: Worker Node Joining

1. **Token Generation**
   - Creates join token with 24-hour TTL
   - Generates join command

2. **Node Registration**
   - Executes join command on each worker
   - Configures CRI socket
   - Verifies join success

## 🔍 Verification

After successful deployment, verify the cluster:

```bash
# Check cluster status
kubectl cluster-info

# Verify all nodes are Ready
kubectl get nodes

# Check all system pods are Running
kubectl get pods -n kube-system

# Verify Calico installation
kubectl get pods -n kube-system | grep calico
```

Expected output:
```
NAME                      STATUS   ROLES           AGE   VERSION
master                    Ready    control-plane   5m    v1.28.15
worker1                   Ready    <none>          3m    v1.28.15
worker2                   Ready    <none>          3m    v1.28.15
worker3                   Ready    <none>          3m    v1.28.15
```

## 🔐 Port Requirements

### Master Node

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API server |
| 2379-2380 | TCP | etcd server client API |
| 10250 | TCP | Kubelet API |
| 10259 | TCP | kube-scheduler |
| 10257 | TCP | kube-controller-manager |

### Worker Nodes

| Port | Protocol | Purpose |
|------|----------|---------|
| 10250 | TCP | Kubelet API |
| 30000-32767 | TCP | NodePort Services |

### Calico (All Nodes)

| Port | Protocol | Purpose |
|------|----------|---------|
| 179 | TCP | BGP |
| 4789 | UDP | VXLAN |

## 🛠️ Troubleshooting

### Nodes Remain in NotReady State

```bash
# Check kubelet logs
journalctl -u kubelet -f

# Verify Calico pods
kubectl get pods -n kube-system | grep calico

# Check Calico logs
kubectl logs -n kube-system -l k8s-app=calico-node
```

**Solution**: Wait 3-5 minutes for Calico initialization. If issues persist, verify network connectivity.

### CoreDNS Pods Pending

```bash
# Check for network plugin issues
kubectl describe pod -n kube-system coredns-<pod-id>
```

**Solution**: Ensure Calico is fully operational. CoreDNS requires a functional CNI.

### Worker Nodes Fail to Join

```bash
# On worker node, check kubelet status
systemctl status kubelet

# Check for firewall issues
sudo ufw status
```

**Solution**: Verify network connectivity to master node and ensure required ports are open.

### Certificate or Token Issues

```bash
# Generate new token on master
kubeadm token create --print-join-command --ttl 24h
```

**Solution**: Re-run join command with fresh token on worker nodes.

## 📊 Component Versions

| Component | Version |
|-----------|---------|
| Kubernetes | v1.28.x |
| containerd | Latest from Ubuntu repos |
| Calico | v3.25.0 |
| Pause Container | 3.9 |

## 🔄 Maintenance Operations

### Adding New Worker Nodes

1. Prepare the new node with same OS and network configuration
2. Add IP to `workers` array in script
3. Re-run script (existing nodes will be skipped)




## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
![alt text](<Screenshot from 2025-10-18 16-41-16.png>)

