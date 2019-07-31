#!/bin/bash

set -e
set -o pipefail

export KUBERNETES_VERSION=v1.12.0

die() {
    echo $1
    echo "exiting..."
    exit 1
}

export -f die

export VM_SIZE=${VM_SIZE:-'s-1vcpu-1gb'}
export VM_IMAGE=${VM_IMAGE:-'ubuntu-18-10-x64'}
export VM_USER=${VM_USER:-'root'}
export REGION=${REGION:-'fra1'}
export FIREWALL_NAME=${FIREWALL_NAME:-'kubernetes-fire-wall'}
export FIREWALL_ID=${FIREWALL_ID:-}
export CONTROLLER_NODE_NAME=${CONTROLLER_NODE_NAME:-'controller'}
export NUM_CONTROLLERS=${NUM_CONTROLLERS:-1}
export WORKER_NODE_NAME=${WORKER_NODE_NAME:-'worker'}
export NUM_WORKERS=${NUM_WORKERS:-1}

[ -z "${SSH_FINGERPRINT}" ] && die "SSH_FINGERPRINT is not set"
command -v cfssljson > /dev/null 2>&1 || die "cfssl and cfssljson are required"
command -v cfssl > /dev/null 2>&1 || die "cfssl and cfssljson are required"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

get_droplet_info() {
    droplet_id=$1
    field=$2
    echo $(doctl compute droplet get "$droplet_id" --format "$field" | tail -1)
}

export -f get_droplet_info

get_public_ip() {
    instance=${1}
    droplet_id=$(get_droplet_id "$instance")
    echo $(get_droplet_info "$droplet_id" 'Public IPv4')
}

export -f get_public_ip

get_private_ip() {
    instance=${1}
    droplet_id=$(get_droplet_id "$instance")
    echo $(get_droplet_info "$droplet_id" 'Private IPv4')
}

export -f get_private_ip

get_instance_public_ips() {
    public_ips=$(get_public_ip "$CONTROLLER_NODE_NAME")
    for i in $(seq 1 "${NUM_WORKERS}"); do
        instance="${WORKER_NODE_NAME}-${i}"
        public_ips="$public_ips,$(get_public_ip "$instance")"
    done

    echo ${public_ips[@]}
}

export -f get_instance_public_ips

get_instance_private_ips() {
    private_ips=$(get_private_ip "$CONTROLLER_NODE_NAME")
    for i in $(seq 1 "${NUM_WORKERS}"); do
        instance="${WORKER_NODE_NAME}-${i}"
        private_ips="$private_ips,$(get_private_ip ${instance})"
    done

    echo ${private_ips[@]}
}

export -f get_instance_private_ips

get_or_create_firewall() {
    firewall=($(doctl compute firewall list --format 'ID,Name' | grep " $FIREWALL_NAME"))
    if [[ !"${#firewall}" -gt "0" ]]; then
        firewall=$(doctl compute firewall create \
            --name "${FIREWALL_NAME}" \
            --format 'ID,Name' \
            --inbound-rules "protocol:tcp,ports:all,address:0.0.0.0/0,address:::/0 protocol:udp,ports:all,address:0.0.0.0/0,address:::/0 protocol:icmp,address:0.0.0.0/0,address:::/0" \
            --outbound-rules "protocol:tcp,ports:all,address:0.0.0.0/0,address:::/0 protocol:udp,ports:all,address:0.0.0.0/0,address:::/0 protocol:icmp,address:0.0.0.0/0,address:::/0" \
        )
    fi

    echo ${firewall[0]}
}

get_droplet_id() {
    node_name=$1
    droplet=($(
        doctl compute droplet list --format "ID,Name" | tail -n +2 | grep "$node_name"
    ))
    echo ${droplet[0]}
}

export -f get_droplet_id

create_controller_node() {
    droplet_id=$(get_droplet_id $CONTROLLER_NODE_NAME)

    if [[ -z $droplet_id ]]; then
        echo "Creating controller node..."
        droplet_id=$(doctl compute droplet create "${CONTROLLER_NODE_NAME}" \
            --region "${REGION}" \
            --ssh-keys "${SSH_FINGERPRINT}" \
            --size "${VM_SIZE}" \
            --image "${VM_IMAGE}" \
            --enable-private-networking \
            --format ID \
            --wait | tail -1
    )
    fi
}

create_worker_nodes() {
    for i in $(seq 1 ${NUM_WORKERS}); do
        worker="${WORKER_NODE_NAME}-${i}"

        droplet_id=$(get_droplet_id "$worker")

        if [[ -z $droplet_id ]]; then
            echo "Creating worker node ${worker}..."
            doctl compute droplet create "${worker}" \
            --region "${REGION}" \
            --ssh-keys "${SSH_FINGERPRINT}" \
            --size "${VM_SIZE}" \
            --image "${VM_IMAGE}" \
            --enable-private-networking \
            --user-data "pod-cidr=10.200.${i}.0/24" \
            --format ID \
            --wait
        fi
    done
}

add_droplet_firewall_rules_and_enable_ip_forward() {
    firewall_id=$1
    droplet_id=$2

    doctl compute firewall add-droplets "${firewall_id}" --droplet-ids "${droplet_id}"

    max=60; i=0
    until doctl compute ssh "${droplet_id}" --ssh-command "sysctl net.ipv4.ip_forward=1"; do
        i=$((i + 1))
        if [[ $i -eq "10" ]]; then
            die "droplet=$droplet_id, firewall=$firewall_id: Timed out waiting for firewall rule"
        fi
        echo 'waiting for firewall rule to be effective'
        echo "droplet=$droplet_id, firewall=$firewall_id: firewall rule not yet active..."
        sleep 5
    done
}

add_firewall_rules() {
    firewall_id=$(get_or_create_firewall)

    echo "Setting up controller node..."
    controller_id=$(get_droplet_id $CONTROLLER_NODE_NAME)
    add_droplet_firewall_rules_and_enable_ip_forward $firewall_id $controller_id

    for i in $(seq 1 ${NUM_WORKERS}); do
        worker_name="${WORKER_NODE_NAME}-${i}"
        echo "Setting up worker node ${worker_name}..."
        worker_id=$(get_droplet_id $worker_name)
        add_droplet_firewall_rules_and_enable_ip_forward $firewall_id $worker_id
    done
}

"${DIR}/provision.sh"
