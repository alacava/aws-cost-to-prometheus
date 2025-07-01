FROM python:3.11-slim

# Install required tools
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    jq \
    ca-certificates \
    && apt-get clean

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Create app directory
WORKDIR /app
COPY entrypoint.sh config.env.example ./
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]