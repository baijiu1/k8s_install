# k8s_install
K8S的安装脚本
## 安装说明
首先要把所有要用到的二进制可执行文件放到一个目录里，目录结构：
[root@k8s-master01 opt]# tree 
.
├── bin
│   ├── cfssl
│   ├── cfssl-certinfo
│   ├── cfssljson
│   ├── cni
│   │   ├── bandwidth
│   │   ├── bridge
│   │   ├── dhcp
│   │   ├── firewall
│   │   ├── flannel
│   │   ├── host-device
│   │   ├── host-local
│   │   ├── ipvlan
│   │   ├── loopback
│   │   ├── macvlan
│   │   ├── portmap
│   │   ├── ptp
│   │   ├── sbr
│   │   ├── static
│   │   ├── tuning
│   │   └── vlan
│   ├── etcd
│   ├── etcdctl
│   ├── flanneld
│   ├── kubeadm
│   ├── kube-apiserver
│   ├── kube-controller-manager
│   ├── kubectl
│   ├── kubelet
│   ├── kube-proxy
│   ├── kube-scheduler
│   └── mk-docker-opts.sh
├── cfg
│   ├── config_etcd.py
│   ├── coredns.yaml.sed
│   ├── create_etcd_node.sh
│   ├── dashboard-configmap.yaml
│   ├── dashboard-controller.yaml
│   ├── dashboard-rbac.yaml
│   ├── dashboard-secret.yaml
│   ├── dashboard-service.yaml
│   ├── flannel_node_install.sh
│   ├── k8s_main_install.sh
│   ├── kubelet_kube_proxy_node_install.sh
│   ├── set_hostname.sh
│   └── system_init.sh
# 前提：
1、修改k8s_main_install.sh脚本中all_nodes，etcd_names，kube_master，kube_nodes四个变量。其他可以根据自己需要修改。
2、所有机器之间ssh互通。本机自己也要与本机互通，执行k8s_main_install.sh之后，都是在本机一个节点上运行的。所以ssh必须互通。
bin_dir放的是所有可执行文件。
ca_dir放的是所有证书文件。
cfg_dir放的是所有配置文件。
flannel_network_dir为flannel配置文件。
kube_data_dir为所有K8S组件的数据目录。
修改all_nodes，etcd_names，kube_master，kube_nodes四个变量后，直接执行k8s_main_install.sh脚本即可。
