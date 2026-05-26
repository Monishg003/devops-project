FROM alpine:3.18 AS builder

WORKDIR /build

RUN echo "Building application..." && \
    mkdir -p src && \
    echo "app.name=DevOps Platform" > src/app.properties && \
    echo "app.version=1.0.0" >> src/app.properties && \
    echo "app.built=$(date)" >> src/app.properties

RUN [ -f src/app.properties ] && \
    echo "Build successful" || \
    (echo "Build failed" && exit 1)


FROM alpine:3.18 AS runtime

LABEL maintainer="monish@devops.com"
LABEL version="1.0.0"
LABEL project="devops-final-project"
LABEL security.scan="trivy-verified"

RUN apk add --no-cache \
    bash \
    curl \
    wget \
    python3 \
    postgresql-client \
    && rm -rf /var/cache/apk/*

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

RUN mkdir -p /app/config /app/logs /app/tmp && \
    chown -R appuser:appgroup /app

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup \
    /build/src/app.properties config/

COPY --chown=appuser:appgroup app/start.sh .
RUN chmod +x start.sh

USER appuser

HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=40s \
            --retries=3 \
    CMD wget -q --spider \
        http://localhost:${APP_PORT:-8080}/health \
        || exit 1

EXPOSE 8080

CMD ["./start.sh"]
