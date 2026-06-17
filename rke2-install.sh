#!/usr/bin/env bash
set -euo pipefail

# =========================
# 可配置变量
# =========================
RKE2_VERSION="${RKE2_VERSION:-v1.34.7+rke2r1}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.rancherlsp.com}"
INSTALL_TYPE="${INSTALL_TYPE:-server}"

# Agent 节点需要配置
RKE2_SERVER_URL="${RKE2_SERVER_URL:-}"
RKE2_TOKEN="${RKE2_TOKEN:-}"

# =========================
# 基础检查
# =========================
if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 用户执行"
  exit 1
fi

if [[ "${INSTALL_TYPE}" != "server" && "${INSTALL_TYPE}" != "agent" ]]; then
  echo "INSTALL_TYPE 只能是 server 或 agent"
  exit 1
fi

if [[ "${INSTALL_TYPE}" == "agent" ]]; then
  if [[ -z "${RKE2_SERVER_URL}" || -z "${RKE2_TOKEN}" ]]; then
    echo "agent 模式必须指定 RKE2_SERVER_URL 和 RKE2_TOKEN"
    exit 1
  fi
fi

mkdir -p /etc/rancher/rke2

# =========================
# 配置 Harbor Proxy Cache 镜像代理
# =========================
cat > /etc/rancher/rke2/registries.yaml <<EOF
mirrors:
  docker.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      '(^.+$)': 'docker.io/\$1'

  quay.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      '(^.+$)': 'quay.io/\$1'

  gcr.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      '(^.+$)': 'gcr.io/\$1'

  ghcr.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      '(^.+$)': 'ghcr.io/\$1'

  registry.k8s.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      '(^.+$)': 'registry.k8s.io/\$1'

  registry.rancher.com:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      '(^.+$)': 'registry.rancher.com/\$1'
EOF

# =========================
# Agent 节点配置
# =========================
if [[ "${INSTALL_TYPE}" == "agent" ]]; then
cat > /etc/rancher/rke2/config.yaml <<EOF
server: ${RKE2_SERVER_URL}
token: ${RKE2_TOKEN}
EOF
fi

# =========================
# 安装 RKE2
# =========================
curl -sfL https://get.rke2.io | \
INSTALL_RKE2_VERSION="${RKE2_VERSION}" \
INSTALL_RKE2_TYPE="${INSTALL_TYPE}" \
sh -

# =========================
# 启动 RKE2
# =========================
if [[ "${INSTALL_TYPE}" == "server" ]]; then
  systemctl enable rke2-server
  systemctl start rke2-server
else
  systemctl enable rke2-agent
  systemctl start rke2-agent
fi

# =========================
# 配置 kubectl / crictl / ctr
# =========================
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/bin/kubectl
ln -sf /var/lib/rancher/rke2/bin/ctr /usr/bin/ctr
ln -sf /var/lib/rancher/rke2/bin/crictl /usr/bin/crictl

# =========================
# 配置 crictl
# =========================
mkdir -p /etc

cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF

# =========================
# 配置 kubeconfig
# =========================
if [[ "${INSTALL_TYPE}" == "server" ]]; then
  mkdir -p /root/.kube
  cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
  chmod 600 /root/.kube/config
fi

echo
echo "======================================="
echo "RKE2 安装完成"
echo "======================================="
echo "Version : ${RKE2_VERSION}"
echo "Type    : ${INSTALL_TYPE}"
echo "Harbor  : ${HARBOR_REGISTRY}"
echo "======================================="

if [[ "${INSTALL_TYPE}" == "server" ]]; then
  echo
  echo "查看节点："
  echo "kubectl get nodes"
  echo
  echo "获取 Agent 加入 Token："
  echo "cat /var/lib/rancher/rke2/server/node-token"
fi