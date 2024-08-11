# 基础镜像阶段
FROM ubuntu:20.04 AS base

# 安装 Node.js 和基本工具
RUN apt-get update && \
    apt-get install -y \
    curl \
    git \
    build-essential \
    ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 依赖安装阶段
FROM base AS deps

WORKDIR /app

COPY package.json yarn.lock ./

# 安装 Yarn
RUN curl -fsSL https://classic.yarnpkg.com/install.sh | bash \
    && apt-get install -y yarn

RUN yarn config set registry 'https://registry.npmmirror.com/'
RUN yarn install

# 构建阶段
FROM base AS builder

ENV OPENAI_API_KEY=""
ENV CODE=""

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN yarn build

# 运行阶段
FROM base AS runner

WORKDIR /app

# 安装 proxychains-ng
RUN apt-get update && \
    apt-get install -y proxychains \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV CODE=""

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/server ./.next/server

EXPOSE 3000

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
