# RKE2 集群一键安装文档（Harbor Proxy Cache版）

## 文档说明

本文档用于通过 Harbor Proxy Cache 部署 RKE2 集群。

当前环境：

| 项目            | 值                    |
| --------------- | --------------------- |
| Harbor地址      | harbor.rancherlsp.com |
| Harbor版本      | 2.14.4                |
| RKE2安装方式    | 官方安装脚本          |
| 镜像加速方式    | Harbor Proxy Cache    |
| 容器运行时      | containerd            |
| kubectl安装方式 | RKE2内置              |
| crictl安装方式  | RKE2内置              |

------

# 一、Harbor准备工作

## 1、创建Registry Endpoint

进入：

```text
Administration
 └── Registries
```

创建以下 Endpoint：

| Name                 | Provider        | Endpoint                                                     |
| -------------------- | --------------- | ------------------------------------------------------------ |
| docker.io            | Docker Hub      | 默认                                                         |
| registry.rancher.com | Docker Registry | [https://registry.rancher.com](https://registry.rancher.com/) |
| registry.k8s.io      | Docker Registry | [https://registry.k8s.io](https://registry.k8s.io/)          |
| quay.io              | Docker Registry | [https://quay.io](https://quay.io/)                          |
| ghcr.io              | Docker Registry | [https://ghcr.io](https://ghcr.io/)                          |
| gcr.io               | Docker Registry | [https://gcr.io](https://gcr.io/)                            |

全部测试通过：

```text
Healthy
```

------

## 2、创建 Proxy Cache 项目

进入：

```text
Projects
 └── New Project
```

勾选：

```text
Proxy Cache
```

创建：

```text
docker.io
registry.rancher.com
registry.k8s.io
quay.io
ghcr.io
gcr.io
```

并关联对应 Endpoint。

------

# 二、一键安装脚本

保存如下脚本：

```bash
vi install-rke2.sh
```

内容如下：

```bash
#!/usr/bin/env bash
set -euo pipefail

# =========================
# 可配置变量
# =========================
RKE2_VERSION="${RKE2_VERSION:-v1.34.7+rke2r1}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.rancherlsp.com}"
INSTALL_TYPE="${INSTALL_TYPE:-server}"

# Agent节点需要
RKE2_SERVER_URL="${RKE2_SERVER_URL:-}"
RKE2_TOKEN="${RKE2_TOKEN:-}"

# =========================
# 基础检查
# =========================
if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用root用户执行"
  exit 1
fi

if [[ "${INSTALL_TYPE}" != "server" && "${INSTALL_TYPE}" != "agent" ]]; then
  echo "INSTALL_TYPE只能是server或agent"
  exit 1
fi

if [[ "${INSTALL_TYPE}" == "agent" ]]; then
  if [[ -z "${RKE2_SERVER_URL}" || -z "${RKE2_TOKEN}" ]]; then
    echo "agent模式必须指定RKE2_SERVER_URL和RKE2_TOKEN"
    exit 1
  fi
fi

mkdir -p /etc/rancher/rke2

# =========================
# 配置 Harbor 镜像代理
# =========================
cat > /etc/rancher/rke2/registries.yaml <<EOF
mirrors:
  docker.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      "(^.+$)": "docker.io/\\\$1"

  quay.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      "(^.+$)": "quay.io/\\\$1"

  gcr.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      "(^.+$)": "gcr.io/\\\$1"

  ghcr.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      "(^.+$)": "ghcr.io/\\\$1"

  registry.k8s.io:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      "(^.+$)": "registry.k8s.io/\\\$1"

  registry.rancher.com:
    endpoint:
      - https://${HARBOR_REGISTRY}
    rewrite:
      "(^.+$)": "registry.rancher.com/\\\$1"
EOF

# =========================
# Agent配置
# =========================
if [[ "${INSTALL_TYPE}" == "agent" ]]; then
cat > /etc/rancher/rke2/config.yaml <<EOF
server: ${RKE2_SERVER_URL}
token: ${RKE2_TOKEN}
EOF
fi

# =========================
# 安装RKE2
# =========================
curl -sfL https://get.rke2.io | \
INSTALL_RKE2_VERSION="${RKE2_VERSION}" \
INSTALL_RKE2_TYPE="${INSTALL_TYPE}" \
sh -

# =========================
# 启动服务
# =========================
if [[ "${INSTALL_TYPE}" == "server" ]]; then
    systemctl enable rke2-server
    systemctl start rke2-server
else
    systemctl enable rke2-agent
    systemctl start rke2-agent
fi

# =========================
# 配置命令
# =========================
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/bin/kubectl
ln -sf /var/lib/rancher/rke2/bin/ctr /usr/bin/ctr
ln -sf /var/lib/rancher/rke2/bin/crictl /usr/bin/crictl

# =========================
# 配置crictl
# =========================
crictl config runtime-endpoint unix:///run/k3s/containerd/containerd.sock
crictl config image-endpoint unix:///run/k3s/containerd/containerd.sock

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
```

------

# 三、安装 Server 节点

赋予权限：

```bash
chmod +x install-rke2.sh
```

安装：

```bash
./install-rke2.sh
```

指定版本：

```bash
RKE2_VERSION=v1.34.7+rke2r1 ./install-rke2.sh
```

------

# 四、获取 Token

Master节点：

```bash
cat /var/lib/rancher/rke2/server/node-token
```

输出示例：

```text
K10c0f4d5a4e3......
```

记录备用。

------

# 五、安装 Agent 节点

执行：

```bash
INSTALL_TYPE=agent \
RKE2_SERVER_URL=https://192.168.1.100:9345 \
RKE2_TOKEN=K10c0f4d5a4e3...... \
./install-rke2.sh
```

------

# 六、验证集群

配置环境变量：

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```

查看节点：

```bash
kubectl get nodes
```

查看Pod：

```bash
kubectl get pods -A
```

------

# 七、验证 Harbor 缓存

测试拉取镜像：

```bash
crictl pull registry.rancher.com/rancher/rke2-runtime:v1.34.7-rke2r1
```

进入 Harbor：

```text
Projects
 └── registry.rancher.com
```

应看到：

```text
rancher/rke2-runtime
```

镜像已被缓存。

------

# 八、常用命令

查看节点：

```bash
kubectl get nodes -o wide
```

查看Pod：

```bash
kubectl get pods -A
```

查看镜像：

```bash
crictl images
```

查看容器：

```bash
crictl ps -a
```

查看containerd镜像：

```bash
ctr -n k8s.io images ls
```

查看RKE2状态：

```bash
systemctl status rke2-server
```

查看日志：

```bash
journalctl -u rke2-server -f
```

Agent日志：

```bash
journalctl -u rke2-agent -f
```