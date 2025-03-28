#!/bin/bash
set -xe

STATIC_SA_PATH="$1"
RUNC_VERSION="$2"
CONTAINERD_VERSION="$3"
MCRHOSTNAME="$4"
DEFAULT_RUNTIME="$5"

mkdir -p /etc/containerd
mkdir -p /var/lib/containerd


curl -o runc -L ${STATIC_SA_PATH}/public/runc/v${RUNC_VERSION}/runc
install -m 0555 runc /usr/bin/runc
rm runc

curl -LO ${STATIC_SA_PATH}/public/containerd/v${CONTAINERD_VERSION}/containerd.tar.gz
# if the file is a posix archive, untar it that way
# workaround to incorrect filetype in agc currently. This may be due to how the archive was obtained - from RepoDepot
# rather than straight from the internet. There is outstanding work to streamline how 3p binaries are 
# delivered to the airgap, but no ETA on this currently until it is prioritized. 
# https://msdata.visualstudio.com/Vienna/_sprints/backlog/Rockland%20Creek/Vienna/Rockland%20Creek/Backlog%20Items?System.AssignedTo=%40me&workitem=3148492
if file containerd.tar.gz | grep -q "POSIX tar archive"; then
    echo "POSIX archive"
    tar -xf containerd.tar.gz -C /usr
else
    # if the file is a gzip archive, untar it that way
    echo "GZIP archive"
    tar -xvzf containerd.tar.gz -C /usr
fi
rm containerd.tar.gz

tee /etc/containerd/config.toml > /dev/null <<EOF
version = 2
oom_score = 0
[plugins."io.containerd.grpc.v1.cri"]
        sandbox_image = "$MCRHOSTNAME/oss/kubernetes/pause:3.6"
        [plugins."io.containerd.grpc.v1.cri".containerd]
                default_runtime_name = "$DEFAULT_RUNTIME"
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
                        runtime_type = "io.containerd.runc.v2"
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
                        BinaryName = "/usr/bin/runc"
                        SystemdCgroup = true
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
                        privileged_without_host_devices = false
                        runtime_engine = ""
                        runtime_root = ""
                        runtime_type = "io.containerd.runc.v1"
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
                        BinaryName = "/usr/bin/nvidia-container-runtime"
                        SystemdCgroup = true
        [plugins."io.containerd.grpc.v1.cri".registry]
                config_path = "/etc/containerd/certs.d"
        [plugins."io.containerd.grpc.v1.cri".registry.headers]
                X-Meta-Source-Client = ["azure/aks"]
[metrics]
        address = "0.0.0.0:10257"
EOF


tee /etc/systemd/system/containerd.service > /dev/null <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target
[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
LimitMEMLOCK=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999
[Install]
WantedBy=multi-user.target
EOF

systemctl enable containerd