# --- 最终的、支持HTTPS的、多阶段构建的Dockerfile ---

# === 阶段一：构建后端 (Build Backend) ===
FROM golang:1.23-alpine AS backend-builder
WORKDIR /src
# 复制后端源代码
COPY ./backend .
# 下载依赖并编译
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/pansou .

# === 阶段二：构建前端 (Build Frontend) ===
FROM node:18-alpine AS frontend-builder
WORKDIR /app
# 复制前端依赖说明文件
COPY package*.json ./
# 安装依赖
RUN npm install
# 复制所有前端源代码
COPY . .
# 执行构建
RUN npm run build

# === 阶段三：准备最终的运行环境 (Final Stage) ===
FROM nginx:alpine
WORKDIR /app

# [核心] 从后端构建阶段，复制编译好的后端程序
COPY --from=backend-builder /app/pansou /app/pansou
RUN chmod +x /app/pansou

# [核心] 从前端构建阶段，复制编译好的前端文件到Nginx的默认网站目录
COPY --from=frontend-builder /app/dist /usr/share/nginx/html

# 复制我们全新的、支持HTTPS的Nginx配置文件
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 复制您的“内部VIP通行证”（SSL证书）
COPY certs/ /etc/nginx/certs/

# 复制启动脚本
COPY start.sh /app/
RUN chmod +x /app/start.sh

# 暴露80 (HTTP) 和 443 (HTTPS) 两个端口
EXPOSE 80 443

# 设置启动命令
CMD ["/app/start.sh"]
