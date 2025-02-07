#!/bin/bash
# deploy_lambda.sh
#
# This script packages a Python Lambda function that sends AWS CloudTrail event
# notifications to a Slack channel and deploys it to AWS.
#
# Prerequisites:
#   - AWS CLI must be installed and configured.
#   - zip utility must be installed.
#   - The IAM role specified (LAMBDA_ROLE_ARN) must have permissions for Lambda execution.
#
# Configuration: Update the variables below as needed.

# -------------------------------
# CONFIGURATION VARIABLES
# -------------------------------
LAMBDA_FUNCTION_NAME="MySlackNotifierFunction"   # Name of the Lambda function to create
LAMBDA_RUNTIME="python3.8"                          # Python runtime version (e.g., python3.8)
LAMBDA_ROLE_ARN="arn:aws:iam::xxxxxxxxxxxx:role/YourLambdaRole"  # Replace with your Lambda execution role ARN
LAMBDA_HANDLER="lambda_function.lambda_handler"   # The handler (filename.function_name)
ZIP_FILE="lambda_function.zip"                      # The name of the ZIP file to create
SOURCE_FILE="lambda_function.py"                    # The source code file name

# Set your Slack webhook URL here (or ensure it’s set as an environment variable on Lambda)
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxxxxxxx/xxxxxxxx/xxxxxxxxx"

# -------------------------------
# STEP 1: Write the Lambda Code to a File
# -------------------------------
cat > ${SOURCE_FILE} << 'EOF'
import json
import os
import urllib.request
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Read Slack Webhook URL from environment variables
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")

def extract_resource_details(detail, event_name):
    """
    Extract resource details from the CloudTrail event detail based on event_name.
    Returns a tuple of (resourceKey, resourceValue). If not found, returns ("", "").
    """
    resourceKey = ""
    resourceValue = ""
    response_elements = detail.get("responseElements", {})
    request_parameters = detail.get("requestParameters", {})

    if event_name in ["TerminateInstances", "RunInstances"]:
        instances_set = response_elements.get("instancesSet", {})
        items = instances_set.get("items", [])
        if items:
            resourceKey = "Instance_ID"
            resourceValue = items[0].get("instanceId", "")
    elif event_name in ["CreateDBInstance", "DeleteDBInstance"]:
        resourceKey = "DB_Instance_ID"
        resourceValue = response_elements.get("dBInstanceIdentifier", "")
    elif event_name in ["CreateLoadBalancer", "DeleteLoadBalancer"]:
        load_balancers = response_elements.get("loadBalancers", [])
        if load_balancers:
            resourceKey = "LoadBalancer_ID"
            resourceValue = load_balancers[0].get("loadBalancerName", "")
    elif event_name in ["CreateUser", "DeleteUser"]:
        user_info = response_elements.get("user", {})
        resourceKey = "User_ID"
        resourceValue = user_info.get("userName", "")
    elif event_name in ["CreateGroup", "DeleteGroup"]:
        group_info = response_elements.get("group", {})
        resourceKey = "Group"
        resourceValue = group_info.get("groupName", "")
    elif event_name in ["CreateRole", "DeleteRole"]:
        role_info = response_elements.get("role", {})
        resourceKey = "Role"
        resourceValue = role_info.get("roleName", "")
    elif event_name in ["CreatePolicy", "DeletePolicy"]:
        policy_info = response_elements.get("policy", {})
        resourceKey = "Policy"
        resourceValue = policy_info.get("policyName", "")
    elif event_name in ["CreateCluster", "DeleteCluster"]:
        cluster_info = response_elements.get("cluster", {})
        resourceKey = "Cluster"
        resourceValue = cluster_info.get("clusterName", "")
    elif event_name in ["CreateRestApi", "DeleteRestApi"]:
        resourceKey = "RestApi"
        resourceValue = response_elements.get("id", "")
    elif event_name in ["CreatePipeline", "DeletePipeline"]:
        pipeline_info = response_elements.get("pipeline", {})
        resourceKey = "Pipeline"
        resourceValue = pipeline_info.get("pipelineName", "")
    elif event_name in ["CreateProject", "DeleteProject", "UpdateProject"]:
        project_info = response_elements.get("project", {})
        resourceKey = "Project"
        resourceValue = project_info.get("projectName", "")
    elif event_name in ["CreateApplication", "DeleteApplication"]:
        application_info = response_elements.get("application", {})
        resourceKey = "Application"
        resourceValue = application_info.get("applicationName", "")
    elif event_name in ["CreateHostedZone", "DeleteHostedZone"]:
        hosted_zone_info = response_elements.get("hostedZone", {})
        resourceKey = "HostedZone"
        resourceValue = hosted_zone_info.get("id", "")
    elif event_name == "CreateSecret":
        resourceKey = "Secret_ID"
        resourceValue = request_parameters.get("name", "")
    elif event_name == "DeleteSecret":
        resourceKey = "Secret_ID"
        resourceValue = response_elements.get("name", "")
    elif event_name in ["CreateRepository", "DeleteRepository"]:
        repository_info = response_elements.get("repository", {})
        resourceKey = "Repository Name"
        resourceValue = repository_info.get("repositoryName", "")
    elif event_name in ["CreateAutoScalingGroup", "DeleteAutoScalingGroup"]:
        resourceKey = "AutoScalingGroup"
        resourceValue = response_elements.get("autoScalingGroupName", "")
    
    return resourceKey, resourceValue

def lambda_handler(event, context):
    """
    Lambda function triggered by AWS CloudTrail (via EventBridge) to send 
    notifications to a Slack channel when an AWS infrastructure change occurs.
    """
    logger.info("Received event: %s", json.dumps(event))
    
    try:
        detail = event.get("detail", {})
        event_name = detail.get("eventName", "UnknownEvent")
        user_identity = detail.get("userIdentity", {})
        aws_region = detail.get("awsRegion", "Unknown")
        event_time = detail.get("eventTime", "Unknown")
        event_source = detail.get("eventSource", "Unknown")

        # Extract user details
        user_name = user_identity.get("userName") or user_identity.get("principalId", "UnknownUser")
        if ":" in user_name:
            user_name = user_name.split(":")[-1]

        # Filter notifications based on user_name (only notify if contains '@xyz.com')
        if "@xyz.com" not in user_name:
            logger.info("User %s does not match notification criteria. Skipping.", user_name)
            return {"statusCode": 200, "body": "User not in notify list."}

        # Extract resource details using the helper function
        resourceKey, resourceValue = extract_resource_details(detail, event_name)

        # Construct the Slack message payload
        slack_message = {
            "text": (
                f"*AWS Infrastructure Change Detected! 🚨*\n"
                f"👤 User: `{user_name}`\n"
                f"🛠 Event Source: `{event_source}`\n"
                f"🛠 Event: `{event_name}`\n"
                f"{f'🛠 {resourceKey}: `{resourceValue}`\n' if resourceKey and resourceValue else ''}"
                f"🌍 Region: `{aws_region}`\n"
                f"🕒 Time: `{event_time}`\n"
            )
        }
        logger.info("Sending Slack alert: %s", slack_message)

        # Send alert to Slack
        send_slack_notification(slack_message)
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Notification sent",
                "slack_message": slack_message
            })
        }
    except Exception as e:
        logger.exception("Error processing event: %s", str(e))
        return {"statusCode": 500, "body": f"Error processing event: {str(e)}"}

def send_slack_notification(message):
    """
    Sends the formatted message to Slack via the incoming webhook.
    """
    if not SLACK_WEBHOOK_URL:
        logger.error("SLACK_WEBHOOK_URL not set in environment variables.")
        return

    req = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=json.dumps(message).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            logger.info("Slack Notification Sent! Response Code: %s", response.status)
    except Exception as e:
        logger.error("Error sending Slack notification: %s", str(e))
EOF

# -------------------------------
# STEP 2: Package the Lambda Function
# -------------------------------
echo "Packaging Lambda deployment package..."
zip ${ZIP_FILE} ${SOURCE_FILE}
if [ $? -ne 0 ]; then
    echo "Error: Failed to create ZIP package."
    exit 1
fi

# -------------------------------
# STEP 3: Deploy the Lambda Function to AWS
# -------------------------------
echo "Deploying Lambda function ${LAMBDA_FUNCTION_NAME}..."

aws lambda create-function \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --runtime "${LAMBDA_RUNTIME}" \
    --role "${LAMBDA_ROLE_ARN}" \
    --handler "${LAMBDA_HANDLER}" \
    --zip-file fileb://${ZIP_FILE} \
    --environment "Variables={SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}}" \
    --timeout 10 \
    --memory-size 128

if [ $? -eq 0 ]; then
    echo "Lambda function deployed successfully!"
else
    echo "Failed to deploy Lambda function."
fi
