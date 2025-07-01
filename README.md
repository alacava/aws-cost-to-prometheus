# AWS Cost to Prometheus via Pushgateway

This container pulls AWS Cost Explorer data (per account, region, and service) and pushes the results to a Prometheus Pushgateway.

## Usage

1. Copy `config.env.example` to `config.env` and fill in values.

2. Build the container:

```bash
docker build -t aws-cost-push .
```

## Run
```bash
docker run --rm \
  --env-file ./config.env \
  aws-cost-push
```