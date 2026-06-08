# RuoYi-Cloud K8s 部署说明

## 文件结构

```
k8s/
├── 00-namespace-and-config.yaml   # Namespace + Secret（MySQL/Nacos 密钥）
├── 01-mysql.yaml                  # MySQL StatefulSet + PVC + Service
├── 02-redis.yaml                  # Redis Deployment + ConfigMap + PVC + Service
├── 03-nacos.yaml                  # Nacos StatefulSet + ConfigMap + Service (双Service)
├── 04-microservices.yaml          # gateway / auth / modules-system
├── 05-nginx.yaml                  # Nginx + ConfigMap + NodePort + Ingress
└── README.md
```

## 部署顺序

```bash
# 1. 创建命名空间和密钥
kubectl apply -f 00-namespace-and-config.yaml

# 2. 启动基础设施（有状态服务先行）
kubectl apply -f 01-mysql.yaml
kubectl apply -f 02-redis.yaml

# 3. 等待 MySQL 就绪后启动 Nacos
kubectl wait --for=condition=ready pod -l app=ruoyi-mysql -n ruoyi-cloud --timeout=120s
kubectl apply -f 03-nacos.yaml

# 4. 等待 Nacos 就绪后启动微服务
kubectl wait --for=condition=ready pod -l app=ruoyi-nacos -n ruoyi-cloud --timeout=180s
kubectl apply -f 04-microservices.yaml

# 5. 启动前端网关
kubectl apply -f 05-nginx.yaml
```

## 部署前必须修改的地方

### 1. 镜像地址（04-microservices.yaml）
```yaml
# 将所有 your-harbor.example.com 替换为实际 Harbor 地址
image: your-harbor.example.com/ruoyi/gateway:latest
image: your-harbor.example.com/ruoyi/auth:latest
image: your-harbor.example.com/ruoyi/modules-system:latest
```

如果镜像仓库需要认证，先创建 imagePullSecret：
```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=your-harbor.example.com \
  --docker-username=admin \
  --docker-password=your-password \
  -n ruoyi-cloud
```
然后在每个 Deployment spec 中添加：
```yaml
spec:
  imagePullSecrets:
    - name: harbor-secret
```

### 2. Nacos 配置文件（03-nacos.yaml）
将 `./nacos/conf/application.properties` 内容填入 ConfigMap 的 `data.application.properties` 字段。
**重要**：所有 `localhost` 需改为对应 K8s Service 名：
- MySQL: `ruoyi-mysql:3306`
- Redis: `ruoyi-redis:6379`

### 3. Redis 配置文件（02-redis.yaml）
将 `./redis/conf/redis.conf` 内容填入 ConfigMap 的 `data.redis.conf` 字段。

### 4. Nginx 前端静态文件（05-nginx.yaml）
生产环境推荐将前端 dist 打包进自定义 Nginx 镜像：
```dockerfile
FROM nginx:latest
COPY dist/ /home/ruoyi/projects/ruoyi-ui/
COPY nginx.conf /etc/nginx/nginx.conf
```

### 5. Secret 密码（00-namespace-and-config.yaml）
将 `password`、`your_auth_token` 等替换为真实值，或使用 base64 编码的 `data` 字段。

## 与 Docker Compose 的关键差异

| 概念 | Docker Compose | K8s |
|------|----------------|-----|
| 服务发现 | 容器名（如 `ruoyi-mysql`）| Service 名（同名，规则相同）|
| `links` | 已弃用但有效 | 不需要，同 Namespace 内 DNS 自动解析 |
| `depends_on` | 仅控制启动顺序 | 用 `initContainer` + `readinessProbe` 替代 |
| 持久化 | bind mount (`./mysql/data`) | PVC（需要 StorageClass 支持）|
| 暴露端口 | `ports: 3306:3306` | NodePort / ClusterIP / Ingress |
| 有状态服务 | 普通 service | StatefulSet（MySQL/Nacos）|

## StorageClass 配置

如果集群有 NFS 动态存储（nfs-subdir-external-provisioner），取消各 PVC 中的注释：
```yaml
storageClassName: nfs-client
```

否则需要提前手动创建 PV，或使用本地存储（仅适合单节点测试环境）。
