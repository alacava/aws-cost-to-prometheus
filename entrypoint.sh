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

t_first_date=$(date +%Y-%m-01)
t_last_date=$(date -d "`date +%Y%m01` +1 month -1 day" +%Y-%m-%d)

accounts=$(aws organizations list-accounts --query "Accounts[].Id" --output text)

for account_id in $accounts; do
  echo "📦 Processing account: $account_id"

  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'"$account_id"'"]}}' \
    --group-by Type=DIMENSION,Key=SERVICE > /tmp/service.json

  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'"$account_id"'"]}}' \
    --group-by Type=DIMENSION,Key=REGION > /tmp/region.json

  metrics=""
  metrics+="# TYPE aws_cost_unblended_cost_service gauge\n"
  readarray -t services < <(jq -c '.ResultsByTime[].Groups[]' /tmp/service.json)
  for svc in "${services[@]}"; do
    key=$(echo "$svc" | jq -r '.Keys[0]' | sed 's/ /_/g')
    amount=$(echo "$svc" | jq -r '.Metrics.UnblendedCost.Amount')
    metrics+="aws_cost_unblended_cost_service{account_id=\"$account_id\",service=\"$key\"} $amount\n"
  done

  metrics+="# TYPE aws_cost_unblended_cost_region gauge\n"
  readarray -t regions < <(jq -c '.ResultsByTime[].Groups[]' /tmp/region.json)
  for reg in "${regions[@]}"; do
    key=$(echo "$reg" | jq -r '.Keys[0]' | sed 's/ /_/g')
    amount=$(echo "$reg" | jq -r '.Metrics.UnblendedCost.Amount')
    metrics+="aws_cost_unblended_cost_region{account_id=\"$account_id\",region=\"$key\"} $amount\n"
  done

  echo -e "$metrics" | curl -s --data-binary @- "$PUSHGATEWAY_URL/metrics/job/aws_cost/account/$account_id"
  echo "✅ Metrics for $account_id pushed."
done