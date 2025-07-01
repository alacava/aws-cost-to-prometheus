# AWS Cost to Prometheus via Pushgateway

This container pulls AWS Cost Explorer data (per account, region, and service) and pushes the results to a Prometheus Pushgateway.

## Usage

1. Copy `config.env.example` to `config.env` and fill in values.

2. Build the container:

```bash
docker build -t aws-cost-to-prometheus .
```

## Run
# If you want to use your own image, change/remove the antlac1
```bash
docker run --rm \
  --env-file ./config.env \
  antlac1/aws-cost-to-prometheus
```