# ---------------------------------------------------------------------------
# Cognito User Pool
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "yami_users" {
  name = "yami-user-pool"

  username_attributes     = ["phone_number"]
  # auto_verified_attributes = ["phone_number"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  # sms_configuration {
  #   external_id    = "yami-sms"
  #   sns_caller_arn = aws_iam_role.cognito_sms_role.arn
  # }

  # lambda_config {
  #   post_confirmation = aws_lambda_function.post_confirmation.arn
  # }

  # schema {
  #   name                = "phone_number"
  #   attribute_data_type = "String"
  #   mutable             = true
  #   required            = true
  # }
}

resource "aws_cognito_user_pool_client" "yami_client" {
  name         = "yami-client"
  user_pool_id = aws_cognito_user_pool.yami_users.id

  generate_secret = false # public client for frontend use

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]
}

# IAM role Cognito assumes to publish SMS via SNS
# resource "aws_iam_role" "cognito_sms_role" {
#   name = "cognito-sms-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = { Service = "cognito-idp.amazonaws.com" }
#       Action = "sts:AssumeRole"
#       Condition = {
#         StringEquals = { "sts:ExternalId" = "yami-sms" }
#       }
#     }]
#   })
# }

# resource "aws_iam_role_policy" "cognito_sms_policy" {
#   name = "cognito-sms-policy"
#   role = aws_iam_role.cognito_sms_role.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = "sns:Publish"
#       Resource = "*"
#     }]
#   })
# }

# # ---------------------------------------------------------------------------
# # SQS queue (with DLQ) sitting between the two Lambdas
# # ---------------------------------------------------------------------------

# resource "aws_sqs_queue" "confirmed_users_dlq" {
#   name = "confirmed-users-dlq"
# }

# resource "aws_sqs_queue" "confirmed_users" {
#   name                       = "confirmed-users"
#   visibility_timeout_seconds = 30

#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.confirmed_users_dlq.arn
#     maxReceiveCount      = 5
#   })
# }

# # ---------------------------------------------------------------------------
# # Lambda #1: Post Confirmation trigger — publishes to SQS
# # ---------------------------------------------------------------------------

# data "archive_file" "post_confirmation_zip" {
#   type        = "zip"
#   source_dir  = "${path.module}/lambdas/post-confirmation"
#   output_path = "${path.module}/build/post-confirmation.zip"
# }

# resource "aws_lambda_function" "post_confirmation" {
#   function_name    = "post-confirmation-publish"
#   filename         = data.archive_file.post_confirmation_zip.output_path
#   source_code_hash = data.archive_file.post_confirmation_zip.output_base64sha256
#   handler          = "index.handler"
#   runtime          = "nodejs20.x"
#   role             = aws_iam_role.post_confirmation_role.arn
#   timeout          = 5

#   environment {
#     variables = {
#       QUEUE_URL = aws_sqs_queue.confirmed_users.url
#     }
#   }
# }

# resource "aws_lambda_permission" "cognito_invoke" {
#   statement_id  = "AllowCognitoInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.post_confirmation.function_name
#   principal     = "cognito-idp.amazonaws.com"
#   source_arn    = aws_cognito_user_pool.yami_users.arn
# }

# resource "aws_iam_role" "post_confirmation_role" {
#   name = "post-confirmation-lambda-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "post_confirmation_logs" {
#   role       = aws_iam_role.post_confirmation_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# resource "aws_iam_role_policy" "post_confirmation_sqs_send" {
#   name = "sqs-send"
#   role = aws_iam_role.post_confirmation_role.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = "sqs:SendMessage"
#       Resource = aws_sqs_queue.confirmed_users.arn
#     }]
#   })
# }

# # ---------------------------------------------------------------------------
# # Lambda #2: Bridge — consumes SQS, calls your backend webhook
# # ---------------------------------------------------------------------------

# data "archive_file" "bridge_zip" {
#   type        = "zip"
#   source_dir  = "${path.module}/lambdas/bridge"
#   output_path = "${path.module}/build/bridge.zip"
# }

# resource "aws_lambda_function" "bridge" {
#   function_name    = "confirmed-users-bridge"
#   filename         = data.archive_file.bridge_zip.output_path
#   source_code_hash = data.archive_file.bridge_zip.output_base64sha256
#   handler          = "index.handler"
#   runtime          = "nodejs20.x"
#   role             = aws_iam_role.bridge_role.arn
#   timeout          = 10

#   environment {
#     variables = {
#       BACKEND_WEBHOOK_URL = var.backend_user_registration_url
#     }
#   }
# }

# resource "aws_lambda_event_source_mapping" "sqs_to_bridge" {
#   event_source_arn = aws_sqs_queue.confirmed_users.arn
#   function_name    = aws_lambda_function.bridge.arn
#   batch_size       = 1
# }

# resource "aws_iam_role" "bridge_role" {
#   name = "bridge-lambda-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "bridge_logs" {
#   role       = aws_iam_role.bridge_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# resource "aws_iam_role_policy" "bridge_sqs_consume" {
#   name = "sqs-consume"
#   role = aws_iam_role.bridge_role.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "sqs:ReceiveMessage",
#         "sqs:DeleteMessage",
#         "sqs:GetQueueAttributes",
#       ]
#       Resource = aws_sqs_queue.confirmed_users.arn
#     }]
#   })
# }

# # ---------------------------------------------------------------------------
# # Outputs
# # ---------------------------------------------------------------------------

# output "user_pool_id" {
#   value = aws_cognito_user_pool.yami_users.id
# }

# output "user_pool_client_id" {
#   value = aws_cognito_user_pool_client.yami_client.id
# }

# output "queue_url" {
#   value = aws_sqs_queue.confirmed_users.url
# }