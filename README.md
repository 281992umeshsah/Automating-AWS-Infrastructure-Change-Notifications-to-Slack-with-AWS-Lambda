# Automating-AWS-Infrastructure-Change-Notifications-to-Slack-with-AWS-Lambda
Automating AWS Infrastructure Change Notifications to Slack with AWS Lambda

How to Use This Script
Update the Configuration:
Modify the variables at the top of the script (such as LAMBDA_FUNCTION_NAME, LAMBDA_ROLE_ARN, and SLACK_WEBHOOK_URL) to match your environment.

Ensure Prerequisites Are Met:
Make sure the AWS CLI is configured with the appropriate credentials, and that the zip utility is installed on your system.

Run the Script:
Save the script as deploy_lambda.sh, give it executable permissions with:

bash
Copy
chmod +x deploy_lambda.sh
Then run it:

bash
Copy
./deploy_lambda.sh
This script will package your Lambda function code into a ZIP file, deploy the function using the AWS CLI, and set the Slack webhook URL as an environment variable for your Lambda. If the deployment is successful, you’ll see a confirmation message.


