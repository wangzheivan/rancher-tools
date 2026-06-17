
#!/usr/bin/env bash
set -euo pipefail


# =========================
# 可配置变量
# =========================

# prime 或 prime-gc
RANCHER_EDITION="${RANCHER_EDITION:-prime-gc}"

# Rancher Chart 版本，例如：2.13.0、2.12.3
RANCHER_VERSION="${RANCHER_VERSION:-2.13.0}"

# 仅 prime-gc 使用，用于拼接 charts.rancher.cn 仓库地址
# 例如：2.13 -> https://charts.rancher.cn/2.13-prime/latest
RANCHER_GC_MINOR_VERSION="${RANCHER_GC_MINOR_VERSION:-2.13}"

# Rancher 访问域名
MY_HOSTNAME="${MY_HOSTNAME:-rancher.rancherlsp.com}"

# Harbor 地址，仅 prime-gc 使用
PRIVATE_REGISTRY="${PRIVATE_REGISTRY:-harbor.rancherlsp.com}"

# Rancher 镜像，仅 prime-gc 使用
RANCHER_IMAGE="${RANCHER_IMAGE:-${PRIVATE_REGISTRY}/prime/rancher}"

# Helm 版本
HELM_VERSION="${HELM_VERSION:-v3.16.2}"

# Kubernetes Namespace
NAMESPACE="${NAMESPACE:-cattle-system}"

# Rancher 副本数
REPLICAS="${REPLICAS:-1}"

# 初始密码
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-Rancher12345}"

# TLS 模式
TLS_MODE="${TLS_MODE:-external}"

# Release 名称
RELEASE_NAME="${RELEASE_NAME:-rancher}"

# =========================
# 基础检查
# =========================
if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] 请使用 root 用户执行"
  exit 1
fi

if [[ "${RANCHER_EDITION}" != "prime" && "${RANCHER_EDITION}" != "prime-gc" ]]; then
  echo "[ERROR] RANCHER_EDITION 只能是 prime 或 prime-gc"
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[ERROR] 未找到 kubectl，请先安装并配置好 RKE2 集群"
  exit 1
fi

if ! kubectl get nodes >/dev/null 2>&1; then
  echo "[ERROR] kubectl 无法访问当前 Kubernetes 集群"
  exit 1
fi

# =========================
# 配置 RKE2 Ingress Nginx 支持外部 TLS / X-Forwarded-* 头
# =========================
echo "[INFO] 配置 rke2-ingress-nginx-controller ConfigMap..."

kubectl -n kube-system patch configmap rke2-ingress-nginx-controller \
  --type merge \
  -p '{"data":{"use-forwarded-headers":"true"}}'

# =========================
# 安装 Helm
# =========================
if ! command -v helm >/dev/null 2>&1; then
  echo "[INFO] 安装 Helm ${HELM_VERSION}..."
  curl https://rancher-mirror.rancher.cn/helm/get-helm-3.sh | \
    INSTALL_HELM_MIRROR=cn \
    bash -s -- --version "${HELM_VERSION}"
else
  echo "[INFO] Helm 已存在：$(helm version --short)"
fi

# =========================
# 添加 Rancher Helm Repo
# =========================
if [[ "${RANCHER_EDITION}" == "prime" ]]; then
  RANCHER_REPO_URL="https://charts.rancher.com/server-charts/prime"
else
  RANCHER_REPO_URL="https://charts.rancher.cn/${RANCHER_GC_MINOR_VERSION}-prime/latest"
fi

echo "[INFO] Rancher Edition : ${RANCHER_EDITION}"
echo "[INFO] Rancher Version : ${RANCHER_VERSION}"
echo "[INFO] Rancher Repo    : ${RANCHER_REPO_URL}"
echo "[INFO] Hostname        : ${MY_HOSTNAME}"

helm repo add rancher-prime "${RANCHER_REPO_URL}" --force-update
helm repo update

# =========================
# 部署 Rancher
# =========================
if [[ "${RANCHER_EDITION}" == "prime" ]]; then

  echo "[INFO] 开始部署 Rancher Prime..."

  helm upgrade --install "${RELEASE_NAME}" rancher-prime/rancher \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set hostname="${MY_HOSTNAME}" \
    --set replicas="${REPLICAS}" \
    --set global.cattle.psp.enabled=false \
    --set bootstrapPassword="${BOOTSTRAP_PASSWORD}" \
    --set tls="${TLS_MODE}" \
    --version "${RANCHER_VERSION}"

else

  echo "[INFO] 开始部署 Rancher Prime GC..."
  echo "[INFO] Private Registry : ${PRIVATE_REGISTRY}"
  echo "[INFO] Rancher Image    : ${RANCHER_IMAGE}"

  helm upgrade --install "${RELEASE_NAME}" rancher-prime/rancher \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set hostname="${MY_HOSTNAME}" \
    --set replicas="${REPLICAS}" \
    --set global.cattle.psp.enabled=false \
    --set bootstrapPassword="${BOOTSTRAP_PASSWORD}" \
    --set rancherImage="${RANCHER_IMAGE}" \
    --set systemDefaultRegistry="${PRIVATE_REGISTRY}" \
    --set tls="${TLS_MODE}" \
    --version "${RANCHER_VERSION}"

fi

# =========================
# 输出状态
# =========================
echo
echo "======================================="
echo "Rancher Server 部署完成"
echo "======================================="
echo "Edition   : ${RANCHER_EDITION}"
echo "Version   : ${RANCHER_VERSION}"
echo "Namespace : ${NAMESPACE}"
echo "Hostname  : ${MY_HOSTNAME}"
echo "TLS       : ${TLS_MODE}"
echo "======================================="
echo
echo "查看 Pod："
echo "kubectl -n ${NAMESPACE} get pods"
echo
echo "查看 Helm Release："
echo "helm -n ${NAMESPACE} list"

