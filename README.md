目录结构：
```bash
[root@slave k8s_install]# tree
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
│   ├── helm-v3.0.2-linux-amd64.tar.gz
│   ├── kubeadm
│   ├── kube-apiserver
│   ├── kube-controller-manager
│   ├── kubectl
│   ├── kubelet
│   ├── kube-proxy
│   ├── kube-scheduler
│   └── mk-docker-opts.sh
└── cfg
    ├── config_etcd.py
    ├── coredns.yaml.sed
    ├── create_etcd_node.sh
    ├── dashboard-configmap.yaml
    ├── dashboard-controller.yaml
    ├── dashboard-rbac.yaml
    ├── dashboard-secret.yaml
    ├── dashboard-service.yaml
    ├── flannel_node_install.sh
    ├── k8s_main_install.sh
    ├── kubelet_kube_proxy_node_install.sh
    ├── set_hostname.sh
    └── system_init.sh

3 directories, 44 files
```

前提：
需要各个机器之间ssh互通。
K8S的SHELL安装脚本，版本1.17。
all_nodes：所有机器的IP
etcd_names：要安装etcd的机器
kube_master：安装mater管理节点的IP
kube_nodes：工作节点的机器IP
