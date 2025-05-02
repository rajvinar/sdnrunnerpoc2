#!/bin/bash
set -xe

NEED_RAID="$1"
AMD_GPU="$2"
LUSTRE_ENABLE="false"
if [[ $# == 3 ]]
then
  LUSTRE_ENABLE="$3"
fi

tee /etc/systemd/system/config.service > /dev/null <<EOF
[Install]
WantedBy=multi-user.target

[Unit]
Description=config setup
DefaultDependencies=no
Before=kubelet.service
EOF

if [[ $NEED_RAID == "true" ]]
then
    echo "BindsTo=raid-setup.service" >> /etc/systemd/system/config.service
    echo "After=raid-setup.service" >> /etc/systemd/system/config.service
fi

if [[ $AMD_GPU == "true" ]]
then
    echo "After=rocmstartup.service" >> /etc/systemd/system/config.service
fi

echo "[Service]" >> /etc/systemd/system/config.service

if [[ $LUSTRE_ENABLE == "false" ]]
then
  echo "TimeoutSec=360" >> /etc/systemd/system/config.service
else
  echo "TimeoutSec=1800" >> /etc/systemd/system/config.service
fi
echo "ExecStart=/usr/bin/sleep infinity" >> /etc/systemd/system/config.service

if [[ $AMD_GPU == "true" ]]
then
    echo "ExecStartPre=/bin/bash -c \"ret=\$(cat /proc/uptime | awk '{print \$1}'); if echo \$ret'<'600 | bc -l | grep 1; then sleep 5m; fi\"" >> /etc/systemd/system/config.service
fi

if [[ $LUSTRE_ENABLE == "true" ]]
then
    echo "ExecStartPre=/bin/bash -c \"while true;do if [[ -f /etc/DDN.FIRST ]]; then sleep 10; else exit 0 ;fi;done\"" >> /etc/systemd/system/config.service
fi

systemctl enable config
