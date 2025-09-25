FROM golang:latest AS builder

LABEL org.opencontainers.image.source = https://github.com/skyhhjmk/ip_derper_plus

WORKDIR /app

# 复制项目文件
COPY . /app

# 修改 derper 代码以禁用服务器名称检查（从 GitHub Actions 工作流移植）
RUN cd /app/tailscale && \
    sed -i '/hi.ServerName != m.hostname/,+2d' cmd/derper/cert.go

# build modified derper
RUN cd /app/tailscale/cmd/derper && \
    CGO_ENABLED=0 /usr/local/go/bin/go build -buildvcs=false -ldflags "-s -w" -o /app/derper && \
    cd /app && \
    rm -rf /app/tailscale

FROM ubuntu:20.04
WORKDIR /app

# ========= CONFIG =========
# - derper args
ENV DERP_ADDR=:443
ENV DERP_HTTP_PORT=80
ENV DERP_HOST=127.0.0.1
ENV DERP_CERTS=/app/certs/
ENV DERP_STUN=true
ENV DERP_STUN_PORT=3478
# 不修改，兼容旧版
ENV DERP_VERIFY_CLIENTS=false
# 适配自带防盗
ENV REG_BASH='echo "No reg bash need to run."'
# ==========================

# 安装依赖（与原 Dockerfile 保持一致）
RUN apt-get update && \
    apt-get install -y openssl curl

RUN curl -fsSL https://tailscale.com/install.sh | sh

RUN $REG_BASH

# 复制构建好的二进制文件和证书生成脚本
COPY --from=builder /app/derper /app/derper
COPY build_cert.sh /app/

# 添加健康检查（基于 GitHub Actions 工作流中的测试步骤）
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:$DERP_HTTP_PORT || exit 1

# build self-signed certs && start derper
CMD bash /app/build_cert.sh $DERP_HOST $DERP_CERTS /app/san.conf && \
    /app/derper --hostname=$DERP_HOST \
    --certmode=manual \
    --certdir=$DERP_CERTS \
    --stun=$DERP_STUN  \
    --a=$DERP_ADDR \
    --http-port=$DERP_HTTP_PORT \
    --verify-clients=$DERP_VERIFY_CLIENTS \
    --stun-port=$DERP_STUN_PORT