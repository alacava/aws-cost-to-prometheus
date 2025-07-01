#!/bin/bash
set -e

# Log environment info
echo "🔐 AWS_PROFILE_NAME: $AWS_PROFILE_NAME"
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

# Get account list (ID + cleaned name)
mapfile -t ACCOUNTS < <(aws organizations list-accounts \
  --query "Accounts[].{Id:Id,Name:Name}" \
  --output text)

# Initialize metric strings
region_metrics="# TYPE aws_cost_unblended_cost_region gauge\n"
total_cost=0

# Loop through accounts (each line has: ID<tab>Name)
for ((i = 0; i < ${#ACCOUNTS[@]}; i += 2)); do
  account_id="${ACCOUNTS[i]}"
  raw_name="${ACCOUNTS[i+1]}"
  account_name="${raw_name// /_}"

  echo "📦 Processing account: $account_id ($account_name)"

  # Query cost by region
  aws ce get-cost-and-usage \
    --time-period Start=$t_first_date,End=$t_last_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter "{\"Dimensions\":{\"Key\":\"LINKED_ACCOUNT\",\"Values\":[\"$account_id\"]}}" \
    --group-by Type=DIMENSION,Key=REGION > /tmp/region.json

  readarray -t regions < <(jq -c '.ResultsByTime[].Groups[]' /tmp/region.json)
  for region_entry in "${regions[@]}"; do
    region=$(echo "$region_entry" | jq -r '.Keys[0]')
    amount=$(echo "$region_entry" | jq -r '.Metrics.UnblendedCost.Amount')
    [[ "$amount" == "0" || -z "$amount" ]] && continue

    region_metrics+="aws_cost_unblended_cost_region{account_id=\"$account_id\",account=\"$account_name\",region=\"$region\"} $amount\n"
    total_cost=$(echo "$total_cost + $amount" | bc)
  done
done

# Add total cost metric
region_metrics+="\n# TYPE aws_cost_total_unblended_cost_all_accounts gauge\n"
region_metrics+="aws_cost_total_unblended_cost_all_accounts $total_cost\n"

# Push to Pushgateway
echo -e "$region_metrics" | curl -s --data-binary @- "$PUSHGATEWAY_URL/metrics/job/aws_cost"
echo "✅ Pushed metrics to $PUSHGATEWAY_URL"
