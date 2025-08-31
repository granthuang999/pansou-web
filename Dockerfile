# --- 最终的、支持HTTPS的、基于正确文件结构的Dockerfile ---

# 阶段一：构建前端
FROM node:18-alpine as builder
WORKDIR /app
# 复制 package.json 等依赖说明文件
COPY package*.json ./
# 安装依赖
RUN npm install
# 复制所有前端源代码
COPY . .
# 执行构建
RUN npm run build

# 阶段二：准备最终的运行环境
FROM nginx:alpine

# 设置工作目录
WORKDIR /app

# [核心修正] 从第一阶段，复制编译好的前端文件到Nginx的默认网站目录
COPY --from=builder /app/dist /usr/share/nginx/html

# 复制我们全新的、支持HTTPS的Nginx配置文件
COPY nginx.conf /etc/nginx/nginx.conf

# 复制您的“内部VIP通行证”（SSL证书）
COPY certs/ /etc/nginx/certs/

# 复制后端二进制文件 (它将在构建上下文中由GitHub Action提供)
COPY pansou /app/pansou
RUN chmod +x /app/pansou

# 复制启动脚本
COPY start.sh /app/
RUN chmod +x /app/start.sh

# 暴露80 (HTTP) 和 443 (HTTPS) 两个端口
EXPOSE 80 443

# 设置启动命令
CMD ["/app/start.sh"]
