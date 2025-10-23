FROM golang:latest AS builder

LABEL org.opencontainers.image.source = https://github.com/realtvop/ip_derper_air

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

FROM ghcr.io/tailscale/tailscale:latest
WORKDIR /app

# ========= CONFIG =========
# - derper args
ENV DERP_ADDR=443
ENV DERP_HTTP_PORT=80
ENV DERP_HOST=127.0.0.1
ENV DERP_CERTS=/app/certs
ENV DERP_STUN=true
ENV DERP_STUN_PORT=3478
# 不修改，兼容旧版
ENV DERP_VERIFY_CLIENTS=false
# 适配自带防盗
ENV TS_AUTHKEY=""
ENV TS_STATE_DIR=/var/lib/tailscale
ENV TS_EXTRA_ARGS="--advertise-tags=tag:container"
# ==========================

# 安装依赖（与原 Dockerfile 保持一致）
RUN apk update && \
    apk add openssl curl caddy

#RUN curl -fsSL https://tailscale.com/install.sh | sh

# 复制构建好的二进制文件和证书生成脚本
COPY --from=builder /app/derper /app/derper
COPY build_cert.sh /app/
COPY start_ts.sh /app/
COPY start_caddy.sh /app/

# build self-signed certs && start derper
CMD /bin/sh /app/start_ts.sh && \
    /bin/sh /app/start_caddy.sh && \
    /bin/sh /app/build_cert.sh $DERP_HOST $DERP_CERTS /app/san.conf && \
    tailscale netcheck && \
    /app/derper --hostname=$DERP_HOST \
    --certmode=manual \
    --certdir=$DERP_CERTS \
    --stun=$DERP_STUN  \
    --a=:$DERP_ADDR \
    --http-port=$DERP_HTTP_PORT \
    --verify-clients=$DERP_VERIFY_CLIENTS \
    --stun-port=$DERP_STUN_PORT
