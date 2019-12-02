#!/bin/bash
flannel_network_dir=/kubernetes/network
kube_data_dir=/data/k8s
function system_init(){
systemctl stop firewalld
echo "安装基础软件"
yum install -y epel-release
yum install -y jq vim wget net-tools lrzsz gcc gcc-c++ make libnftnl-devel libmnl libmnl-devel autoconf automake libtool bison flex  libnetfilter_conntrack-devel libnetfilter_queue-devel libpcap-devel iptables-services bzip2 git
swapoff -a
echo "编译1.6.2版本的iptables"
wget https://gitee.com/haru_hi/iptables/raw/master/iptables-1.6.2.tar.bz2
#wget http://ftp.netfilter.org/pub/iptables/iptables-1.6.2.tar.bz2
tar -xjf iptables-1.6.2.tar.bz2
cd iptables-1.6.2
if [ `rpm -q centos-release|awk -F '-' '{print $3}'` == "6" ];then
./configure --disable-nftables 
elif [ `rpm -q centos-release|awk -F '-' '{print $3}'` == "7" ];then
./configure
fi
make -j `cat /proc/cpuinfo | grep processor| wc -l` && make install
cp -f /usr/local/sbin/iptables /sbin/        
cp -f /usr/local/sbin/iptables-restore /sbin/
cp -f /usr/local/sbin/iptables-save /sbin/
service iptables stop
function install_docker(){
DOCKER_DIR=/data/docker-data
mkdir -p $DOCKER_DIR
wget -O /etc/yum.repos.d/docker-ce.repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum install -y docker-ce ntpdate ntp
systemctl restart ntpdate
if [ ! -e /etc/docker ];then
mkdir -p /etc/docker
fi
sed -i '/Type=notify/a WorkingDirectory='$DOCKER_DIR'/' /usr/lib/systemd/system/docker.service
cat > /etc/docker/docker-daemon.json <<EOF
{
    "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn","https://hub-mirror.c.163.com"],
    "insecure-registries": ["docker02:35000"],
    "max-concurrent-downloads": 20,
    "live-restore": true,
    "max-concurrent-uploads": 10,
    "debug": true,
    "data-root": "${DOCKER_DIR}/data",
    "exec-root": "${DOCKER_DIR}/exec",
    "log-opts": {
      "max-size": "100m",
      "max-file": "5"
    }
}
EOF
sleep 5
systemctl daemon-reload && systemctl enable docker && systemctl restart docker
sleep 5
}
function ulimits(){
cat > /etc/security/limits.conf <<EOF
* soft noproc 65536
* hard noproc 65536
* soft nofile 65536
* hard nofile 65536
EOF

echo > /etc/security/limits.d/20-nproc.conf 

ulimit -n 65536
ulimit -u 65536

}

function kernel(){
cat > /etc/sysctl.conf <<EOF
vm.swappiness=0
vm.max_map_count=655360
vm.overcommit_memory=1
vm.overcommit_ratio=90
vm.zone_reclaim_mode=0
vm.dirty_expire_centisecs=1500	#expire time
vm.dirty_ratio=95	#force flush
vm.dirty_background_ratio=10	#flush
vm.dirty_writeback_centisecs=100
fs.aio-max-nr=1048576
fs.file-max = 65536
net.core.netdev_max_backlog = 32768
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.somaxconn = 32768
net.core.wmem_default = 8388608
net.core.wmem_max = 16777216
net.ipv4.conf.all.arp_ignore = 0
net.ipv4.conf.lo.arp_announce = 0
net.ipv4.conf.lo.arp_ignore = 0
net.ipv4.ip_local_port_range = 5000 65000
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_tw_reuse = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl -p >/dev/null 2>&1
}

function history(){
	if ! grep "HISTTIMEFORMAT" /etc/profile >/dev/null 2>&1
	then echo '
	UserIP=$(who -u am i | cut -d"("  -f 2 | sed -e "s/[()]//g")
	export HISTTIMEFORMAT="[%F %T] [`whoami`] [${UserIP}] " ' >> /etc/profile;
	fi
	sed -i "s/HISTSIZE=1000/HISTSIZE=999999999/" /etc/profile
}

function security(){
	> /etc/issue
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
	sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0 >/dev/null 2>&1
	yum install -y openssl openssh bash >/dev/null 2>&1
}

function other(){
	yum groupinstall Development tools -y >/dev/null 2>&1
	yum install -y vim wget lrzsz telnet traceroute iotop tree git >/dev/null 2>&1
	echo "export HOME=/root" >> /etc/profile
	source /etc/profile
	useradd -M -s /sbin/nologin nginx >/dev/null 2>&1
	mkdir -p /root/ops_scripts /data1/www
	mkdir -p /opt/codo/
}

export -f ulimits
export -f kernel
export -f history
export -f security
export -f other
export -f install_docker

ulimits
kernel
history
security
other
install_docker
}
system_init