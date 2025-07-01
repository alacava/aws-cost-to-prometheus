# AWS Cost Metrics Exporter

This Docker-based script collects AWS Cost Explorer data and exports it to Prometheus Pushgateway, providing visibility into your organization's cloud spend.

## 📊 Prometheus Metrics

The following metrics are pushed to [Prometheus Pushgateway](https://prometheus.io/docs/practices/pushing/) by this script:

| Metric Name                                      | Labels                                | Description                                      |
|--------------------------------------------------|----------------------------------------|--------------------------------------------------|
| `aws_cost_unblended_cost_service`               | `account_id`, `service`               | Monthly unblended cost by AWS service per account |
| `aws_cost_unblended_cost_region`                | `account_id`, `region`                | Monthly unblended cost by AWS region per account |
| `aws_cost_total_unblended_cost_by_account`      | `account_id`,                         | Monthly unblended cost by AWS account            |
| `aws_cost_daily_unblended_cost_account`         | `account_id`, `day`                   | Daily cost per account (`today`, `yesterday`)    |
| `aws_cost_daily_unblended_cost_account_service` | `account_id`, `service`, `day`        | Daily cost by service per account                |
| `aws_cost_total_unblended_cost_all_accounts`    | *(none)*                              | Total monthly cost across all AWS accounts       |
| `aws_cost_total_unblended_cost_by_service`      | `service`                             | Total monthly cost across all accounts per service |
| `aws_cost_forecast_unblended_cost_all_accounts` | *(none)*                              | Forecasted total cost for the current month      |
| `aws_cost_daily_unblended_cost_all_accounts`    | `day` (`today`, `yesterday`)          | Daily total cost across all AWS accounts         |

## 🐳 Usage

1. Set your AWS credentials and Pushgateway URL in `config.env`.
2. Build and run the Docker container.

```bash
docker build -t aws-cost-exporter .
docker run --env-file=config.env aws-cost-exporter
```

## 🔧 Environment Variables

| Variable            | Description                              |
|---------------------|------------------------------------------|
| `AWS_ACCESS_KEY_ID` | AWS access key (if not using a profile)  |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key                       |
| `AWS_PROFILE_NAME`  | Optional AWS CLI profile name            |
| `PUSHGATEWAY_URL`   | Prometheus Pushgateway endpoint          |

## 📁 Output

All metrics are pushed to the Pushgateway under job name `aws_cost`, with per-account sub-jobs.