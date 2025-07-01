#!/bin/bash
set -e

# Log environment info
echo "🔐 AWS_PROFILE_NAME: $AWS_PROFILE_NAME"
echo "🔐 AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:4}****"
echo "📡 PUSHGATEWAY_URL: $PUSHGATEWAY_URL"

# Use profile if provided
if [[ -n "$AWS_PROFILE_NAME" ]]; then
  export AWS_PROFILE="$AWS_PROFILE_NAME"
  echo "🔐 Using AWS profile: $AWS_PROFILE"
else
  echo "🔐 Using AWS access keys from environment"
fi

# Set date range
t_first_date=$(date +%Y-%m-01)
t_last_date=$(date -d "`date +%Y%m01` +1 month -1 day" +%Y-%m-%d)

echo "📆 Date range: $t_first_date → $t_last_date"

# Build map of account IDs to account names
declare -A ACCOUNT_NAMES
mapfile -t account_info < <(aws organizations list-accounts --query "Accounts[].{Id:Id,Name:Name}" --output text)
for ((i = 0; i < ${#account_info[@]}; i += 2)); do
  ACCOUNT_ID="${account_info[i]}"
  ACCOUNT_NAME="${account_info[i+1]// /_}"  # Replace spaces with underscores
  ACCOUNT_NAMES["$ACCOUNT_ID"]="$ACCOUNT_NAME"
done

# Initialize metric strings
region_metrics="# TYPE aws_cost_unblended_cost_region gauge\n"
total_cost=0

# Loop through all accounts
for account_id in "${!ACCOUNT_NAMES[@]}"; do
  account_name="${ACCOUNT_NAMES[$account_id]}"
  echo "📦 Processing account: $account_id ($account_name)"

  # Query cost data by region
  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter "{\"Dimensions\":{\"Key\":\"LINKED_ACCOUNT\",\"Values\":[\"$account_id\"]}}" \
    --group-by Type=DIMENSION,Key=REGION > /tmp/region.json

  # Process each region entry
  readarray -t regions < <(jq -c '.ResultsByTime[].Groups[]' /tmp/region.json)
  for region_entry in "${regions[@]}"; do
    region=$(echo "$region_entry" | jq -r '.Keys[0]')
    amount=$(echo "$region_entry" | jq -r '.Metrics.UnblendedCost.Amount')
    [[ "$amount" == "0" || -z "$amount" ]] && continue

    region_metrics+="aws_cost_unblended_cost_region{account_id=\"$account_id\",account=\"$account_name\",region=\"$region\"} $amount\n"
    total_cost=$(echo "$total_cost + $amount" | bc)
  done
done

# Add total metric
region_metrics+="\n# TYPE aws_cost_total_unblended_cost_all_accounts gauge\n"
region_metrics+="aws_cost_total_unblended_cost_all_accounts $total_cost\n"

# Push to Pushgateway
echo -e "$region_metrics" | curl -s --data-binary @- "$PUSHGATEWAY_URL/metrics/job/aws_cost"
echo "✅ Pushed metrics to $PUSHGATEWAY_URL"
