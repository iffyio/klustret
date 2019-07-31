set -e
set -o pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CA_CONFIG_DIR=${DIR}/ca

export CERTS_DIR="${CA_CONFIG_DIR}/tmp"

do_certs() {
    echo "Generating certicicates..."

    source "${DIR}/generate_certificates.sh"

    generate_certificates
}

do_kubeconfigs() {
    echo "Generating kubeconfigs..."

    source "${DIR}/generate_configuration_files.sh"

    generate_configuration_files
}

do_etcd() {
    echo "Setting up etcd on controller node..."

    controller_public_ip=$(get_public_ip "$CONTROLLER_NODE_NAME")

    echo "Copying etcd.service to controller node..."
    scp "${DIR}/etc/systemd/system/etcd.service" "${VM_USER}@${controller_public_ip}:~/"

    echo "Copying etcd install script to controller node..."
    scp "${DIR}/install_etcd.sh" "${VM_USER}@${controller_public_ip}:~/"

    echo "Running etcd install script to controller node..."
    ssh "${VM_USER}@${controller_public_ip}" sudo ./install_etcd.sh
}

do_k8s_controller() {
    echo "Copying component services to controller node..."

    controller_public_ip=$(get_public_ip "$CONTROLLER_NODE_NAME")

    ssh "${VM_USER}@${controller_public_ip}" sudo mkdir -p /etc/kubernetes/config

    scp "${DIR}/etc/systemd/system/kube-apiserver.service" \
        "${DIR}/etc/systemd/system/kube-scheduler.service" \
        "${DIR}/etc/systemd/system/kube-controller-manager.service" \
        "${VM_USER}@${controller_public_ip}:/etc/systemd/system/"

    scp "${DIR}/etc/kube-scheduler.yaml" \
        "${VM_USER}@${controller_public_ip}:/etc/kubernetes/config"

    echo "Copying k8s controller install script to controller node..."
    scp "${DIR}/install_kubernetes_controller.sh" "${VM_USER}@${controller_public_ip}:~/"

    ssh "${VM_USER}@${controller_public_ip}" sudo ./install_kubernetes_controller.sh

    echo 'Waiting for kubernetes controller components to be ready...'
    i=0
    until ssh "${VM_USER}@${controller_public_ip}" \
        'bash -c '"'"'{ n=$(kubectl get componentstatuses | grep -i healthy | wc -l); [[ "$n" -gt 2 ]]; }'"'"; do
        i=$((i + 1))
        if [[ "$i" -eq 20 ]]; then
            echo "Timed out waiting for controller components to be ready"
            echo "===============component statuses=============="
            ssh "${VM_USER}@${controller_public_ip}" \
                'kubectl get componentstatuses'
            exit 1
        fi

        echo 'Waiting for kubernetes controller components to be ready...'
        sleep 5
    done

    echo "Copying apiserver to kubelet cluster roles"
    scp "${DIR}/etc/cluster-role-kube-apiserver-to-kubelet.yaml" \
        "${DIR}/etc/cluster-role-binding-kube-apiserver-to-kubelet.yaml" \
        "${VM_USER}@${controller_public_ip}:~/"

    echo "Applying apiserver to kubelet cluster roles..."
    ssh "${VM_USER}@${controller_public_ip}" \
        kubectl apply -f cluster-role-kube-apiserver-to-kubelet.yaml

    ssh "${VM_USER}@${controller_public_ip}" \
        kubectl apply -f cluster-role-binding-kube-apiserver-to-kubelet.yaml
}

do_k8s_workers() {
    for i in $(seq 1 "${NUM_WORKERS}"); do
        instance="${WORKER_NODE_NAME}-${i}"

        echo "Installing kubernetes worker components on ${instance}..."
        worker_public_ip="$(get_public_ip ${instance})"

        echo "Copying cni configs..."
        ssh "${VM_USER}@${worker_public_ip}" sudo mkdir -p /etc/cni/net.d
        scp "${DIR}/etc/cni/net.d/10-bridge.conf" \
            "${DIR}/etc/cni/net.d/99-loopback.conf" \
            "${VM_USER}@${worker_public_ip}:/etc/cni/net.d"

        scp "${DIR}/etc/kubelet-config.yaml" \
            "${DIR}/etc/kube-proxy-config.yaml" \
            "${VM_USER}@${worker_public_ip}:~/"

        scp "${DIR}/etc/systemd/system/kubelet.service" \
            "${DIR}/etc/systemd/system/kube-proxy.service" \
            "${DIR}/etc/systemd/system/containerd.service" \
            "${VM_USER}@${worker_public_ip}:/etc/systemd/system/"

        echo "Copying k8s install script to worker node..."
        scp "${DIR}/install_kubernetes_worker.sh" "${VM_USER}@${worker_public_ip}:~/"

        echo "Running k8s install script on worker node..."
        ssh "${VM_USER}@${worker_public_ip}" sudo ./install_kubernetes_worker.sh
    done
}

do_dns() {
    echo "Setting up coredns..."

    controller_public_ip=$(get_public_ip "$CONTROLLER_NODE_NAME")

    ssh "${VM_USER}@${controller_public_ip}" \
        kubectl apply -f https://storage.googleapis.com/kubernetes-the-hard-way/coredns.yaml
}

provision() {
    echo "Provisioning cluster..."

    do_certs
    do_kubeconfigs
    do_etcd
    do_k8s_controller
    do_k8s_workers
}

provision