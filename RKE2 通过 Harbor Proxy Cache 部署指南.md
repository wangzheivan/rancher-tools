# RKE2 通过 Harbor Proxy Cache 部署指南

## 环境信息

| 项目         | 信息                  |
| ------------ | --------------------- |
| Harbor版本   | 2.14.4                |
| Harbor地址   | harbor.rancherlsp.com |
| RKE2版本     | v1.34.7+rke2r1        |
| 镜像代理方式 | Harbor Proxy Cache    |
| 容器运行时   | containerd            |

------

# 一、Harbor配置

## 1. 创建Registry Endpoint

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

测试连接均应显示：

```text
Healthy
```

------

## 2. 创建 Proxy Cache 项目

进入：

```text
Projects
  └── New Project
```

勾选：

```text
Proxy Cache
```

分别创建：

```text
docker.io
registry.rancher.com
registry.k8s.io
quay.io
ghcr.io
gcr.io
```

并关联对应 Endpoint。

最终效果：

```text
docker.io
registry.rancher.com
registry.k8s.io
quay.io
ghcr.io
gcr.io
```

均为：

```text
Proxy Cache
```

类型项目。

------

# 二、RKE2节点配置

创建目录：

```bash
mkdir -p /etc/rancher/rke2
```

------

## 创建 registries.yaml

文件：

```bash
vi /etc/rancher/rke2/registries.yaml
```

内容：

```yaml
mirrors:
  docker.io:
    endpoint:
      - https://harbor.rancherlsp.com
    rewrite:
      "(^.+$)": "docker.io/$1"

  quay.io:
    endpoint:
      - https://harbor.rancherlsp.com
    rewrite:
      "(^.+$)": "quay.io/$1"

  gcr.io:
    endpoint:
      - https://harbor.rancherlsp.com
    rewrite:
      "(^.+$)": "gcr.io/$1"

  ghcr.io:
    endpoint:
      - https://harbor.rancherlsp.com
    rewrite:
      "(^.+$)": "ghcr.io/$1"

  registry.k8s.io:
    endpoint:
      - https://harbor.rancherlsp.com
    rewrite:
      "(^.+$)": "registry.k8s.io/$1"

  registry.rancher.com:
    endpoint:
      - https://harbor.rancherlsp.com
    rewrite:
      "(^.+$)": "registry.rancher.com/$1"

configs:
  harbor.rancherlsp.com:
    auth:
      username: admin
      password: HarborPassword
```

如果 Harbor 使用自签证书：

```yaml
configs:
  harbor.rancherlsp.com:
    auth:
      username: admin
      password: HarborPassword
    tls:
      insecure_skip_verify: true
```

------

# 三、安装RKE2 Server

执行：

```bash
curl -sfL https://get.rke2.io | \
INSTALL_RKE2_VERSION=v1.34.7+rke2r1 \
INSTALL_RKE2_TYPE=server \
sh -
```

启动服务：

```bash
systemctl enable rke2-server
systemctl start rke2-server
```

查看状态：

```bash
systemctl status rke2-server
```

查看日志：

```bash
journalctl -u rke2-server -f
```

------

# 四、获取Node Token

Master节点执行：

```bash
cat /var/lib/rancher/rke2/server/node-token
```

记录输出内容。

例如：

```text
K10f8b8f0d2a4b5a...
```

------

# 五、安装Agent节点

复制相同的：

```bash
/etc/rancher/rke2/registries.yaml
```

到所有Agent节点。

安装：

```bash
curl -sfL https://get.rke2.io | \
INSTALL_RKE2_VERSION=v1.34.7+rke2r1 \
INSTALL_RKE2_TYPE=agent \
sh -
```

配置：

```bash
mkdir -p /etc/rancher/rke2
```

创建：

```bash
vi /etc/rancher/rke2/config.yaml
```

内容：

```yaml
server: https://<MASTER-IP>:9345
token: <NODE-TOKEN>
```

启动：

```bash
systemctl enable rke2-agent
systemctl start rke2-agent
```

------

# 六、验证镜像代理

测试拉取：

```bash
/var/lib/rancher/rke2/bin/crictl pull \
registry.rancher.com/rancher/rke2-runtime:v1.34.7-rke2r1
```

成功后进入 Harbor：

```text
Projects
 └── registry.rancher.com
```

可以看到：

```text
rancher/rke2-runtime
```

镜像已经自动缓存。

------

# 七、验证集群

Master节点执行：

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```

查看节点：

```bash
kubectl get nodes
```

查看系统Pod：

```bash
kubectl get pods -A
```

查看镜像：

```bash
crictl images
```

------

# 八、后续扩展

当安装以下组件时：

- Rancher
- Longhorn
- Cert-Manager
- Monitoring
- Logging
- Istio
- Cilium

涉及：

```text
docker.io
quay.io
ghcr.io
registry.k8s.io
registry.rancher.com
```

镜像会自动经过 Harbor Proxy Cache，无需再修改 Helm Chart 镜像地址。

实现效果：

Node
↓
RKE2/containerd
↓
Harbor Proxy Cache
↓
Internet Registry

```
首次拉取缓存，后续全部走 Harbor 本地镜像。
```