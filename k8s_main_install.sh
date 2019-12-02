#!/bin/bash
#master执行
#########################################
#K8S版本：1.16.3
#etcd版本：3.3.13
#flannel版本：v0.11.0
#########################################
bin_dir=/opt/kubernetes/bin
ca_dir=/opt/kubernetes/ssl
cfg_dir=/opt/kubernetes/cfg
flannel_network_dir=/kubernetes/network
kube_data_dir=/data/k8s
#kubernetes 服务 IP
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"
#集群DNS域名
CLUSTER_DNS_DOMAIN="cluster.local"
# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"
# 服务网段，部署前路由不可达，部署后集群内路由可达(kube-proxy 保证)
SERVICE_CIDR="10.254.0.0/16"
# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"
#定义字典
declare -A etcd_names
all_nodes=('192.168.0.5' '192.168.0.6' '192.168.0.10')
etcd_names=(['etcd1']='192.168.0.5' ['etcd2']='192.168.0.6' ['etcd3']='192.168.0.10')
kube_master=('192.168.0.5')
kube_nodes=('192.168.0.6' '192.168.0.10')

# all_nodes=('192.168.90.229' '192.168.90.230' '192.168.90.231')	#所有节点IP
# kube_master=('192.168.90.229')
# kube_nodes=('192.168.90.230' '192.168.90.231')		#K8S node节点IP
#etcd_names=(['etcd1']='192.168.90.229' ['etcd2']='192.168.90.230' ['etcd3']='192.168.90.231')		#etcd节点IP
# all_nodes=('192.168.0.44' '192.168.0.45' '192.168.0.17' '192.168.0.46' '192.168.0.33')
# etcd_names=(['etcd1']='192.168.0.44' ['etcd2']='192.168.0.45' ['etcd3']='192.168.0.46' ['etcd4']='192.168.0.17' ['etcd5']='192.168.0.33')
# kube_master=('192.168.0.44')
# kube_nodes=('192.168.0.45' '192.168.0.46' '192.168.0.17' '192.168.0.33')
# all_nodes=('192.168.0.172' '192.168.0.173' '192.168.0.174')	#所有节点IP
# kube_master=('192.168.0.172')   #master节点IP
# kube_nodes=('192.168.0.173' '192.168.0.174')		#K8S node节点IP
# etcd_names=(['etcd1']='192.168.0.172' ['etcd2']='192.168.0.173' ['etcd3']='192.168.0.174')		#etcd节点IP
#本机IP
local_ip=$(ip addr | grep inet | egrep -v '(127.0.0.1|inet6|docker|flannel)' | awk '{print $2}' | tr -d "addr:" | head -n 1 | cut -d / -f1)
echo "export PATH=$PATH:$bin_dir" >> /etc/profile
source /etc/profile
mkdir -p /opt/kubernetes/{bin,cfg,ssl}
mkdir -p ${flannel_network_dir}
mkdir -p ${kube_data_dir}/{kube-apiserver,kube-controller-manager,kube-scheduler,kubelet,kube-proxy}    #在所有master节点上创建以后添加
sleep 2
function set_hostname(){
  echo "------------------------------------------------------------------------------------"
  echo "开始生成/tmp/set_hostname.hosts文件，写入各节点hostname信息"
  echo > /tmp/set_hostname.hosts
  echo "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4" >> /tmp/set_hostname.hosts
  echo "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6" >> /tmp/set_hostname.hosts
  for kube_master_host_name in ${kube_master[@]}
    do
      ((c++))
      echo $kube_master_host_name "k8s-master0"$c >> /tmp/set_hostname.hosts
    done
  for kube_node_host_name in ${kube_nodes[@]}
    do
      ((k++))
      echo $kube_node_host_name "k8s-node0"$k >> /tmp/set_hostname.hosts
    done
  echo "写入到各节点/etc/hosts文件中"
  for host_name in ${all_nodes[@]}
    do
      ssh $host_name "mv /etc/hosts /etc/hosts.bak"
      scp /tmp/set_hostname.hosts $host_name:/etc/hosts
      scp $cfg_dir/set_hostname.sh $host_name:/tmp/set_hostname.sh
    done
  echo "远程执行设置所有节点的hostname"
  for host_name in ${all_nodes[@]}
    do
      ssh $host_name "bash /tmp/set_hostname.sh" 
    done
}
function move_to_opt_kubernetes_dir(){
echo "------------------------------------------------------------------------------------"
echo "移动当前所有可执行文件到/opt/kubernetes/bin和/opt/kubernetes/cfg下"
dir=$(pwd)
cp -a ../bin/* $bin_dir/
cp -a ./* $cfg_dir/
chmod +x -R $bin_dir/*
}
function mkdir_all_nodes(){
echo "------------------------------------------------------------------------------------"
echo "在所有节点创建所需目录"
for i in ${all_nodes[@]}
do
ssh $i "mkdir -p /opt/kubernetes/{bin,cfg,ssl};mkdir -p /kubernetes/network;mkdir -p /opt/kubernetes/bin/cni;mkdir -p ${kube_data_dir}/{kube-apiserver,kube-controller-manager,kube-scheduler,kubelet,kube-proxy}"
done
}
function create_all_ca_file(){
echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建 ca 配置文件"
cat > ca-config.json << SUCESS
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
SUCESS
echo "创建 ca 证书签名请求"
cat > ca-csr.json << SUCESS
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
SUCESS
echo "生成 ca 根证书和私钥"
cd $ca_dir && $bin_dir/cfssl gencert -initca ca-csr.json | $bin_dir/cfssljson -bare ca


echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建 kubernetes 证书签名请求文件"
cat > kubernetes-csr.json << SUCESS
{
     "CN": "kubernetes",
     "hosts": [
       "127.0.0.1",
       "${CLUSTER_KUBERNETES_SVC_IP}",
       "kubernetes",
       "kubernetes.default",
       "kubernetes.default.svc",
       "kubernetes.default.svc.cluster",
       "kubernetes.default.svc.cluster.local"
     ],
     "key": {
         "algo": "rsa",
         "size": 2048
     },
     "names": [
         {
             "C": "CN",
             "ST": "BeiJing",
             "L": "BeiJing",
             "O": "k8s",
             "OU": "System"
         }
     ]
}
SUCESS
#替换kubernetes-csr.json证书签名请求文件中的hosts为所有节点IP
for i in ${all_nodes[@]}
do
sed -i '5i        "'${i}'",' kubernetes-csr.json
done
echo "生成 kubernetes 证书和私钥"
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kubernetes-csr.json | $bin_dir/cfssljson -bare kubernetes
echo "------------------------------------------------------------------------------------"
#admin证书用于kubectl认证
cd ${ca_dir}
echo "创建 admin 证书签名请求文件"
cat > admin-csr.json << SUCESS
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
SUCESS
echo "生成 admin 证书和私钥"
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | $bin_dir/cfssljson -bare admin
echo "------------------------------------------------------------------------------------"
cd ${ca_dir}
echo "创建 kube-proxy 证书签名请求文件"
cat > kube-proxy-csr.json << SUCESS
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
SUCESS
 
echo "生成 kube-proxy 客户端证书和私钥"
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes  kube-proxy-csr.json | $bin_dir/cfssljson -bare kube-proxy

echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建etcd证书和私钥"
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
   "127.0.0.1"
 ],
  "key": {
    "algo": "rsa",
   "size": 2048
  },
  "names": [
    {
     "C": "CN",
     "ST": "BeiJing",
     "L": "BeiJing",
     "O": "k8s",
     "OU": "System"
    }
  ]
}
EOF
#替换 etcd-csr.json证书签名请求文件中的hosts为所有节点IP
for i in ${etcd_names[@]}
do
sed -i '4i     "'${i}'",' etcd-csr.json
done
echo "开始生成etcd证书和私钥"
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes  etcd-csr.json | $bin_dir/cfssljson -bare etcd

echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建flannel证书和私钥"
cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes flanneld-csr.json | $bin_dir/cfssljson -bare flanneld

echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建metrics-server 使用的证书"
cat > proxy-client-csr.json <<EOF
{
  "CN": "aggregator",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes proxy-client-csr.json | $bin_dir/cfssljson -bare proxy-client

echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建kube-controller-manager 证书和私钥"
cat > kube-controller-manager-csr.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
      "127.0.0.1"
    ],
    "names": [
      {
        "C": "CN",
        "ST": "BeiJing",
        "L": "BeiJing",
        "O": "system:kube-controller-manager",
        "OU": "System"
      }
    ]
}
EOF
#替换 kube-controller-manager-csr.json证书签名请求文件中的hosts为所有节点IP
for i in ${all_nodes[@]}
do
sed -i '8i     "'${i}'",' kube-controller-manager-csr.json
done
sleep 3
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-controller-manager-csr.json | $bin_dir/cfssljson -bare kube-controller-manager

echo "------------------------------------------------------------------------------------"
cd $ca_dir
echo "创建kube-scheduler证书和私钥"
cat > kube-scheduler-csr.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
      "127.0.0.1"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "BeiJing",
        "L": "BeiJing",
        "O": "system:kube-scheduler",
        "OU": "4Paradigm"
      }
    ]
}
EOF
#替换 kube-scheduler-csr.json证书签名请求文件中的hosts为所有节点IP
for i in ${all_nodes[@]}
do
sed -i '4i     "'${i}'",' kube-scheduler-csr.json
done
cd $ca_dir && $bin_dir/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-scheduler-csr.json | $bin_dir/cfssljson -bare kube-scheduler
}
#执行系统初始化文件，安装必备依赖、升级iptables和系统优化等
function system_init_in_all_nodes(){
echo "------------------------------------------------------------------------------------"
echo "在所有节点执行系统优化脚本并安装docker"
for i in ${all_nodes[@]}
do
scp $cfg_dir/system_init.sh $i:$cfg_dir/ 
ssh $i "bash $cfg_dir/system_init.sh" &&
done
}
#分发所有证书文件
function scp_all_ca(){
echo "------------------------------------------------------------------------------------"
echo "开始分发证书文件到所有节点"
for i in ${all_nodes[@]}
do
cd $ca_dir
scp ./* $i:$ca_dir/ 
done
}
#分发所有二进制文件
function scp_all_bin(){
echo "------------------------------------------------------------------------------------"
echo "开始分发所有可执行二进制文件到所有节点"
for i in ${all_nodes[@]}
do
scp -r $bin_dir/* $i:$bin_dir/  
scp $cfg_dir/* $i:$cfg_dir/ 
chmod +x -R $bin_dir/*
done
}
#分发所有配置文件
function scp_all_cfg(){
echo "------------------------------------------------------------------------------------"
echo "分发所有的配置文件"
for i in ${all_nodes[@]}
do
scp $cfg_dir/* $i:$cfg_dir/ 
done
}
#开始执行安装etcd集群，通过etcd_names变量获取各节点信息
function etcd_install(){
echo "------------------------------------------------------------------------------------"
cd ${cfg_dir}
echo "开始执行etcd节点安装程序"
echo > /tmp/etcd_cluster.hosts
echo > /tmp/etcd_c.hosts
for etc_host in ${!etcd_names[@]}
do
echo -n $etc_host'=https://'${etcd_names[$etc_host]}':2380,' >> /tmp/etcd_c.hosts
cluster=$(cat /tmp/etcd_c.hosts|sed 's/,$//g'|sed '/^$/d' > /tmp/etcd_cluster.hosts)
done
#生成etcd集群信息 etcd2=https://192.168.0.173:2380,etcd3=https://192.168.0.174:2380,etcd1=https://192.168.0.172:2380
etcd_cluster_nodes=$(cat /tmp/etcd_cluster.hosts)
#执行脚本，在所有etcd节点上，传入三个参数1：当前在执行etcd节点的别名  2：当前在执行etcd节点的IP   3：etcd集群信息  并行执行
for etc_host in ${!etcd_names[@]}
do
ssh ${etcd_names[$etc_host]} "bash ${cfg_dir}/create_etcd_node.sh '$etc_host' '${etcd_names[$etc_host]}' '$etcd_cluster_nodes'" &
done
}

#在node节点上安装flannel
function node_install_flannel(){
echo "------------------------------------------------------------------------------------"
echo "开始安装flannel服务"
cd ${cfg_dir} &&
#安装flannel
echo > /tmp/etcd_endpoints.hosts
echo > /tmp/etcd_e.hosts
for etc_host in ${!etcd_names[@]}
do
echo -n 'https://'${etcd_names[$etc_host]}':2379 ,' >> /tmp/etcd_e.hosts
ETCD_ENDPOINTS=$(cat /tmp/etcd_e.hosts|sed 's/,$//g'|sed '/^$/d' > /tmp/etcd_endpoints.hosts)
done
#生成ETCD_ENDPOINTS_NODES信息  flannel用到的etcd集群信息 https://192.168.0.173:2379,https://192.168.0.174:2379,https://192.168.0.172:2379
ETCD_ENDPOINTS_NODES=$(cat /tmp/etcd_endpoints.hosts|sed 's/ //g')
echo "------------------------------------------------------------------------------------"
echo "向etcd中写入flannel KEY"
sleep 30
echo "这里执行sleep30秒的操作，等待所有机器上的etcd启动，然后向etcd写入flannel 网络信息的KEY值"
#master节点操作
#etcdctl --endpoints=https://192.168.0.36:2379,https://192.168.0.38:2379,https://192.168.0.35:2379 --ca-file=/opt/kubernetes/ssl/ca.pem --cert-file=/opt/kubernetes/ssl/kubernetes.pem --key-file=/opt/kubernetes/ssl/kubernetes-key.pem mk /kubernetes/network/config '{"Network":"10.10.0.0/16","SubnetLen":24,"Backend":{"Type":"vxlan"}}'
$bin_dir/etcdctl --endpoints="$ETCD_ENDPOINTS_NODES" --ca-file=$ca_dir/ca.pem --cert-file=$ca_dir/flanneld.pem --key-file=$ca_dir/flanneld-key.pem mk $flannel_network_dir/config '{"Network":"'${CLUSTER_CIDR}'","SubnetLen":21,"Backend":{"Type":"vxlan"}}' &&
echo "------------------------------------------------------------------------------------"
echo "在node节点执行flannel安装脚本"
#在所有的work节点安装flannel，传入一个参数 1：etcd集群信息
for kube_node in ${kube_nodes[@]}
do
ETCD_ENDPOINTS_NODES=$(cat /tmp/etcd_endpoints.hosts|sed 's/ //g')
ssh $kube_node "bash ${cfg_dir}/flannel_node_install.sh '$ETCD_ENDPOINTS_NODES'" 
done
}


function kube_api_server(){
sleep 30
echo "--------------------------------KUBE-API-SERVER部分----------------------------------------------------"
echo "开始在master节点上安装"
#ETCD_ENDPOINTS_NODES信息
ETCD_ENDPOINTS_NODES=$(cat /tmp/etcd_endpoints.hosts|sed 's/ //g')
###############################kube-api-server部分###################################
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
echo "创建加密配置文件"
cat > $cfg_dir/encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
echo "创建审计策略文件"
cat > $cfg_dir/audit-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
  # The following requests were manually identified as high-volume and low-risk, so drop them.
  - level: None
    resources:
      - group: ""
        resources:
          - endpoints
          - services
          - services/status
    users:
      - 'system:kube-proxy'
    verbs:
      - watch
   
  - level: None
    resources:
      - group: ""
        resources:
          - nodes
          - nodes/status
    userGroups:
      - 'system:nodes'
    verbs:
      - get
   
  - level: None
    namespaces:
      - kube-system
    resources:
      - group: ""
        resources:
          - endpoints
    users:
      - 'system:kube-controller-manager'
      - 'system:kube-scheduler'
      - 'system:serviceaccount:kube-system:endpoint-controller'
    verbs:
      - get
      - update
   
  - level: None
    resources:
      - group: ""
        resources:
          - namespaces
          - namespaces/status
          - namespaces/finalize
    users:
      - 'system:apiserver'
    verbs:
      - get
   
  # Don't log HPA fetching metrics.
  - level: None
    resources:
      - group: metrics.k8s.io
    users:
      - 'system:kube-controller-manager'
    verbs:
      - get
      - list
   
  # Don't log these read-only URLs.
  - level: None
    nonResourceURLs:
      - '/healthz*'
      - /version
      - '/swagger*'
   
  # Don't log events requests.
  - level: None
    resources:
      - group: ""
        resources:
          - events
   
  # node and pod status calls from nodes are high-volume and can be large, don't log responses for expected updates from nodes
  - level: Request
    omitStages:
      - RequestReceived
    resources:
      - group: ""
        resources:
          - nodes/status
          - pods/status
    users:
      - kubelet
      - 'system:node-problem-detector'
      - 'system:serviceaccount:kube-system:node-problem-detector'
    verbs:
      - update
      - patch
   
  - level: Request
    omitStages:
      - RequestReceived
    resources:
      - group: ""
        resources:
          - nodes/status
          - pods/status
    userGroups:
      - 'system:nodes'
    verbs:
      - update
      - patch
   
  # deletecollection calls can be large, don't log responses for expected namespace deletions
  - level: Request
    omitStages:
      - RequestReceived
    users:
      - 'system:serviceaccount:kube-system:namespace-controller'
    verbs:
      - deletecollection
   
  # Secrets, ConfigMaps, and TokenReviews can contain sensitive & binary data,
  # so only log at the Metadata level.
  - level: Metadata
    omitStages:
      - RequestReceived
    resources:
      - group: ""
        resources:
          - secrets
          - configmaps
      - group: authentication.k8s.io
        resources:
          - tokenreviews
  # Get repsonses can be large; skip them.
  - level: Request
    omitStages:
      - RequestReceived
    resources:
      - group: ""
      - group: admissionregistration.k8s.io
      - group: apiextensions.k8s.io
      - group: apiregistration.k8s.io
      - group: apps
      - group: authentication.k8s.io
      - group: authorization.k8s.io
      - group: autoscaling
      - group: batch
      - group: certificates.k8s.io
      - group: extensions
      - group: metrics.k8s.io
      - group: networking.k8s.io
      - group: policy
      - group: rbac.authorization.k8s.io
      - group: scheduling.k8s.io
      - group: settings.k8s.io
      - group: storage.k8s.io
    verbs:
      - get
      - list
      - watch
   
  # Default level for known APIs
  - level: RequestResponse
    omitStages:
      - RequestReceived
    resources:
      - group: ""
      - group: admissionregistration.k8s.io
      - group: apiextensions.k8s.io
      - group: apiregistration.k8s.io
      - group: apps
      - group: authentication.k8s.io
      - group: authorization.k8s.io
      - group: autoscaling
      - group: batch
      - group: certificates.k8s.io
      - group: extensions
      - group: metrics.k8s.io
      - group: networking.k8s.io
      - group: policy
      - group: rbac.authorization.k8s.io
      - group: scheduling.k8s.io
      - group: settings.k8s.io
      - group: storage.k8s.io
         
  # Default level for all other requests.
  - level: Metadata
    omitStages:
      - RequestReceived
EOF

echo "生成token"
sleep 1
cat > $cfg_dir/token.csv << SUCESS
`head -c 16 /dev/urandom | od -An -t x | tr -d ' '`,kubelet-bootstrap,10001,"system:kubelet-bootstrap"
SUCESS
echo "------------------------------------------------------------------------------------"
# echo "生成 kube-apiserver 配置"
sleep 1
# cat > /opt/kubernetes/cfg/kube-apiserver.conf << SUCESS
# KUBE_APISERVER_OPTS="--logtostderr=true \\
# --default-not-ready-toleration-seconds=360 \\
# --default-unreachable-toleration-seconds=360 \\
# --feature-gates=DynamicAuditing=true \\
# --max-mutating-requests-inflight=2000 \\
# --max-requests-inflight=4000 \\
# --default-watch-cache-size=200 \\
# --delete-collection-workers=2 \\
# --encryption-provider-config=$cfg_dir/encryption-config.yaml \\
# --insecure-port=0 \\
# --audit-dynamic-configuration \\
# --audit-log-maxage=15 \\
# --audit-log-maxbackup=3 \\
# --audit-log-maxsize=100 \\
# --audit-log-mode=batch \\
# --audit-log-truncate-enabled \\
# --audit-log-batch-buffer-size=20000 \\
# --audit-log-batch-max-size=2 \\
# --audit-log-path=${kube_data_dir}/kube-apiserver/audit.log \\
# --audit-policy-file=$cfg_dir/audit-policy.yaml \\
# --profiling \\
# --anonymous-auth=false \\
# --requestheader-allowed-names="" \\
# --requestheader-client-ca-file=${ca_dir}/ca.pem \\
# --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
# --requestheader-group-headers=X-Remote-Group \\
# --requestheader-username-headers=X-Remote-User \\
# --service-account-key-file=${ca_dir}/ca.pem \\
# --runtime-config=api/all=true \\
# --enable-admission-plugins=NodeRestriction \\
# --v=2 \\
# --etcd-servers=${ETCD_ENDPOINTS_NODES} \\
# --bind-address=${local_ip} \\
# --secure-port=6443 \\
# --advertise-address=${local_ip} \\
# --allow-privileged=true \\
# --service-cluster-ip-range=10.10.0.0/16 \\
# --authorization-mode=RBAC,Node \\
# --kubelet-https=true \\
# --enable-bootstrap-token-auth \\
# --token-auth-file=/opt/kubernetes/cfg/token.csv \\
# --service-node-port-range=30000-50000 \\
# --tls-cert-file=${ca_dir}/kubernetes.pem  \\
# --tls-private-key-file=${ca_dir}/kubernetes-key.pem \\
# --client-ca-file=${ca_dir}/ca.pem \\
# --service-account-key-file=${ca_dir}/ca-key.pem \\
# --etcd-cafile=${ca_dir}/ca.pem \\
# --etcd-certfile=${ca_dir}/kubernetes.pem \\
# --etcd-keyfile=${ca_dir}/kubernetes-key.pem"
# SUCESS
 echo "------------------------------------------------------------------------------------"
echo "生成 kube-apiserver 系统服务启动文件"
sleep 1
cat > /usr/lib/systemd/system/kube-apiserver.service << SUCESS
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=${kube_data_dir}/kube-apiserver
ExecStart=$bin_dir/kube-apiserver \\
  --advertise-address=${local_ip} \\
  --default-not-ready-toleration-seconds=360 \\
  --default-unreachable-toleration-seconds=360 \\
  --feature-gates=DynamicAuditing=true \\
  --max-mutating-requests-inflight=2000 \\
  --max-requests-inflight=4000 \\
  --default-watch-cache-size=200 \\
  --delete-collection-workers=2 \\
  --encryption-provider-config=${cfg_dir}/encryption-config.yaml \\
  --etcd-cafile=${ca_dir}/ca.pem \\
  --etcd-certfile=${ca_dir}/kubernetes.pem \\
  --etcd-keyfile=${ca_dir}/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS_NODES} \\
  --bind-address=${local_ip} \\
  --secure-port=6443 \\
  --tls-cert-file=${ca_dir}/kubernetes.pem \\
  --tls-private-key-file=${ca_dir}/kubernetes-key.pem \\
  --insecure-port=0 \\
  --audit-dynamic-configuration \\
  --audit-log-maxage=15 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-truncate-enabled \\
  --audit-log-path=${K8S_DIR}/kube-apiserver/audit.log \\
  --audit-policy-file=${cfg_dir}/audit-policy.yaml \\
  --profiling \\
  --anonymous-auth=false \\
  --client-ca-file=${ca_dir}/ca.pem \\
  --enable-bootstrap-token-auth=true \\
  --requestheader-allowed-names="aggregator" \\
  --requestheader-client-ca-file=${ca_dir}/ca.pem \\
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --service-account-key-file=${ca_dir}/ca.pem \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=api/all=true \\
  --enable-admission-plugins=NodeRestriction \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --event-ttl=168h \\
  --kubelet-certificate-authority=${ca_dir}/ca.pem \\
  --kubelet-client-certificate=${ca_dir}/kubernetes.pem \\
  --kubelet-client-key=${ca_dir}/kubernetes-key.pem \\
  --kubelet-https=true \\
  --kubelet-timeout=10s \\
  --proxy-client-cert-file=${ca_dir}/proxy-client.pem \\
  --proxy-client-key-file=${ca_dir}/proxy-client-key.pem \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=30000-50000 \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=10
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SUCESS
echo "分发审计策略文件"
for i in ${kube_master[@]}
do
scp $cfg_dir/audit-policy.yaml $i:$cfg_dir/
scp $cfg_dir/encryption-config.yaml $i:$cfg_dir/
scp /usr/lib/systemd/system/kube-apiserver.service $i:/usr/lib/systemd/system/kube-apiserver.service
done
systemctl daemon-reload
systemctl enable kube-apiserver && systemctl restart kube-apiserver
 echo "授予kube-apiserver访问kubelet API的权限"
 $bin_dir/kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
echo "启动"
sleep 1

}


function kube_controller_manager(){
echo "------------------------------------------------------------------------------------"
echo "创建与分发 kube-controller-manager的 kubeconfig 文件"
cd ${cfg_dir} && $bin_dir/kubectl config set-cluster kubernetes \
  --certificate-authority=$ca_dir/ca.pem \
  --embed-certs=true \
  --server=https://${local_ip}:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig
  
cd ${cfg_dir} && $bin_dir/kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=$ca_dir/kube-controller-manager.pem \
  --client-key=$ca_dir/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig
  
cd ${cfg_dir} && $bin_dir/kubectl config set-context system:kube-controller-manager \
  --cluster=kubernetes \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig
  
cd ${cfg_dir} && $bin_dir/kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig
echo "分发kube-controller-manager.kubeconfig到所有master节点"
# echo "生成 kube-controller-manager 配置文件"
# sleep 1
# cat > ${cfg_dir}/kube-controller-manager.conf << SUCESS
# KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=true \\
# --profiling \\
# --controllers=*,bootstrapsigner,tokencleaner \\
# --kube-api-qps=1000 \\
# --kube-api-burst=2000 \\
# --use-service-account-credentials=true \\
# --concurrent-service-syncs=2 \\
# --bind-address=0.0.0.0 \\
# --tls-cert-file==${ca_dir}/kube-controller-manager.pem \\
# --tls-private-key-file==${ca_dir}/kube-controller-manager-key.pem \\
# --authentication-kubeconfig=${cfg_dir}/kube-controller-manager.kubeconfig \\
# --client-ca-file==${ca_dir}/ca.pem \\
# --requestheader-allowed-names="" \\
# --requestheader-client-ca-file==${ca_dir}/ca.pem \\
# --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
# --requestheader-group-headers=X-Remote-Group \\
# --requestheader-username-headers=X-Remote-User \\
# --authorization-kubeconfig=${cfg_dir}/kube-controller-manager.kubeconfig \\
# --cluster-signing-cert-file=${ca_dir}/ca.pem \\
# --cluster-signing-key-file=${ca_dir}/ca-key.pem  \\
# --experimental-cluster-signing-duration=8760h \\
# --horizontal-pod-autoscaler-sync-period=10s \\
# --concurrent-deployment-syncs=10 \\
# --concurrent-gc-syncs=30 \\
# --node-cidr-mask-size=24 \\
# --service-cluster-ip-range=${SERVICE_CIDR} \\
# --pod-eviction-timeout=6m \\
# --terminated-pod-gc-threshold=10000 \\
# --root-ca-file=${ca_dir}/ca.pem \\
# --service-account-private-key-file=${ca_dir}/ca-key.pem \\
# --kubeconfig=${cfg_dir}/kube-controller-manager.kubeconfig \\
# --v=2 "
# SUCESS
 echo "------------------------------------------------------------------------------------"
echo "生成 kube-controller-manager 系统服务启动文件"
sleep 1
cat > /usr/lib/systemd/system/kube-controller-manager.service << SUCESS
[Unit]
Description=Kubernetes Controller Manager
 
[Service]
WorkingDirectory=${kube_data_dir}/kube-controller-manager
ExecStart=${bin_dir}/kube-controller-manager --logtostderr=true \\
--profiling \\
--controllers=*,bootstrapsigner,tokencleaner \\
--kube-api-qps=1000 \\
--kube-api-burst=2000 \\
--use-service-account-credentials=true \\
--concurrent-service-syncs=2 \\
--bind-address=0.0.0.0 \\
--tls-cert-file=${ca_dir}/kube-controller-manager.pem \\
--tls-private-key-file=${ca_dir}/kube-controller-manager-key.pem \\
--authentication-kubeconfig=${cfg_dir}/kube-controller-manager.kubeconfig \\
--client-ca-file=${ca_dir}/ca.pem \\
--requestheader-allowed-names="" \\
--requestheader-client-ca-file=${ca_dir}/ca.pem \\
--requestheader-extra-headers-prefix="X-Remote-Extra-" \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
--authorization-kubeconfig=${cfg_dir}/kube-controller-manager.kubeconfig \\
--cluster-signing-cert-file=${ca_dir}/ca.pem \\
--cluster-signing-key-file=${ca_dir}/ca-key.pem  \\
--experimental-cluster-signing-duration=8760h \\
--horizontal-pod-autoscaler-sync-period=10s \\
--concurrent-deployment-syncs=10 \\
--concurrent-gc-syncs=30 \\
--node-cidr-mask-size=24 \\
--service-cluster-ip-range=${SERVICE_CIDR} \\
--pod-eviction-timeout=6m \\
--terminated-pod-gc-threshold=10000 \\
--root-ca-file=${ca_dir}/ca.pem \\
--service-account-private-key-file=${ca_dir}/ca-key.pem \\
--kubeconfig=${cfg_dir}/kube-controller-manager.kubeconfig \\
--v=2
Restart=on-failure
RestartSec=5
 
[Install]
WantedBy=multi-user.target
SUCESS
echo "为所有master节点分发kube-controller-manager systemd和配置文件"
for kube_master_node in ${kube_master[@]}
do
scp ${cfg_dir}/kube-controller-manager.kubeconfig $kube_master_node:$cfg_dir/
scp ${cfg_dir}/kube-controller-manager.conf $kube_master_node:$cfg_dir/
scp /usr/lib/systemd/system/kube-controller-manager.service $kube_master_node:/usr/lib/systemd/system/kube-controller-manager.service
done

 echo "------------------------------------------------------------------------------------"
echo "启动"
sleep 1
systemctl daemon-reload
systemctl enable kube-controller-manager && systemctl restart kube-controller-manager
for kube_master_node in ${kube_master[@]}
do
ssh $kube_master_node "curl -s http://$kube_master_node:10252/metrics|head"
ssh $kube_master_node "curl -s --cacert $ca_dir/ca.pem http://$kube_master_node:10252/metrics|head"
ssh $kube_master_node "curl -s --cacert $ca_dir/ca.pem http://127.0.0.1:10252/metrics |head"
ssh $kube_master_node "curl -s --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem http://$kube_master_node:10252/metrics |head"
done
}


function kube_scheduler(){
echo "------------------------------------------------------------------------------------"
echo "创建和分发 kube-scheduler kubeconfig 文件"
cd ${cfg_dir} && $bin_dir/kubectl config set-cluster kubernetes \
  --certificate-authority=$ca_dir/ca.pem \
  --embed-certs=true \
  --server=https://${local_ip}:6443 \
  --kubeconfig=kube-scheduler.kubeconfig
 
cd ${cfg_dir} && $bin_dir/kubectl config set-credentials system:kube-scheduler \
  --client-certificate=$ca_dir/kube-scheduler.pem \
  --client-key=$ca_dir/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig
 
cd ${cfg_dir} && $bin_dir/kubectl config set-context system:kube-scheduler \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig
 
cd ${cfg_dir} && $bin_dir/kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig


echo "生成 kube-scheduler 配置文件"
sleep 1
cat > ${cfg_dir}/kube-scheduler.yaml <<EOF
apiVersion: kubescheduler.config.k8s.io/v1alpha1
kind: KubeSchedulerConfiguration
bindTimeoutSeconds: 600
clientConnection:
  burst: 200
  kubeconfig: "${cfg_dir}/kube-scheduler.kubeconfig"
  qps: 100
enableContentionProfiling: false
enableProfiling: true
hardPodAffinitySymmetricWeight: 1
healthzBindAddress: 0.0.0.0:10251
leaderElection:
  leaderElect: true
metricsBindAddress: 0.0.0.0:10251
EOF

cat > ${cfg_dir}/kube-scheduler.conf << SUCESS
KUBE_SCHEDULER_OPTS="--logtostderr=true \\
--config=${cfg_dir}/kube-scheduler.yaml \\
--bind-address=0.0.0.0 \\
--tls-cert-file=$ca_dir/kube-scheduler.pem \\
--tls-private-key-file=$ca_dir/kube-scheduler-key.pem \\
--authentication-kubeconfig=${cfg_dir}/kube-scheduler.kubeconfig \\
--client-ca-file=$ca_dir/ca.pem \\
--requestheader-allowed-names="" \\
--requestheader-client-ca-file=$ca_dir/ca.pem \\
--requestheader-extra-headers-prefix="X-Remote-Extra-" \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User \\
--logtostderr=true \\
--v=2 "
SUCESS
 echo "------------------------------------------------------------------------------------"
echo "生成 kube-scheduler 系统服务启动文件"
sleep 1
cat > /usr/lib/systemd/system/kube-scheduler.service << SUCESS
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
 
[Service]
WorkingDirectory=${kube_data_dir}/kube-scheduler
EnvironmentFile=-$cfg_dir/kube-scheduler.conf
ExecStart=${bin_dir}/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=always
RestartSec=5
StartLimitInterval=0
 
[Install]
WantedBy=multi-user.target
SUCESS
echo "为所有master节点分发kube-scheduler systemd和配置文件"
for kube_master_node in ${kube_master[@]}
do
scp ${cfg_dir}/kube-scheduler.kubeconfig $kube_master_node:$cfg_dir/
scp ${cfg_dir}/kube-scheduler.yaml $kube_master_node:$cfg_dir/
scp ${cfg_dir}/kube-scheduler.conf $kube_master_node:$cfg_dir/
scp /usr/lib/systemd/system/kube-scheduler.service $kube_master_node:/usr/lib/systemd/system/kube-scheduler.service
ssh $kube_master_node "curl -s http://$kube_master_node:10251/metrics |head"
ssh $kube_master_node "curl -s http://127.0.0.1:10251/metrics |head"
ssh $kube_master_node "curl -s --cacert $ca_dir/ca.pem http://$kube_master_node:10251/metrics |head"
ssh $kube_master_node "curl -s --cacert $ca_dir/ca.pem http://127.0.0.1:10251/metrics |head"
ssh $kube_master_node "curl -s --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://$kube_master_node:10259/metrics |head"
done
 echo "------------------------------------------------------------------------------------"
echo "启动"
sleep 1
systemctl daemon-reload
systemctl enable kube-scheduler && systemctl restart kube-scheduler
}


function create_kubectl_config_file(){
echo "------------------------------------------------------------------------------------"
echo "创建kubectl配置文件##################################################################"
echo "设置集群参数"
cd ${cfg_dir} && $bin_dir/kubectl config set-cluster kubernetes \
  --certificate-authority=$ca_dir/ca.pem \
  --embed-certs=true \
  --server=https://${local_ip}:6443 \
  --kubeconfig=kubectl.kubeconfig

echo "设置客户端认证参数"
cd ${cfg_dir} && $bin_dir/kubectl config set-credentials admin \
  --client-certificate=$ca_dir/admin.pem \
  --client-key=$ca_dir/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig
  
echo "设置上下文参数"
cd ${cfg_dir} && $bin_dir/kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig

echo "设置默认上下文"
cd ${cfg_dir} && $bin_dir/kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig
cd ${cfg_dir} && cp -a kubectl.kubeconfig ~/.kube/config
for i in ${kube_master[@]}
do
scp $cfg_dir/kubectl.kubeconfig $i:~/.kube/config
done
#--certificate-authority：验证 kube-apiserver 证书的根证书；
#--client-certificate、--client-key：刚生成的 admin 证书和私钥，连接 kube-apiserver 时使用；
#--embed-certs=true：将 ca.pem 和 admin.pem 证书内容嵌入到生成的 kubectl.kubeconfig 文件中(不加时，写入的是证书文件路径，
}

function create_kubelet_bootstrapping_kubeconfig_file(){
  kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
  echo "创建 kubelet bootstrapping kubeconfig 文件"
  all_node_hostname=$(cat /etc/hosts|grep -Ev "::1|127|master"|awk '{print $2}'|xargs)
  arr_all_node_hostname=($all_node_hostname)
 for node_node_name in ${arr_all_node_hostname[@]}
  do
  echo ">>> ${node_node_name}"
    # 创建 token
    export BOOTSTRAP_TOKEN=$(kubeadm token create \
      --description kubelet-bootstrap-token \
      --groups system:bootstrappers:${node_node_name} \
      --kubeconfig ~/.kube/config)
    
    # 设置集群参数
    cd ${cfg_dir} && ${bin_dir}/kubectl config set-cluster kubernetes \
      --certificate-authority=$ca_dir/ca.pem \
      --embed-certs=true \
      --server=https://${local_ip}:6443 \
      --kubeconfig=kubelet-bootstrap-${node_node_name}.kubeconfig
      echo "master节点IP： ${local_ip}"
    
    # 设置客户端认证参数
    cd ${cfg_dir} && ${bin_dir}/kubectl config set-credentials kubelet-bootstrap \
      --token=${BOOTSTRAP_TOKEN} \
      --kubeconfig=kubelet-bootstrap-${node_node_name}.kubeconfig
    
    # 设置上下文参数
    cd ${cfg_dir} && ${bin_dir}/kubectl config set-context default \
      --cluster=kubernetes \
      --user=kubelet-bootstrap \
      --kubeconfig=kubelet-bootstrap-${node_node_name}.kubeconfig
    
    # 设置默认上下文
    cd ${cfg_dir} && ${bin_dir}/kubectl config use-context default --kubeconfig=kubelet-bootstrap-${node_node_name}.kubeconfig
 done

echo "向所有node节点分发kubelet-bootstrap.kubeconfig文件"
 for node_node_name in ${arr_all_node_hostname[@]}
 do
    echo ">>> ${node_node_name}"
   scp ${cfg_dir}/kubelet-bootstrap-${node_node_name}.kubeconfig ${node_node_name}:${cfg_dir}/kubelet-bootstrap.kubeconfig
  done
 sleep 1
#  cd ${cfg_dir} && ${bin_dir}/kubectl config set-cluster kubernetes \
#  --certificate-authority=$ca_dir/ca.pem \
#  --embed-certs=true \
#  --server=https://${local_ip}:6443 \
#  --kubeconfig=kubelet-bootstrap.kubeconfig
 
# cd ${cfg_dir} && ${bin_dir}/kubectl config set-credentials kubelet-bootstrap \
#   --token=`cat ${cfg_dir}/token.csv |awk -F',' '{print $1}'` \
#   --kubeconfig=kubeletbootstrap.kubeconfig
 
# cd ${cfg_dir} && ${bin_dir}/kubectl config set-context default \
#   --cluster=kubernetes \
#   --user=kubelet-bootstrap \
#   --kubeconfig=kubelet-bootstrap.kubeconfig
 
# cd ${cfg_dir} && ${bin_dir}/kubectl config use-context default --kubeconfig=kubelet-bootstrap.kubeconfig

#    for node_node_name in ${kube_nodes[@]}
# do
#    echo ">>> ${node_node_name}"
#        scp ${cfg_dir}/kubelet-bootstrap.kubeconfig ${node_node_name}:${cfg_dir}/
#    done

 echo "------------------------------------------------------------------------------------"
echo "创建kubelet-bootstrap绑定授权"
$bin_dir/kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers
# cd ${cfg_dir} && ${bin_dir}/kubectl create clusterrolebinding kubelet-bootstrap \
#   --clusterrole=system:node-bootstrapper \
#   --user=kubelet-bootstrap
}


#在node节点上安装kubelet和kube-proxy
function kubelet_in_nodes(){
echo "------------------------------------------------------------------------------------"
echo "在node节点上安装kubelet和kube-proxy"
#安装kubelet
for kube_node in ${kube_nodes[@]}
do
ssh $kube_node bash ${cfg_dir}/kubelet_kube_proxy_node_install.sh $kube_node $local_ip
done
}

#通过TLS请求，在master上
function allow_tls_require_on_master(){
echo "------------------------------------------------------------------------------------"
echo "自动通过nodes的TLS请求，在master上"
cat > $cfg_dir/csr-crb.yaml <<EOF
 # Approve all CSRs for the group "system:bootstrappers"
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: auto-approve-csrs-for-group
 subjects:
 - kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
   apiGroup: rbac.authorization.k8s.io
---
 # To let a node of the group "system:nodes" renew its own credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-client-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
   apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
---
 # To let a node of the group "system:nodes" renew its own server credentials
 kind: ClusterRoleBinding
 apiVersion: rbac.authorization.k8s.io/v1
 metadata:
   name: node-server-cert-renewal
 subjects:
 - kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
 roleRef:
   kind: ClusterRole
   name: approve-node-server-renewal-csr
   apiGroup: rbac.authorization.k8s.io
EOF
$bin_dir/kubectl apply -f $cfg_dir/csr-crb.yaml
kubectl certificate approve `kubectl get csr|awk 'NR>1{print $1}'`
# #添加环境变量
# echo "export PATH=$PATH:/opt/kubernetes/bin" >> /etc/profile
# #获取nodes节点的数量
# nodes_num=${#kube_nodes[*]}
# source /etc/profile
# echo "通过所有节点的TLS请求"
# for allow_node in ${kube_nodes[@]}
# do
# ((c++))
# kubectl certificate approve `kubectl get csr | awk 'NR=="'${c}'"{print $1}'`
# done
kubectl get nodes
# curl -s --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir//admin-key.pem https://$local_ip:10250/metrics|head
# $bin_dir/kubectl create sa kubelet-api-test
# $bin_dir/kubectl create clusterrolebinding kubelet-api-test --clusterrole=system:kubelet-api-admin --serviceaccount=default:kubelet-api-test
# SECRET=$(kubectl get secrets | grep kubelet-api-test | awk '{print $1}')
# TOKEN=$(kubectl describe secret ${SECRET} | grep -E '^token' | awk '{print $2}')
# for allow_node in ${kube_nodes[@]}
# do
# curl -s --cacert $ca_dir/ca.pem -H "Authorization: Bearer ${TOKEN}" https://$allow_node:10250/metrics|head
# curl -s --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://$allow_node:10250/metrics
# curl -s --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://$allow_node:10250/metrics/cadvisor
# break
# done
# curl -sSL --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://${local_ip}:6443/api/v1/nodes/k8s-node01/proxy/configz | jq '.kubeletconfig|.kind="KubeletConfiguration"|.apiVersion="kubelet.config.k8s.io/v1beta1"'
# curl -sSL --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://${local_ip}:6443/api/v1/nodes/k8s-node01/proxy/configz | jq '.kubeletconfig|.kind="KubeletConfiguration"|.apiVersion="kubelet.config.k8s.io/v1beta1"'
# curl -sSL --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://${local_ip}:6443/api/v1/nodes/k8s-node02/proxy/configz | jq '.kubeletconfig|.kind="KubeletConfiguration"|.apiVersion="kubelet.config.k8s.io/v1beta1"'
# curl -sSL --cacert $ca_dir/ca.pem --cert $ca_dir/admin.pem --key $ca_dir/admin-key.pem https://${local_ip}:6443/api/v1/nodes/k8s-node03/proxy/configz | jq '.kubeletconfig|.kind="KubeletConfiguration"|.apiVersion="kubelet.config.k8s.io/v1beta1"'
}

function install_coredns(){
  echo "安装 K8S 插件部分： 包括 coredns dashboard"
echo "------------------------------------------------------------------------------------"
echo "从阿里云下载coredns镜像"
docker pull registry.cn-shanghai.aliyuncs.com/k8s_pkg/coredns:1.6.2 && docker tag registry.cn-shanghai.aliyuncs.com/k8s_pkg/coredns:1.6.2 k8s.gcr.io/coredns:1.6.2
echo "安装coredns"
cd ${cfg_dir}
cp coredns.yaml.sed coredns.yaml
sed -i 's#$DNS_DOMAIN#'$CLUSTER_DNS_DOMAIN'#g' coredns.yaml
sed -i 's#$DNS_SERVER_IP#'$CLUSTER_DNS_SVC_IP'#g' coredns.yaml
sed -i 's#$DNS_MEMORY_LIMIT#100Mi#g' coredns.yaml
echo "创建coredns"
kubectl apply -f coredns.yaml
}

function install_dashboard(){
echo "------------------------------------------------------------------------------------"
echo "从阿里云下载dashboard镜像,然后修改为k8s.gcr.io/kubernetes-dashboard-amd64:v1.10.1"
docker pull registry.cn-shanghai.aliyuncs.com/k8s_pkg/kubernetes-dashboard-amd64:v1.10.1 && docker tag registry.cn-shanghai.aliyuncs.com/k8s_pkg/kubernetes-dashboard-amd64:v1.10.1 k8s.gcr.io/kubernetes-dashboard-amd64:v1.10.1
echo "安装dashboard"

mkdir -p dashboard
mv ${cfg_dir}/dashboard* dashboard/
cd dashboard
echo "修改 service 定义，指定端口类型为 NodePort，这样外界可以通过地址 NodeIP:NodePort 访问 dashboard；"
sed -i '10a type: NodePort' dashboard-service.yaml
sed -i 's/type.*/  type: NodePort/' dashboard-service.yaml
kubectl apply -f  .
echo "设置登录dashboard的kubeconfig文件"
kubectl create sa dashboard-admin -n kube-system
kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
ADMIN_SECRET=$(kubectl get secrets -n kube-system | grep dashboard-admin | awk '{print $1}')
DASHBOARD_LOGIN_TOKEN=$(kubectl describe secret -n kube-system ${ADMIN_SECRET} | grep -E '^token' | awk '{print $2}')
echo "设置集群参数"
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=https://${local_ip}:6443 \
  --kubeconfig=dashboard.kubeconfig
 
echo "设置客户端认证参数，使用上面创建的 Token"
kubectl config set-credentials dashboard_user \
  --token=${DASHBOARD_LOGIN_TOKEN} \
  --kubeconfig=dashboard.kubeconfig
 
echo "设置上下文参数"
kubectl config set-context default \
  --cluster=kubernetes \
  --user=dashboard_user \
  --kubeconfig=dashboard.kubeconfig
 
echo "设置默认上下文"
kubectl config use-context default --kubeconfig=dashboard.kubeconfig
echo "将上面生成的 dashboard.kubeconfig文件拷贝到本地，然后使用这个文件登录 Dashboard。"
}
# function metrics_server(){
# echo "部署metrics-server插件，用来采集数据"

# }



function _main(){
echo "------------------------------------------------------------------------------------"
move_to_opt_kubernetes_dir
mkdir_all_nodes
set_hostname
scp_all_bin
scp_all_cfg
system_init_in_all_nodes
create_all_ca_file
scp_all_ca
create_kubectl_config_file
etcd_install
node_install_flannel
kube_api_server
kube_controller_manager
kube_scheduler
kubelet_in_nodes
create_kubelet_bootstrapping_kubeconfig_file
allow_tls_require_on_master
install_coredns
install_dashboard
}
_main











