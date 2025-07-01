FROM amazonlinux:2023

RUN yum install -y \
    python3 \
    jq \
    curl \
    unzip \
    awscli \
 && pip3 install --upgrade pip

WORKDIR /app
COPY entrypoint.sh config.env.example ./
RUN chmod +x entrypoint.sh

CMD ["./entrypoint.sh"]
