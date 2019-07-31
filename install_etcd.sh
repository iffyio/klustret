ETCD_VERSION=3.3.9
export ETCDCTL_API=3

install_etcd() {
    echo "Fetching etcd v${ETCD_VERSION}"

    etcd_uri="https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz"
    wget -q --show-progress --https-only --timestamping "$etcd_uri"

    echo "Installing etcd v${ETCD_VERSION}"
    tar -xvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    sudo mv etcd-v${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/

    sudo mkdir -p /etc/etcd /var/lib/etcd
    sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

    etcd_name=$(hostname -s)
    private_ip=$(curl http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)

    sudo mkdir -p /etc/systemd/system/
    sudo mv etcd.service /etc/systemd/system/etcd.service
    sudo sed -i "s/INTERNAL_IP/${private_ip}/g" /etc/systemd/system/etcd.service
    sudo sed -i "s/ETCD_NAME/${etcd_name}/g" /etc/systemd/system/etcd.service

    echo "Starting etcd systemd service..."
    sudo systemctl daemon-reload
    sudo systemctl enable etcd
    sudo systemctl start etcd

    echo "Waiting for etcd to start..."
    max=60; i=0
    until etcdctl member list --endpoints=https://127.0.0.1:2379 --cacert=/etc/etcd/ca.pem --cert=/etc/etcd/kubernetes.pem --key=/etc/etcd/kubernetes-key.pem ; do
        i=$((i + 1))
        if [[ $i -eq "10" ]]; then
            echo "Timed out waiting for etcd to be ready"
            exit 1
        fi
        echo 'Etcd not yet ready, will retry in 5secs...'
        sleep 5
    done
}

install_etcd
