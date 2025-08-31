FROM nginx:alpine

# 安装必要的运行时依赖
RUN apk add --no-cache ca-certificates tzdata curl

# 设置时区
ENV TZ=Asia/Shanghai

# [核心修改] 将您的SSL证书，复制到start.sh脚本期望的位置
# 这一步会在构建镜像时，将您的证书文件永久地打包进去
COPY certs /app/data/ssl

# 复制后端二进制文件 (它将在构建上下文中由GitHub Action提供)
COPY pansou-amd64 /app/pansou
RUN chmod +x /app/pansou

# 复制前端构建产物
COPY frontend-dist /app/frontend/dist/

# 复制启动脚本
COPY start.sh /app/
RUN chmod +x /app/start.sh

# 创建必要的目录
RUN mkdir -p /app/data /app/logs /var/log/nginx /etc/nginx/conf.d

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/api/health || exit 1

# 暴露端口
EXPOSE 80 443

# 设置卷挂载点
VOLUME ["/app/data", "/app/logs"]

# 设置启动命令
CMD ["/app/start.sh"]
