##################################################################################
### first, create the EventBridge Schedule

resource "aws_iam_role" "pull_quote_scheduler_role" {
  name               = "pull_quote_scheduler_role"
  description        = "The IAM role for the EventBridge Scheduler to assume"
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

# define the policy document that will apply to the IAM role (best practice to not use heredoc / jsonencode)
data "aws_iam_policy_document" "pull_quote_scheduler_policy_document" {
  statement {
    sid = "1"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = [
      aws_lambda_function.pull_quote_lambda.arn
    ]
  }
}

resource "aws_iam_policy" "pull_quote_scheduler_iam_policy" {
  name        = "pull_quote_scheduler_iam_policy"
  description = "The policy that will apply to the EventBridge Scheduler Role"
  policy      = data.aws_iam_policy_document.pull_quote_scheduler_policy_document.json
}

# what policy will define the permissions associated with the IAM role above
resource "aws_iam_role_policy_attachment" "pull_quote_scheduler_policy_attachment" {
  policy_arn = aws_iam_policy.pull_quote_scheduler_iam_policy.arn
  role       = aws_iam_role.pull_quote_scheduler_role.name
}

# create the actual event bridge schedule
resource "aws_scheduler_schedule" "pull_quote_schedule" {
  name        = "pull_quote_schedule"
  description = "The EventBridge Scedule that will trigger the PullQuote Lambda, scheduled via cron/rate syntax"

  flexible_time_window {
    mode = "OFF"
  }

  # schedule_expression = "cron(*/1 * * * ? *)" # run every 1 minute, cron syntax
  schedule_expression = "rate(1 minutes)" # run every 1 minute, rate syntax (valid inputs are minutes, hours, days)

  target {
    arn = aws_lambda_function.pull_quote_lambda.arn # arn of the lambda

    role_arn = aws_iam_role.pull_quote_scheduler_role.arn # role that allows scheduler to start the task

    retry_policy {
      maximum_retry_attempts = 0 # don't retry
    }
  }
}

##################################################################################
### next, we create the lambda and all associated roles/policies/applications

# what role will the lambda act under
resource "aws_iam_role" "pull_quote_lambda_role" {
  name               = "pull_quote_lambda_role"
  description        = "The IAM role for the PullQuote lambda to act under"
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

# define the policy document that will apply to the IAM role (best practice to not use heredoc / jsonencode)
data "aws_iam_policy_document" "pull_quote_lambda_policy_document" {
  statement {
    sid = "1"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }

  statement {
    sid = "2"

    actions = [
      "dynamodb:PutItem"
    ]

    resources = [
      aws_dynamodb_table.quotes_raw.arn
    ]
  }
}


# what policy will define the permissions associated with the IAM role above
resource "aws_iam_policy" "pull_quote_lambda_iam_policy" {
  name        = "pull_quote_lambda_iam_policy"
  description = "The policy that will attach to the lambda role. Governs what our lambda can actually do to other aws services"
  policy      = data.aws_iam_policy_document.pull_quote_lambda_policy_document.json
}

# attach the policy to the role
resource "aws_iam_role_policy_attachment" "pull_quote_lamda_policy_attachment" {
  role       = aws_iam_role.pull_quote_lambda_role.name
  policy_arn = aws_iam_policy.pull_quote_lambda_iam_policy.arn
}

# zip the python to allow upload to aws lambda
data "archive_file" "pull_quote_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/pull_quote.zip"
  source_dir  = "${path.module}/pull_quote_lambda_function/"
}

# create the lambda resource
resource "aws_lambda_function" "pull_quote_lambda" {
  function_name    = "pull_quote"
  description      = "Lambda function to grab quote(s) from the quotable API, and store in our dynamodb table quotes_raw"
  role             = aws_iam_role.pull_quote_lambda_role.arn
  filename         = "${path.module}/pull_quote.zip"
  handler          = "pull_quote.lambda_handler"
  runtime          = "python3.11"
  depends_on       = [aws_iam_role_policy_attachment.pull_quote_lamda_policy_attachment]
  source_code_hash = data.archive_file.pull_quote_lambda_zip.output_base64sha256 # ensures terraform recognizes changed to zip payload as changes
}

##################################################################################
### lastly, we create the dynamodb table and all associated roles/policies/applications

# (nearly) raw table of quotes in the ethos of ELT (as opposed to ETL)
resource "aws_dynamodb_table" "quotes_raw" {
  name           = "quotes_raw"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "ingested_date"
  range_key      = "ingested_at"

  attribute {
    name = "ingested_date"
    type = "S"
  }

  attribute {
    name = "ingested_at"
    type = "S"
  }

  tags = {
    name  = "quotes_raw"
    level = "raw"
    repo  = "serverless-quote-elt"
  }
}
