#!/bin/bash
ETCD_NAME=${1:-"default"}
ETCD_LISTEN_IP=${2:-"0.0.0.0"}
ETCD_INITIAL_CLUSTER=${3:-}
bin_dir=/opt/kubernetes/bin
ca_dir=/opt/kubernetes/ssl
cfg_dir=/opt/kubernetes/cfg
ETCD_DATA_DIR=/data/k8s/etcd/data
ETCD_WAL_DIR=/data/k8s/etcd/wal
rm -rf ${ETCD_WAL_DIR} && rm -rf ${ETCD_DATA_DIR}
mkdir -p ${ETCD_WAL_DIR}
mkdir -p ${ETCD_DATA_DIR}

function etcd_service_util(){
echo "生成etcd配置文件"
cat > $cfg_dir/etcd.conf << SUCESS
# [member]
ETCD_NAME=$ETCD_NAME
ETCD_DATA_DIR=$ETCD_DATA_DIR
ETCD_WAL_DIR=$ETCD_WAL_DIR
ETCD_LISTEN_PEER_URLS="https://${ETCD_LISTEN_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="https://${ETCD_LISTEN_IP}:2379,http://127.0.0.1:2379"
ETCD_AUTO_COMPACTION_RETENTION="1"
ETCD_AUTO_COMPACTION_MODE="periodic"
ETCD_MAX_REQUEST_BYTES="33554432"
ETCD_QUOTA_BACKEND_BYTES="6442450944"
ETCD_HEARTBEAT_INTERVAL="250"
ETCD_ELECTION_TIMEOUT="2000"
 
#[cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${ETCD_LISTEN_IP}:2380"
ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER}"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-0"
ETCD_ADVERTISE_CLIENT_URLS="https://${ETCD_LISTEN_IP}:2379"

#[security]
ETCD_CLIENT_CERT_AUTH="true"
ETCD_CERT_FILE=${ca_dir}/etcd.pem
ETCD_KEY_FILE=${ca_dir}/etcd-key.pem
ETCD_TRUSTED_CA_FILE =${ca_dir}/ca.pem
ETCD_PEER_TRUSTED_CA_FILE=${ca_dir}/ca.pem
ETCD_PEER_CLIENT_CERT_AUTH="true"
ETCD_PEER_CERT_FILE=${ca_dir}/etcd.pem
ETCD_PEER_KEY_FILE=${ca_dir}/etcd-key.pem
SUCESS
echo "生成 etcd 系统服务启动文件"
sleep 1
cat > /usr/lib/systemd/system/etcd.service << SUCESS
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos
 
[Service]
Type=notify
WorkingDirectory=${ETCD_DATA_DIR}
EnvironmentFile=-${cfg_dir}/etcd.conf
ExecStart=$bin_dir/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
 
[Install]
WantedBy=multi-user.target
SUCESS




# cat > /usr/lib/systemd/system/etcd.service << SUCESS
# [Unit]
# Description=Etcd Server
# After=network.target
# After=network-online.target
# Wants=network-online.target

# [Service]
# Type=notify
# WorkingDirectory=${ETCD_DATA_DIR}
# ExecStart=/usr/bin/etcd \
  # --data-dir=${ETCD_DATA_DIR} \
  # --wal-dir=${ETCD_WAL_DIR} \
  # --name=${ETCD_NAME} \
  # --cert-file=${ca_dir}/etcd.pem \
  # --key-file=${ca_dir}/etcd-key.pem \
  # --trusted-ca-file=${ca_dir}/ca.pem \
  # --peer-cert-file=${ca_dir}/etcd.pem \
  # --peer-key-file=${ca_dir}/etcd-key.pem \
  # --peer-trusted-ca-file=${ca_dir}/ca.pem \
  # --peer-client-cert-auth \
  # --client-cert-auth \
  # --listen-peer-urls=https://${ETCD_LISTEN_IP}:2380 \
  # --initial-advertise-peer-urls=https://${${ETCD_LISTEN_IP}}:2380 \
  # --listen-client-urls=https://${${ETCD_LISTEN_IP}}:2379,http://127.0.0.1:2379 \
  # --advertise-client-urls=https://${${ETCD_LISTEN_IP}}:2379 \
  # --initial-cluster-token=etcd-cluster-0 \
  # --initial-cluster=etcd1=${ETCD_INITIAL_CLUSTER} \
  # --initial-cluster-state=new \
  # --auto-compaction-mode=periodic \
  # --auto-compaction-retention=1 \
  # --max-request-bytes=33554432 \
  # --quota-backend-bytes=6442450944 \
  # --heartbeat-interval=250 \
  # --election-timeout=2000
# Restart=on-failure
# RestartSec=5
# LimitNOFILE=65536

# [Install]
# WantedBy=multi-user.target

# SUCESS


}
etcd_service_util
echo "etcd服务启动"
sleep 1
systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd && systemctl status etcd