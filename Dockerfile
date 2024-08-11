# 使用 node:18.15.0-alpine3.17 作为基础镜像
FROM node:18.15.0-alpine3.17 AS base

# 设置工作目录
WORKDIR /app

# 安装依赖
RUN apk add --no-cache \
    curl \
    git \
    build-base \
    ca-certificates \
    proxychains-ng

# 复制项目文件到容器中
COPY package.json pnpm-lock.yaml ./

# 安装 pnpm
RUN npm install -g pnpm

# 安装项目依赖
RUN pnpm install

# 构建应用
COPY . .
RUN pnpm build

# 运行阶段
FROM node:18.15.0-alpine3.17 AS runner

WORKDIR /app

# 复制构建产物到运行镜像
COPY --from=base /app/public ./public
COPY --from=base /app/.next/standalone ./
COPY --from=base /app/.next/static ./.next/static
COPY --from=base /app/.next/server ./.next/server

# 设置环境变量
ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV CODE=""

# 暴露端口
EXPOSE 3000

# 运行应用
CMD if [ -n "$PROXY_URL" ]; then \
        export HOSTNAME="127.0.0.1"; \
        protocol=$(echo $PROXY_URL | cut -d: -f1); \
        host=$(echo $PROXY_URL | cut -d/ -f3 | cut -d: -f1); \
        port=$(echo $PROXY_URL | cut -d: -f3); \
        conf=/etc/proxychains.conf; \
        echo "strict_chain" > $conf; \
        echo "proxy_dns" >> $conf; \
        echo "remote_dns_subnet 224" >> $conf; \
        echo "tcp_read_time_out 15000" >> $conf; \
        echo "tcp_connect_time_out 8000" >> $conf; \
        echo "localnet 127.0.0.0/255.0.0.0" >> $conf; \
        echo "localnet ::1/128" >> $conf; \
        echo "[ProxyList]" >> $conf; \
        echo "$protocol $host $port" >> $conf; \
        cat /etc/proxychains.conf; \
        proxychains -f $conf node server.js; \
    else \
        node server.js; \
    fi
