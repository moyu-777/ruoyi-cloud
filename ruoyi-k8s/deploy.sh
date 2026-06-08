#!/bin/bash
# ─────────────────────────────────────────────────────────────────
# RuoYi-Cloud K8s 一键部署脚本
# 使用方式：chmod +x deploy.sh && ./deploy.sh
# ─────────────────────────────────────────────────────────────────
set -e

NAMESPACE="ruoyi"
MANIFESTS_DIR="$(dirname "$0")"

echo "==> [1/3] 创建 Namespace 及基础资源..."
kubectl apply -f "$MANIFESTS_DIR/00-namespace.yaml"
kubectl apply -f "$MANIFESTS_DIR/01-secret.yaml"
kubectl apply -f "$MANIFESTS_DIR/02-pvc.yaml"
kubectl apply -f "$MANIFESTS_DIR/03-configmap.yaml"

echo "==> [2/3] 部署中间件（MySQL → Redis → Nacos）..."
kubectl apply -f "$MANIFESTS_DIR/04-mysql.yaml"
kubectl apply -f "$MANIFESTS_DIR/05-redis.yaml"

echo "    等待 MySQL 就绪..."
kubectl rollout status deployment/ruoyi-mysql -n $NAMESPACE --timeout=120s

kubectl apply -f "$MANIFESTS_DIR/06-nacos.yaml"
echo "    等待 Nacos 就绪（约需 60 秒）..."
kubectl rollout status deployment/ruoyi-nacos -n $NAMESPACE --timeout=180s

echo "==> [3/3] 部署业务服务..."
kubectl apply -f "$MANIFESTS_DIR/07-gateway.yaml"
kubectl apply -f "$MANIFESTS_DIR/08-auth.yaml"
kubectl apply -f "$MANIFESTS_DIR/09-system.yaml"
kubectl apply -f "$MANIFESTS_DIR/10-nginx.yaml"

echo ""
echo "✅ 部署完成！查看 Pod 状态："
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "访问入口（NodePort）："
echo "  前端：http://<NodeIP>:30080"
echo "  Nacos 控制台：http://<NodeIP>:30848/nacos"
