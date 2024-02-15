##################################################################################
### first, create the EventBridge Schedule

resource "aws_scheduler_schedule" "cron" {
  name        = "PullQuote_Schedule"
  group_name  = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(*/1 * * * ? *)" # run every 30 minutes

  target {
    arn      = aws_lambda_function.terraform_lambda_func.arn # arn of the lambda
    # role that allows scheduler to start the task (explained later)
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_event_age_in_seconds = 300
      maximum_retry_attempts       = 10
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name = "cron-scheduler-role"
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "scheduler.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  policy_arn = aws_iam_policy.scheduler.arn
  role       = aws_iam_role.scheduler.name
}

resource "aws_iam_policy" "scheduler" {
  name = "cron-scheduler-policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:lambda:*:*:*"
    }
  ]
}
EOF
}

##################################################################################
### next, we create the lambda and all associated roles/policies/applications

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
    },
    {
      "Action": [
        "dynamodb:PutItem"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:dynamodb:*:*:*"
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

##################################################################################
### last, we create the dynamodb table and all associated roles/policies/applications

resource "aws_dynamodb_table" "quotes_raw" {
  name           = "quotes_raw"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "quote_id"
  range_key      = "ingested_at"

  attribute {
    name = "quote_id"
    type = "S"
  }

  attribute {
    name = "ingested_at"
    type = "S"
  }

  tags = {
    Name        = "dynamodb-table-1"
    Environment = "production"
  }
}
