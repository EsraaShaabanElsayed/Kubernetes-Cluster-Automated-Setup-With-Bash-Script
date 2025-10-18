#!/bin/bash
master_ip=192.168.100.17
worker1_ip=192.168.100.15
worker2_ip=192.168.100.16
worker3_ip=192.168.100.18
all_ips=("$master_ip" "$worker1_ip" "$worker2_ip" "$worker3_ip")
OS="xUbuntu_24.04"
VERSION="1.28"
interface="ens33" 
token=""
# Define your nodes
masters=("192.168.100.17")
workers=("192.168.100.15" "192.168.100.16" "192.168.100.18")
pod_cidr="10.1.0.0/16"

for ip in "${all_ips[@]}"; do
   ssh root@$ip bash -s <<EOF
   cat <<EOF1 | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF1

   if ! lsmod | grep -q overlay; then sudo modprobe overlay; fi
   if ! lsmod | grep -q br_netfilter; then sudo modprobe br_netfilter; fi


   cat <<EOF2 | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF2
   sudo sysctl --system
   
   # Disable swap
   if swapon --show | grep -q '^'; then
    sudo swapoff -a
    sudo sed -i '/ swap / s/^/#/' /etc/fstab
   fi



# Install containerd

   if ! command -v containerd >/dev/null; then
      sudo apt update
      sudo apt install -y containerd
   fi
   
   # Configure containerd with proper CRI settings
   mkdir -p /etc/containerd
   
   # Generate default config and enable CRI
   containerd config default > /etc/containerd/config.toml
   
   # Enable SystemdCgroup and update pause image
   sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
   sed -i 's|registry.k8s.io/pause:3.6|registry.k8s.io/pause:3.9|' /etc/containerd/config.toml

   
   echo "Containerd status:"
   systemctl status containerd --no-pager -l

   # Restart containerd
   systemctl enable containerd  --now
   systemctl daemon-reload
   systemctl restart containerd

   # Verify containerd is running with CRI
   systemctl status containerd


# Kubernetes installation

   sudo apt install -y apt-transport-https ca-certificates curl gpg
   sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

   if ! dpkg -l | grep -q kubelet; then
      sudo apt update
      sudo apt install -y kubelet kubeadm kubectl
      sudo apt-mark hold kubelet kubeadm kubectl
   fi


   sudo apt update
   sudo apt-get install -y jq

   # Get the IP address of that interface
   local_ip="\$(ip --json a s | jq -r ".[] | if .ifname == \"$interface\" then .addr_info[] | if .family == \"inet\" then .local else empty end else empty end")"

   # Write kubelet config
   cat > /etc/default/kubelet << EOF6
   KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF6

   sudo systemctl daemon-reload
   sudo systemctl restart kubelet

EOF


done


   # Loop over masters
for ip in "${masters[@]}"; do
  echo "Configuring master node: $ip"
  
  ssh root@$ip bash -s <<EOF
    export IPADDR=$ip
    export NODENAME=\$(hostname -s)
    export POD_CIDR=$pod_cidr

    echo \"IPADDR=\$IPADDR\"
    echo \"NODENAME=\$NODENAME\"
    echo \"POD_CIDR=\$POD_CIDR\"
    if [ ! -f /etc/kubernetes/admin.conf ]; then
    sudo kubeadm init \
        --apiserver-advertise-address=\$IPADDR \\
        --apiserver-cert-extra-sans=\$IPADDR \\
        --pod-network-cidr=\$POD_CIDR \\
        --node-name "\$NODENAME" \\
        --cri-socket=unix:///var/run/containerd/containerd.sock
        
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown \$(id -u):\$(id -g) /root/.kube/config

    # Set up kubeconfig for root
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown \$(id -u):\$(id -g) /root/.kube/config

    # Also set up for esraa user if it exists
   if id "esraa" &>/dev/null; then
            mkdir -p /home/esraa/.kube
            cp -i /etc/kubernetes/admin.conf /home/esraa/.kube/config
            chown esraa:esraa /home/esraa/.kube/config
   fi

   sleep 30

   # Install Calico network plugin with better error handling
   echo "Installing Calico network plugin..."
      
   # Download Calico manifest
   if curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml -o /tmp/calico.yaml; then
      echo "Calico manifest downloaded successfully"
        
      # Modify pod CIDR if different from default
      if [ "$POD_CIDR" != "192.168.0.0/16" ]; then
          echo "Updating Calico CIDR to $POD_CIDR"
          sed -i "s|192.168.0.0/16|$POD_CIDR|g" /tmp/calico.yaml
      fi
        
      # Apply Calico
      kubectl apply -f /tmp/calico.yaml
        
      if [ $? -eq 0 ]; then
         echo "Calico applied successfully"
          
         # Wait for Calico to be ready
         echo "Waiting for Calico pods to be ready (this may take 2-3 minutes)..."
         kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
         kubectl wait --for=condition=ready pod -l k8s-app=calico-kube-controllers -n kube-system --timeout=300s
          
         echo "Calico installation completed"
         kubectl get pods -n kube-system | grep calico
      else
          echo "ERROR: Failed to apply Calico manifest"
          exit 1
      fi
      else
        echo "ERROR: Failed to download Calico manifest"
        exit 1
      fi
      
      # Verify nodes are ready
      echo "Checking node status..."
      kubectl get nodes
      
   else
      echo "Cluster already initialized"
   fi

EOF
done




token=$(ssh root@${masters[0]} "kubeadm token create --print-join-command --ttl 24h")



#join worker nodes
for ip in "${workers[@]}"; do
  echo "Configuring worker node: $ip"
  ssh root@$ip bash -s <<EOF
  
  # Check if worker has already joined
   if [ ! -f /etc/kubernetes/kubelet.conf ]; then
      $token --cri-socket=unix:///var/run/containerd/containerd.sock
   else
  echo "Node \$(hostname -s) is already joined."
   fi

EOF
done



echo "#################################################################"
echo "!!!! Kubernetes cluster setup completed!!!!!"

echo "#################################################################"