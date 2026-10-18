FROM python:3.15-slim

# Install required tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    jq \
    bc \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Create app directory
WORKDIR /app
COPY entrypoint.sh config.env.example ./
RUN chmod +x entrypoint.sh

# Create non-root user for running the application
RUN useradd -m -u 1000 -s /bin/bash appuser
USER appuser

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["./entrypoint.sh"]