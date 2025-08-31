# --- 最终的、支持HTTPS的、多阶段构建的Dockerfile (V2.0) ---

# === 阶段一：构建前端 (Build Frontend) ===
FROM node:18-alpine AS frontend-builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# === 阶段二：构建后端 (Build Backend) ===
FROM golang:1.23-alpine AS backend-builder
WORKDIR /src
COPY ./backend .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /app/pansou .

# === 阶段三：准备最终的运行环境 (Final Stage) ===
FROM nginx:alpine

# 安装必要的运行时依赖
RUN apk add --no-cache curl

# 设置工作目录
WORKDIR /app

# [核心] 从后端构建阶段，复制编译好的后端程序
COPY --from=backend-builder /app/pansou /app/pansou

# [核心] 从前端构建阶段，复制编译好的前端文件到Nginx的默认网站目录
COPY --from=frontend-builder /app/dist /usr/share/nginx/html

# [核心] 复制我们之前写好的、支持HTTPS的Nginx配置文件到正确的主配置文件路径
COPY nginx.conf /etc/nginx/nginx.conf

# [核心] 复制您的SSL证书
COPY certs/ /etc/nginx/certs/

# [核心] 复制我们全新的、极简的启动脚本
COPY start.sh /app/start.sh

# 赋予执行权限
RUN chmod +x /app/pansou /app/start.sh

# 暴露80 (HTTP) 和 443 (HTTPS) 两个端口
EXPOSE 80 443

# 设置启动命令
CMD ["/app/start.sh"]
