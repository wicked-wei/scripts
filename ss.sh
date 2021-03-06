#!/bin/bash
# Install Shadowsocks on CentOS 7

echo "Installing Shadowsocks..."

random-string()
{
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1
}

PORTS_USED=`ss -antl |grep LISTEN | awk '{ print $4 }' | cut -d: -f2|sed '/^$/d'|sort`
PORTS_USED=`echo $PORTS_USED|sed 's/\s/$\|^/g'`
PORTS_USED="^${PORTS_USED}$"
PORTS_AVAILABLE=(`seq 1025 9000 | grep -v -E "$PORTS_USED" | shuf -n 5 | sort`)

CONFIG_FILE=/etc/shadowsocks.json
SERVICE_FILE=/etc/systemd/system/shadowsocks.service
SS_PASSWORD=$(random-string 16)
SS_PORT=${PORTS_AVAILABLE[0]}
SS_METHOD=aes-256-cfb
SS_FAST_OPEN=true
SS_IP=`ip route get 1 | awk '{print $NF;exit}'`
GET_PIP_FILE=/tmp/get-pip.py

# install pip
curl "https://bootstrap.pypa.io/get-pip.py" -o "${GET_PIP_FILE}"
python ${GET_PIP_FILE}

# install git
yum install git -y

# install shadowsocks
pip install git+https://github.com/shadowsocks/shadowsocks.git@master

# create shadowsocls config
cat <<EOF | sudo tee ${CONFIG_FILE}
{
  "server": "0.0.0.0",
  "port_password": {
        "${SS_PORT}": "${SS_PASSWORD}"
        },
  "method": "${SS_METHOD}",
  "timeout": 300,
  "fast_open": ${SS_FAST_OPEN}
}
EOF

#set fastopen
#echo 3 > /proc/sys/net/ipv4/tcp_fastopen

# create service
cat <<EOF | sudo tee ${SERVICE_FILE}
[Unit]
Description=Shadowsocks

[Service]
TimeoutStartSec=0
ExecStart=/usr/bin/ssserver -c ${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

echo "Optimizing..."

LIMITS_CONF=/etc/security/limits.conf
SYSCTL_CONF=/etc/sysctl.d/local.conf
MODPROBE=/sbin/modprobe

echo "Backing up ${LIMITS_CONF} to ${LIMITS_CONF}.old"
mv ${LIMITS_CONF} ${LIMITS_CONF}.old

cat <<EOF | sudo tee ${LIMITS_CONF}
* soft nofile 51200
* hard nofile 51200
EOF

ulimit -n 51200

${MODPROBE} tcp_hybla

echo "Backing up ${SYSCTL_CONF} to ${SYSCTL_CONF}.old"
mv ${SYSCTL_CONF} ${SYSCTL_CONF}.old

cat <<EOF | sudo tee ${SYSCTL_CONF}
fs.file-max = 51200

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default=65536
net.core.wmem_default=65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_fin_timeout = 5
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = hybla
EOF

sysctl --system

echo "Installing denyhosts..."
yum install -y epel-release.noarch
yum install -y denyhosts

echo "Installing firewalld..."
systemctl enable firewalld
systemctl start firewalld

echo "Starting services..."
systemctl enable denyhosts
systemctl start denyhosts

# start service
systemctl enable shadowsocks
systemctl start shadowsocks

# view service status
sleep 5
systemctl status firewalld
systemctl status denyhosts
systemctl status shadowsocks

echo "Configuring firewall..."
firewall-cmd --permanent --add-port=${SS_PORT}/tcp
firewall-cmd --permanent --add-port=${SS_PORT}/udp
firewall-cmd --reload
echo "following ports are enabled:"
firewall-cmd --list-ports

echo "================================"
echo ""
echo "Congratulations! Shadowsocks has been installed on your system."
echo "You shadowsocks connection info:"
echo "--------------------------------"
echo "server:      ${SS_IP}"
echo "port:        ${SS_PORT}"
echo "password:    ${SS_PASSWORD}"
echo "method:      ${SS_METHOD}"
echo "--------------------------------"
