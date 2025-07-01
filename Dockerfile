FROM amazonlinux:2023

# Install required tools
RUN yum install -y \
    python3 \
    jq \
    curl \
    unzip \
    zip \
    less \
    groff \
    tar \
    && yum clean all

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Upgrade pip just in case
RUN pip3 install --upgrade pip

# Create app directory
WORKDIR /app
COPY entrypoint.sh config.env ./
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]