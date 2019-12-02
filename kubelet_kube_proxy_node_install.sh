#!/bin/bash
ONLINE_EXE_IP=${1:-"default"}
master_local_ip=${2:-}
#kubernetes 服务 IP
CLUSTER_KUBERNETES_SVC_IP="10.10.0.1"
#集群DNS IP
CLUSTER_DNS_IP="10.10.0.2"
#集群DNS域名
CLUSTER_DNS_DOMAIN="cluster.local"
# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"
# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"
flannel_network_dir=/kubernetes/network
bin_dir=/opt/kubernetes/bin
ca_dir=/opt/kubernetes/ssl
cfg_dir=/opt/kubernetes/cfg
kube_data_dir=/data/k8s
echo "export PATH=$PATH:$bin_dir" >> /etc/profile
function install_kubelet_in_all_nodes(){
source /etc/profile
echo "创建kubelet参数配置文件"
cat > $cfg_dir/kubelet-config.yaml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: "$ONLINE_EXE_IP"
staticPodPath: ""
syncFrequency: 1m
fileCheckFrequency: 20s
httpCheckFrequency: 20s
staticPodURL: ""
port: 10250
readOnlyPort: 0
rotateCertificates: true
serverTLSBootstrap: true
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "$ca_dir/ca.pem"
authorization:
  mode: Webhook
registryPullQPS: 0
registryBurst: 20
eventRecordQPS: 0
eventBurst: 20
enableDebuggingHandlers: true
enableContentionProfiling: true
healthzPort: 10248
healthzBindAddress: "$ONLINE_EXE_IP"
clusterDomain: "${CLUSTER_DNS_DOMAIN}"
clusterDNS:
  - "${CLUSTER_DNS_SVC_IP}"
nodeStatusUpdateFrequency: 10s
nodeStatusReportFrequency: 1m
imageMinimumGCAge: 2m
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
volumeStatsAggPeriod: 1m
kubeletCgroups: ""
systemCgroups: ""
cgroupRoot: ""
cgroupsPerQOS: true
cgroupDriver: cgroupfs
runtimeRequestTimeout: 10m
hairpinMode: promiscuous-bridge
maxPods: 220
podCIDR: "${CLUSTER_CIDR}"
podPidsLimit: -1
resolvConf: /etc/resolv.conf
maxOpenFiles: 1000000
kubeAPIQPS: 1000
kubeAPIBurst: 2000
serializeImagePulls: false
evictionHard:
  memory.available:  "100Mi"
nodefs.available:  "10%"
nodefs.inodesFree: "5%"
imagefs.available: "15%"
evictionSoft: {}
enableControllerAttachDetach: true
failSwapOn: true
containerLogMaxSize: 20Mi
containerLogMaxFiles: 10
systemReserved: {}
kubeReserved: {}
systemReservedCgroup: ""
kubeReservedCgroup: ""
enforceNodeAllocatable: ["pods"]
EOF
echo "创建kubelet systemd 文件"
cat > /usr/lib/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service
    
[Service]
WorkingDirectory=$kube_data_dir/kubelet
EnvironmentFile=-$cfg_dir/kubelet.conf
ExecStart=$bin_dir/kubelet --logtostderr=true \\
--container-runtime=docker \\
--container-runtime-endpoint=unix:///var/run/dockershim.sock \\
--image-pull-progress-deadline=15m \\
--volume-plugin-dir=${kube_data_dir}/kubelet/kubelet-plugins/volume/exec/ \\
--fail-swap-on=False \\
--v=2 \\
--address=$ONLINE_EXE_IP \\
--hostname-override=$ONLINE_EXE_IP \\
--kubeconfig=$cfg_dir/kubelet.kubeconfig \\
--bootstrap-kubeconfig=$cfg_dir/kubelet-bootstrap.kubeconfig \\
--config=$cfg_dir/kubelet-config.yaml \\
--cert-dir=$ca_dir \\
--pod-infra-container-image=registry.cn-shanghai.aliyuncs.com/k8s_pkg/pause:3.1 \\
--root-dir=$kube_data_dir/kubelet
Restart=always
RestartSec=5
StartLimitInterval=0
    
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable kubelet && systemctl restart kubelet


sleep 1
 #------------------------------------------------------------------------------------------------------------
 echo "创建 kube-proxy kubeconfig 文件"
cd ${cfg_dir} && ${bin_dir}/kubectl config set-cluster kubernetes \
  --certificate-authority=$ca_dir/ca.pem \
  --embed-certs=true \
  --server=https://${master_local_ip}:6443 \
  --kubeconfig=kube-proxy.kubeconfig
 
cd ${cfg_dir} && ${bin_dir}/kubectl config set-credentials kube-proxy \
  --client-certificate=$ca_dir/kube-proxy.pem \
  --client-key=$ca_dir/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
 
cd ${cfg_dir} && ${bin_dir}/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
 
cd ${cfg_dir} && ${bin_dir}/kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
echo "生成 kube-proxy 服务配置文件"
cat > $cfg_dir/kube-proxy.conf << SUCESS
KUBE_PROXY_OPTS="--logtostderr=true \\
--hostname-override=$ONLINE_EXE_IP \\
--v=2 \\
--config=$cfg_dir/kube-proxy-config.yaml "
SUCESS
 echo "创建 kube-proxy配置文件"
 cat > $cfg_dir/kube-proxy-config.yaml <<EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  burst: 200
  kubeconfig: "$cfg_dir/kube-proxy.kubeconfig"
  qps: 100
bindAddress: ${ONLINE_EXE_IP}
healthzBindAddress: ${ONLINE_EXE_IP}:10256
metricsBindAddress: ${ONLINE_EXE_IP}:10249
enableProfiling: true
clusterCIDR: ${CLUSTER_CIDR}
hostnameOverride: ${ONLINE_EXE_IP}
mode: "ipvs"
portRange: ""
kubeProxyIPTablesConfiguration:
  masqueradeAll: false
kubeProxyIPVSConfiguration:
  scheduler: rr
  excludeCIDRs: []
EOF
echo "生成 kube-proxy 系统服务启动文件"
cat > /usr/lib/systemd/system/kube-proxy.service << SUCESS
[Unit]
Description=Kubernetes Proxy
After=network.target
 
[Service]
WorkingDirectory=${kube_data_dir}/kube-proxy
EnvironmentFile=-$cfg_dir/kube-proxy.conf
ExecStart=${bin_dir}/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure
 
[Install]
WantedBy=multi-user.target
SUCESS
echo "启动kubelet和kube-proxy服务"
systemctl daemon-reload && systemctl enable kube-proxy && systemctl restart kube-proxy
}
install_kubelet_in_all_nodes