# 阶段1：构建静态文件
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --registry=https://registry.npmmirror.com
COPY . .
RUN npm run build:prod      # 根据你的实际构建脚本调整

# 阶段2：仅包含静态文件的镜像
FROM alpine:latest
# 创建与 K8s 中期望的路径完全一致的目录
RUN mkdir -p /home/ruoyi/projects/ruoyi-ui
# 从构建阶段复制产物
COPY --from=builder /app/dist /home/ruoyi/projects/ruoyi-ui
