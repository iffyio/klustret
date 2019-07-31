#!/bin/bash

set -e
set -o pipefail

KUBERNETES_VERSION=v1.12.0

install_kubernetes_controller() {
    echo "Installing kubernetes controller ${KUBERNETES_VERSION}..."

    download_uri="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64"

    echo "Fetching kubernetes components..."
    wget -q --show-progress --https-only --timestamping \
        "${download_uri}/kube-apiserver" \
        "${download_uri}/kube-controller-manager" \
        "${download_uri}/kube-scheduler" \
        "${download_uri}/kubectl"

    chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
    sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin

    sudo mkdir -p /var/lib/kubernetes

    echo "Configuring API server..."

    internal_ip=$(curl http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
    sudo cp ca.pem \
        ca-key.pem \
        kubernetes-key.pem \
        kubernetes.pem \
        service-account-key.pem \
        service-account.pem \
        encryption-config.yaml \
        kube-controller-manager.kubeconfig \
        kube-scheduler.kubeconfig \
        /var/lib/kubernetes

    sed -i "s/INTERNAL_IP/${internal_ip}/g" /etc/systemd/system/kube-apiserver.service

    sudo systemctl daemon-reload
    sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
    sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler

}

install_kubernetes_controller