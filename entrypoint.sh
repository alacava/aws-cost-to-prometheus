#!/bin/bash
set -e

# Optional debug
echo "🔍 Loaded ENV:"
echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:4}****"
echo "AWS_PROFILE_NAME: $AWS_PROFILE_NAME"
echo "PUSHGATEWAY_URL: $PUSHGATEWAY_URL"

# Use AWS_PROFILE if present
if [[ -n "$AWS_PROFILE_NAME" ]]; then
  export AWS_PROFILE="$AWS_PROFILE_NAME"
  echo "🔐 Using AWS profile: $AWS_PROFILE"
else
  echo "🔐 Using AWS access keys from environment"
fi

# Set date ranges
t_today_date=$(date +%Y-%m-%d)
t_today_plus1=$(date -d "$t_today_date +1 day" +%Y-%m-%d)
t_yesterday_date=$(date -d "yesterday" +%Y-%m-%d)
t_yesterday_plus1=$(date -d "$t_yesterday_date +1 day" +%Y-%m-%d)
t_first_date=$(date +%Y-%m-01)
t_last_date=$(date -d "$(date +%Y%m01) +1 month -1 day" +%Y-%m-%d)

echo "📅 Date range: $t_first_date → $t_last_date"

accounts=$(aws organizations list-accounts --query "Accounts[].Id" --output text)
total_cost=0
declare -A SERVICE_TOTALS
declare -A ACCOUNT_TOTALS

for account_id in $accounts; do
  echo "📦 Processing account: $account_id"

  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'$account_id'"]}}' \
    --group-by Type=DIMENSION,Key=SERVICE > /tmp/service.json

  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'$account_id'"]}}' \
    --group-by Type=DIMENSION,Key=REGION > /tmp/region.json

  metrics="# TYPE aws_cost_unblended_cost_service gauge\n"
  readarray -t services < <(jq -c '.ResultsByTime[].Groups[]' /tmp/service.json)
  for svc in "${services[@]}"; do
    key=$(echo "$svc" | jq -r '.Keys[0]' | sed 's/ /_/g')
    amount=$(echo "$svc" | jq -r '.Metrics.UnblendedCost.Amount')
    metrics+="aws_cost_unblended_cost_service{account_id=\"$account_id\",service=\"$key\"} $amount\n"
    current=${SERVICE_TOTALS["$key"]:=0}
    SERVICE_TOTALS["$key"]=$(echo "$current + $amount" | bc)
  done

  metrics+="# TYPE aws_cost_unblended_cost_region gauge\n"
  readarray -t regions < <(jq -c '.ResultsByTime[].Groups[]' /tmp/region.json)
  for reg in "${regions[@]}"; do
    key=$(echo "$reg" | jq -r '.Keys[0]' | sed 's/ /_/g')
    amount=$(echo "$reg" | jq -r '.Metrics.UnblendedCost.Amount')
    metrics+="aws_cost_unblended_cost_region{account_id=\"$account_id\",region=\"$key\"} $amount\n"
    total_cost=$(echo "$total_cost + $amount" | bc)
    current_account_total=${ACCOUNT_TOTALS["$account_id"]:=0}
    ACCOUNT_TOTALS["$account_id"]=$(echo "$current_account_total + $amount" | bc)
  done

  metrics+="# TYPE aws_cost_daily_unblended_cost_account gauge\n"
  metrics+="# TYPE aws_cost_daily_unblended_cost_account_service gauge\n"
  for day_label in today yesterday; do
    if [[ $day_label == "today" ]]; then
      start_date=$t_today_date
      end_date=$t_today_plus1
    else
      start_date=$t_yesterday_date
      end_date=$t_yesterday_plus1
    fi

    daily_amount=$(aws ce get-cost-and-usage \
      --time-period Start=$start_date,End=$end_date \
      --granularity DAILY \
      --metrics "UnblendedCost" \
      --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'$account_id'"]}}' \
      | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')

    metrics+="aws_cost_daily_unblended_cost_account{account_id=\"$account_id\",day=\"$day_label\"} $daily_amount\n"

    aws ce get-cost-and-usage \
      --time-period Start=$start_date,End=$end_date \
      --granularity DAILY \
      --metrics "UnblendedCost" \
      --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'$account_id'"]}}' \
      --group-by Type=DIMENSION,Key=SERVICE > /tmp/daily_service.json

    readarray -t daily_services < <(jq -c '.ResultsByTime[].Groups[]' /tmp/daily_service.json)
    for svc in "${daily_services[@]}"; do
      service_key=$(echo "$svc" | jq -r '.Keys[0]' | sed 's/ /_/g')
      svc_amount=$(echo "$svc" | jq -r '.Metrics.UnblendedCost.Amount')
      metrics+="aws_cost_daily_unblended_cost_account_service{account_id=\"$account_id\",service=\"$service_key\",day=\"$day_label\"} $svc_amount\n"
    done
  done

  echo -e "$metrics" | curl -s --data-binary @- "$PUSHGATEWAY_URL/metrics/job/aws_cost/account/$account_id"
  echo "✅ Metrics for $account_id pushed."
done

forecast_amount=$(aws ce get-cost-forecast \
  --time-period Start=$t_today_date,End=$t_last_date \
  --granularity MONTHLY \
  --metric UNBLENDED_COST \
  | jq -r '.ForecastResultsByTime[0].MeanValue')

global_metrics="# TYPE aws_cost_total_unblended_cost_all_accounts gauge\n"
global_metrics+="aws_cost_total_unblended_cost_all_accounts $total_cost\n"

global_metrics+="\n# TYPE aws_cost_total_unblended_cost_by_service gauge\n"
for service in "${!SERVICE_TOTALS[@]}"; do
  amt=${SERVICE_TOTALS[$service]}
  global_metrics+="aws_cost_total_unblended_cost_by_service{service=\"$service\"} $amt\n"
done

global_metrics+="\n# TYPE aws_cost_total_unblended_cost_by_account gauge\n"
for acct in "${!ACCOUNT_TOTALS[@]}"; do
  total=${ACCOUNT_TOTALS[$acct]}
  global_metrics+="aws_cost_total_unblended_cost_by_account{account_id=\"$acct\"} $total\n"
done

global_metrics+="\n# TYPE aws_cost_forecast_unblended_cost_all_accounts gauge\n"
global_metrics+="aws_cost_forecast_unblended_cost_all_accounts $forecast_amount\n"

daily_today=$(aws ce get-cost-and-usage \
  --time-period Start=$t_today_date,End=$t_today_plus1 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')

daily_yesterday=$(aws ce get-cost-and-usage \
  --time-period Start=$t_yesterday_date,End=$t_yesterday_plus1 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  | jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount')

global_metrics+="\n# TYPE aws_cost_daily_unblended_cost_all_accounts gauge\n"
global_metrics+="aws_cost_daily_unblended_cost_all_accounts{day=\"today\"} $daily_today\n"
global_metrics+="aws_cost_daily_unblended_cost_all_accounts{day=\"yesterday\"} $daily_yesterday\n"

echo -e "$global_metrics" | curl -s --data-binary @- "$PUSHGATEWAY_URL/metrics/job/aws_cost_total"
echo "✅ Global totals, forecast, and daily costs pushed"
