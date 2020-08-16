![image](https://github.com/baijiu1/k8s_install/blob/master/651597555810_.pic_hd.jpg)

前提：
需要各个机器之间ssh互通。
K8S的SHELL安装脚本，版本1.17。
需要预先下载好所有二进制文件，放到bin目录下。*.sh文件放到和bin目录同级的cfg目录下，然后编辑k8s_main_install.sh文件，修改：
all_nodes：所有机器的IP
etcd_names：要安装etcd的机器
kube_master：安装mater管理节点的IP
kube_nodes：工作节点的机器IP
