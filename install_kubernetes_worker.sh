#!/bin/bash

set -e
set -o pipefail

KUBERNETES_VERSION=v1.12.0

CNI_VERSION=v0.6.0

CRI_CONTAINERD_VERSION=1.2.0

RUNC_VERSION=v1.0.0

# Get the worker id
instance=$(hostname -s)
worker=$(echo "${instance}" | grep -Eo '[0-9]+$')
pod_cidr="10.200.${worker}.0/24"

install_cni() {
    echo "Installing cni..."

    local download_uri="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz"
    local cni_bin_dir=/opt/cni/bin

    sudo mkdir -p "${cni_bin_dir}"

    wget -q --https-only "${download_uri}"
    sudo tar -xvf "cni-plugins-amd64-${CNI_VERSION}.tgz" -C "${cni_bin_dir}"

    sed -i "s#POD_CIDR#${pod_cidr}#g" /etc/cni/net.d/10-bridge.conf
}

install_cri_containerd() {
    echo "Installing cri containerd..."

    local download_uri="https://github.com/containerd/containerd/releases/download/v${CRI_CONTAINERD_VERSION}-rc.0/containerd-${CRI_CONTAINERD_VERSION}-rc.0.linux-amd64.tar.gz"

    wget -q --https-only "${download_uri}"
    sudo tar -xvf "containerd-${CRI_CONTAINERD_VERSION}-rc.0.linux-amd64.tar.gz" -C /

    wget -q --https-only \
      "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}-rc5/runc.amd64"
    chmod +x runc.amd64
    sudo mv runc.amd64 /usr/local/bin/runc
}

install_kubernetes_components() {
    echo "Installing kubernetes worker components..."
    local download_uri="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64"

    wget -q --https-only \
        "${download_uri}/kubectl" \
        "${download_uri}/kubelet" \
        "${download_uri}/kube-proxy"

    chmod +x kubectl kubelet kube-proxy
    sudo mv kubectl kubelet kube-proxy /usr/local/bin

    sudo mkdir -p /var/lib/kubelet /var/lib/kube-proxy /var/lib/kubernetes /var/run/kubernetes

    sudo cp "${instance}-key.pem" "${instance}.pem" /var/lib/kubelet
    sudo cp "${instance}.kubeconfig" /var/lib/kubelet/kubeconfig
    sudo cp ca.pem /var/lib/kubernetes

    sudo sed "s#POD_CIDR#${pod_cidr}#g; s#INSTANCE#${instance}#g" \
        "kubelet-config.yaml" > /var/lib/kubelet/kubelet-config.yaml

    sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
    sudo cp kube-proxy-config.yaml /var/lib/kube-proxy/
}

install_kubernetes_worker() {
  sudo apt-get install socat

  install_cni
  install_cri_containerd
  install_kubernetes_components

  systemctl daemon-reload
  systemctl enable containerd kubelet kube-proxy
  systemctl start containerd kubelet kube-proxy
}

install_kubernetes_worker
