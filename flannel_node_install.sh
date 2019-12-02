#!/bin/bash
ETCD_ENDPOINTS=${1:-"default"}

flannel_network_dir=/kubernetes/network
bin_dir=/opt/kubernetes/bin
ca_dir=/opt/kubernetes/ssl
cfg_dir=/opt/kubernetes/cfg
function install_flannel_in_all_nodes(){
echo "生成 flannel 配置"
sleep 1
cat > ${cfg_dir}/flanneld.conf << SUCESS
FLANNEL_OPTIONS="-etcd-prefix=$flannel_network_dir \
-etcd-endpoints=${ETCD_ENDPOINTS} \
-etcd-cafile=${ca_dir}/ca.pem \
-etcd-certfile=${ca_dir}/flanneld.pem \
-etcd-keyfile=${ca_dir}/flanneld-key.pem"
SUCESS
 

echo "生成 flannel 系统服务启动文件"
sleep 1
cat > /usr/lib/systemd/system/flanneld.service << SUCESS
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service
 
[Service]
Type=notify
EnvironmentFile=$cfg_dir/flanneld.conf
ExecStart=${bin_dir}/flanneld --ip-masq \$FLANNEL_OPTIONS
ExecStartPost=${bin_dir}/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure
 
[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
SUCESS
 
systemctl daemon-reload
systemctl enable flanneld && systemctl restart flanneld && systemctl status flanneld
 
echo "让 docker 使用flannel网络"
ExecStartNum=`grep -n 'ExecStart' /usr/lib/systemd/system/docker.service|awk -F: '{print $1}'`
if [[ ${ExecStartNum}x != "x" ]];then sed -i "${ExecStartNum}i\EnvironmentFile=/run/flannel/docker" /usr/lib/systemd/system/docker.service;sed -r -i "s#ExecStart=(.*)#ExecStart=\1 \$DOCKER_NETWORK_OPTIONS#g" /usr/lib/systemd/system/docker.service;fi
systemctl daemon-reload 
systemctl enable docker && systemctl restart docker && systemctl status docker

}

install_flannel_in_all_nodes


































