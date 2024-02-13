# what role will the lambda act under
resource "aws_iam_role" "lambda_role" {
name   = "PullQuote_Lambda_Role"
assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

# what policy will define the permissions associated with the IAM role above
resource "aws_iam_policy" "iam_policy_for_lambda" {
 
 name         = "aws_iam_policy_for_terraform_aws_lambda_role"
 path         = "/"
 description  = "AWS IAM Policy for managing aws lambda role"
 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}

# attach the policy to the role
resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
 role        = aws_iam_role.lambda_role.name
 policy_arn  = aws_iam_policy.iam_policy_for_lambda.arn
}

# zip the python to allow upload to aws lambda
data "archive_file" "lambda_resources_zip" {
type        = "zip"
output_path = "${path.module}/pull_quote.zip"
source_dir  = "${path.module}/src/Function/"
}

# create the lambda resource
resource "aws_lambda_function" "terraform_lambda_func" {
filename                       = "${path.module}/pull_quote.zip"
function_name                  = "PullQuote_Lambda"
source_code_hash               = "${data.archive_file.lambda_resources_zip.output_base64sha256}"
role                           = aws_iam_role.lambda_role.arn
handler                        = "pull_quote.lambda_handler"
runtime                        = "python3.11"
depends_on                     = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}