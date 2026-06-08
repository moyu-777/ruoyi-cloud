# 使用 OpenJDK 17 作为基础镜像（根据实际 Java 版本调整）
FROM mcereja/jre17:0.18

# 设置工作目录
WORKDIR /app

# 复制 Maven 构建生成的 JAR 包到镜像中
# 假定 JAR 文件名为 ruoyi-gateway.jar
COPY ./target/ruoyi-gateway.jar /app/app.jar

# 暴露容器内服务端口（与 docker-compose 中 ports 的容器端口一致）
EXPOSE 8080

# 设置 JVM 参数和启动命令（可根据需要调整内存等参数）
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
