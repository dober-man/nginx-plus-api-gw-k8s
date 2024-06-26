#!/bin/bash

# Update the apt package index and install packages needed to use the Kubernetes apt repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

# Download the public signing key for the Kubernetes package repositories
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Update apt package index, install kubelet, kubeadm, and kubectl, and pin their version
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap (required for kubeadm)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# Configure Docker daemon
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo mkdir -p /etc/systemd/system/docker.service.d

# Restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# Initialize Kubernetes cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Set up local kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Apply a pod network (Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# To make master node schedulable
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Ensure nodes are ready
kubectl wait --for=condition=Ready node --all --timeout=120s

# Create deployment for coffee API
kubectl create deployment coffee-api --image=nginxdemos/hello

# Create deployment for tea API
kubectl create deployment tea-api --image=nginxdemos/hello

# Create service for coffee API
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: coffee-service
spec:
  type: NodePort
  selector:
    app: coffee-api
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30081
EOF

# Create service for tea API
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: tea-service
spec:
  type: NodePort
  selector:
    app: tea-api
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30082
EOF

# Display the services details
kubectl get svc coffee-service tea-service

# Wait for the services to be up
echo "Please wait 30s while pods come online'"
sleep 30

# Test the coffee service
echo "Testing coffee service with: curl -s http://localhost:30081 | grep -i 'Welcome to nginx!'"
curl -s http://localhost:30081 | grep -i 'coffee'

# Test the tea service
echo "Testing tea service with: curl -s http://localhost:30082 | grep -i 'Welcome to nginx!'"
curl -s http://localhost:30082 | grep -i 'tea'
