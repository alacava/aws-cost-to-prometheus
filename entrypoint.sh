#!/bin/bash
set -e

# Log environment
echo "AWS_PROFILE_NAME: $AWS_PROFILE_NAME"
echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:4}****"
echo "PUSHGATEWAY_URL: $PUSHGATEWAY_URL"

# Use profile if present
if [[ -n "$AWS_PROFILE_NAME" ]]; then
  export AWS_PROFILE="$AWS_PROFILE_NAME"
  echo "🔐 Using AWS profile: $AWS_PROFILE"
else
  echo "🔐 Using AWS access keys from environment"
fi

# Set date range
t_first_date=$(date +%Y-%m-01)
t_last_date=$(date -d "`date +%Y%m01` +1 month -1 day" +%Y-%m-%d)

# Get all account IDs and names into associative array
declare -A ACCOUNT_NAMES
mapfile -t account_info < <(aws organizations list-accounts --query "Accounts[].{Id:Id,Name:Name}" --output text)
for ((i = 0; i < ${#account_info[@]}; i += 2)); do
  ACCOUNT_ID="${account_info[i]}"
  ACCOUNT_NAME="${account_info[i+1]// /_}"  # Replace spaces with underscores
  ACCOUNT_NAMES["$ACCOUNT_ID"]="$ACCOUNT_NAME"
done

# Track global total
global_total=0
metrics="# TYPE aws_cost_unblended_cost_service gauge\n"
region_metrics="# TYPE aws_cost_unblended_cost_region gauge\n"

for account_id in "${!ACCOUNT_NAMES[@]}"; do
  account_name="${ACCOUNT_NAMES[$account_id]}"
  echo "📦 Processing account: $account_id ($account_name)"

  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["'"$account_id"'"]}}' \
    --group-by Type=DIMENSION,Key=REGION > /tmp/region.json

  readarray -t regions < <(jq -c '.ResultsByTime[].Groups[]' /tmp/region.json)
  for region_entry in "${regions[@]}"; do
    region=$(echo "$region_entry" | jq -r '.Keys[0]')
    amount=$(echo "$region_entry" | jq -r '.Metrics.UnblendedCost.Amount')
    [[ "$amount" == "0" || -z "$amount" ]] && continue

    region_metrics+="aws_cost_unblended_cost_region{account_id=\"$account_id\", account=\"$account_name\", region=\"$region\"} $amount\n"
    global_total=$(echo "$global_total + $amount" | bc)
  done
done

# Add total cost metric
metrics+="aws_cost_total_unblended_cost_all_accounts $global_total\n"

# Push to Pushgateway
final_payload="$metrics\n$region_metrics"
echo -e "$final_payload" | curl -s --data-binary @- "$PUSHGATEWAY_URL/metrics/job/aws_cost"
echo "✅ Metrics pushed to Pushgateway."
