#!/bin/bash

set -e
set -o pipefail

generate_configuration_files() {
  KUBERNETES_PUBLIC_ADDRESS=$(get_public_ip $CONTROLLER_NODE_NAME)
  old_pwd=$(pwd)

  cd "${CERTS_DIR}"

  CLUSTER_NAME='kubernetes-cluster'

  echo "Generating kubeconfig for worker nodes..."
  for i in $(seq 1 "${NUM_WORKERS}"); do
    instance="${WORKER_NODE_NAME}-${i}"

    kubectl config set-cluster "${CLUSTER_NAME}" \
      --certificate-authority="${CERTS_DIR}/ca.pem" \
      --embed-certs=true \
      --server="https://${KUBERNETES_PUBLIC_ADDRESS}:6443" \
      --kubeconfig="${instance}.kubeconfig"

    kubectl config set-credentials "system:node:${instance}" \
      --client-certificate="${CERTS_DIR}/${instance}.pem" \
      --client-key="${CERTS_DIR}/${instance}-key.pem" \
      --embed-certs=true \
      --kubeconfig="${instance}.kubeconfig"

    kubectl config set-context default \
      --cluster="${CLUSTER_NAME}" \
      --user="system:node:${instance}" \
      --kubeconfig="${instance}.kubeconfig"

    kubectl config use-context default --kubeconfig="${instance}.kubeconfig"

  done

  echo "Generating kubeconfig for kube-proxy..."
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority="${CERTS_DIR}/ca.pem" \
    --embed-certs=true \
    --server="https://${KUBERNETES_PUBLIC_ADDRESS}:6443" \
    --kubeconfig="kube-proxy.kubeconfig"

  kubectl config set-credentials "system:node:kube-proxy" \
    --client-certificate="${CERTS_DIR}/kube-proxy.pem" \
    --client-key="${CERTS_DIR}/kube-proxy-key.pem" \
    --embed-certs=true \
    --kubeconfig="kube-proxy.kubeconfig"

  kubectl config set-context default \
    --cluster="${CLUSTER_NAME}" \
    --user="system:kube-proxy" \
    --kubeconfig="kube-proxy.kubeconfig"

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

  for component in "kube-controller-manager" "kube-scheduler"; do
    echo "Generating kubeconfig for ${component}..."

    kubectl config set-cluster "${CLUSTER_NAME}" \
      --certificate-authority="${CERTS_DIR}/ca.pem" \
      --embed-certs=true \
      --server="https://127.0.0.1:6443" \
      --kubeconfig="${component}.kubeconfig"

    kubectl config set-credentials "system:node:${component}" \
      --client-certificate="${CERTS_DIR}/${component}.pem" \
      --client-key="${CERTS_DIR}/${component}-key.pem" \
      --embed-certs=true \
      --kubeconfig="${component}.kubeconfig"

    kubectl config set-context default \
      --cluster="${CLUSTER_NAME}" \
      --user="system:${component}" \
      --kubeconfig="${component}.kubeconfig"

    kubectl config use-context default --kubeconfig="${component}.kubeconfig"
  done

  echo "Generating kubeconfig for admin..."
  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority="${CERTS_DIR}/ca.pem" \
    --embed-certs=true \
    --server="https://${KUBERNETES_PUBLIC_ADDRESS}:6443" \
    --kubeconfig="admin.kubeconfig"

  kubectl config set-credentials "admin" \
    --client-certificate="${CERTS_DIR}/admin.pem" \
    --client-key="${CERTS_DIR}/admin-key.pem" \
    --embed-certs=true \
    --kubeconfig="admin.kubeconfig"

  kubectl config set-context default \
    --cluster="${CLUSTER_NAME}" \
    --user="admin" \
    --kubeconfig="admin.kubeconfig"

  kubectl config use-context default --kubeconfig=admin.kubeconfig

  for i in $(seq 1 "${NUM_WORKERS}"); do
    instance="${WORKER_NODE_NAME}-${i}"

    echo "Copying kubeconfigs to worker ${instance}..."
    instance_public_ip=$(get_public_ip "$instance")
    scp "${instance}.kubeconfig" "kube-proxy.kubeconfig" "${VM_USER}@${instance_public_ip}:~/"
  done

  echo "Copying kubeconfigs to controller..."
  controller_ip=$(get_public_ip $CONTROLLER_NODE_NAME)
    scp "admin.kubeconfig" \
        "kube-controller-manager.kubeconfig" \
        "kube-scheduler.kubeconfig" "${VM_USER}@${controller_ip}:~/"

  cd $old_pwd
}