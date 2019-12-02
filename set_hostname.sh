#!/bin/bash
echo "开始设置hostname"
ONLINE_IP=$(ip addr | grep inet | egrep -v '(127.0.0.1|inet6|docker|flannel)' | awk '{print $2}' | tr -d "addr:" | head -n 1 | cut -d / -f1)
hostname=$(cat /etc/hosts|grep $ONLINE_IP|awk -F ' ' '{print $2}')
hostnamectl set-hostname $hostname