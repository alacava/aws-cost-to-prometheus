FROM amazonlinux:2

RUN yum install -y \
    python3 \
    jq \
    curl \
    unzip \
    awscli \
 && pip3 install --upgrade pip

WORKDIR /app
COPY entrypoint.sh config.env ./
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]
