set -e
set -o pipefail

generate_encryption_config() {
    dst_file="$1"
    encryption_key=$(head -c 32 /dev/urandom | base64)

    sed "s#ENCRYPTION_KEY#${encryption_key}#g" \
        "${DIR}/etc/encryption-config.yaml" > "${dst_file}"
}

generate_certificates() {
    old_pwd=$(pwd)

    cd $CERTS_DIR

    echo "Generating CA certificate and private key..."
    cfssl gencert -initca "${CA_CONFIG_DIR}/csr.json" | cfssljson -bare ca

    echo "Generating API server certificates..."

    public_ips=$(get_instance_public_ips)
    private_ips=$(get_instance_private_ips)
    hostnames="$public_ips,$private_ips,0.0.0.0,127.0.0.1,kubernetes.default"

    cfssl gencert \
        -ca=ca.pem \
        -ca-key=ca-key.pem \
        -config="${CA_CONFIG_DIR}/config.json" \
        -hostname="$hostnames" \
        -profile=kubernetes \
        "${CA_CONFIG_DIR}/kubernetes-csr.json" | cfssljson -bare kubernetes

    # generate service-account certificates
    cfssl gencert \
        -ca=ca.pem \
        -ca-key=ca-key.pem \
        -config="${CA_CONFIG_DIR}/config.json" \
        -profile=kubernetes \
        "${CA_CONFIG_DIR}/service-account-csr.json" | cfssljson -bare service-account

    # generate admin certificates
    cfssl gencert \
        -ca=ca.pem \
        -ca-key=ca-key.pem \
        -config="${CA_CONFIG_DIR}/config.json" \
        -profile=kubernetes \
        "${CA_CONFIG_DIR}/admin-csr.json" | cfssljson -bare admin

    # generate controller-manager certificates
    cfssl gencert \
        -ca=ca.pem \
        -ca-key=ca-key.pem \
        -config="${CA_CONFIG_DIR}/config.json" \
        -profile=kubernetes \
        "${CA_CONFIG_DIR}/kube-controller-manager-csr.json" | cfssljson -bare kube-controller-manager

    # generate proxy certificates
    cfssl gencert \
        -ca=ca.pem \
        -ca-key=ca-key.pem \
        -config="${CA_CONFIG_DIR}/config.json" \
        -profile=kubernetes \
        "${CA_CONFIG_DIR}/kube-proxy-csr.json" | cfssljson -bare kube-proxy

    # generate scheduler certificates
    cfssl gencert \
        -ca=ca.pem \
        -ca-key=ca-key.pem \
        -config="${CA_CONFIG_DIR}/config.json" \
        -profile=kubernetes \
        "${CA_CONFIG_DIR}/kube-scheduler-csr.json" | cfssljson -bare kube-scheduler

    echo "Generating encryption config..."
    encryption_config="${CERTS_DIR}/encryption-config.yaml"
    generate_encryption_config "${encryption_config}"

    echo "Copying keys to controller..."
    controller_public_ip=$(get_public_ip "$CONTROLLER_NODE_NAME")
    scp "ca.pem" \
        "ca-key.pem" \
        "kubernetes-key.pem" \
        "kubernetes.pem" \
        "service-account-key.pem" \
        "service-account.pem" \
        "encryption-config.yaml" \
        "${VM_USER}@${controller_public_ip}:~/"

    for i in $(seq 1 "${NUM_WORKERS}"); do
        instance="${WORKER_NODE_NAME}-${i}"
        instance_csr_config="${CERTS_DIR}/${instance}-csr.json"

        echo "Generating certificates for ${instance}"

        sed "s/INSTANCE/${instance}/g" "${CA_CONFIG_DIR}/instance-csr.json" > "${instance_csr_config}"

        public_ip=$(get_public_ip "$instance")
        private_ip=$(get_private_ip "$instance")

        cfssl gencert \
            -ca=ca.pem \
            -ca-key=ca-key.pem \
            -config="${CA_CONFIG_DIR}/config.json" \
            -hostname="${instance},${public_ip},${private_ip}" \
            -profile=kubernetes \
            "${instance_csr_config}" | cfssljson -bare "${instance}"

        scp "ca.pem" "${instance}-key.pem" "${instance}.pem" "${VM_USER}@${public_ip}:~/"
    done

    cd $old_pwd
}
