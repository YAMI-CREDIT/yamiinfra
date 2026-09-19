# -------------------------------------------------------
# Custom Auth Challenge: Passwordless phone + OTP login
# -------------------------------------------------------

# Used to hash OTPs before they're stored in privateChallengeParameters.
# Generated once and injected into both Create and Verify as an env var.
resource "random_password" "otp_hash_secret" {
  length  = 32
  special = false
}

# Shared IAM role for all three triggers. They only need to write
# CloudWatch logs; OTP delivery goes straight to Termii over HTTPS, no other
# AWS permissions required.
data "aws_iam_policy_document" "custom_auth_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "custom_auth_lambda" {
  name               = "yami-custom-auth-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.custom_auth_assume.json
}

resource "aws_iam_role_policy_attachment" "custom_auth_lambda_logs" {
  role       = aws_iam_role.custom_auth_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Define Auth Challenge
# ---------------------------------------------------------------------------

data "archive_file" "define_auth_challenge_zip" {
  type        = "zip"
  source_dir  = "${var.lambda_function_path}/define-auth-challenge"
  output_path = "${path.module}/define-auth-challenge.zip"
}

resource "aws_lambda_function" "define_auth_challenge" {
  function_name    = "yami-define-auth-challenge"
  filename         = data.archive_file.define_auth_challenge_zip.output_path
  source_code_hash = data.archive_file.define_auth_challenge_zip.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.custom_auth_lambda.arn
  timeout          = 5
}

resource "aws_lambda_permission" "cognito_invoke_define_auth_challenge" {
  statement_id  = "AllowCognitoInvokeDefineAuthChallenge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.define_auth_challenge.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.yami_users.arn
}

# ---------------------------------------------------------------------------
# OTP storage: lets CreateAuthChallenge reuse an unexpired code instead of
# sending a fresh SMS on every wrong attempt. TTL cleans up expired items.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "login_otp" {
  name           = "yami-login-otp"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "phoneNumber"

  attribute {
    name = "phoneNumber"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
}

resource "aws_iam_role_policy" "custom_auth_lambda_dynamodb" {
  name = "custom-auth-otp-table-access"
  role = aws_iam_role.custom_auth_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
      Resource = aws_dynamodb_table.login_otp.arn
    }]
  })
}

# ---------------------------------------------------------------------------
# Create Auth Challenge
# ---------------------------------------------------------------------------

data "archive_file" "create_auth_challenge_zip" {
  type        = "zip"
  source_dir  = "${var.lambda_function_path}/create-auth-challenge"
  output_path = "${path.module}/create-auth-challenge.zip"
}

resource "aws_lambda_function" "create_auth_challenge" {
  function_name    = "yami-create-auth-challenge"
  filename         = data.archive_file.create_auth_challenge_zip.output_path
  source_code_hash = data.archive_file.create_auth_challenge_zip.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.custom_auth_lambda.arn
  timeout          = 10

  environment {
    variables = {
      SMS_SENDER_APIKEY   = var.sms_sender_apikey
      SMS_SENDER_PROVIDER = var.sms_sender_provider
      OTP_HASH_SECRET     = random_password.otp_hash_secret.result
      OTP_TABLE_NAME      = aws_dynamodb_table.login_otp.name
    }
  }
}

resource "aws_lambda_permission" "cognito_invoke_create_auth_challenge" {
  statement_id  = "AllowCognitoInvokeCreateAuthChallenge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_auth_challenge.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.yami_users.arn
}

# ---------------------------------------------------------------------------
# Verify Auth Challenge Response
# ---------------------------------------------------------------------------

data "archive_file" "verify_auth_challenge_zip" {
  type        = "zip"
  source_dir  = "${var.lambda_function_path}/verify-auth-challenge-response"
  output_path = "${path.module}/verify-auth-challenge-response.zip"
}

resource "aws_lambda_function" "verify_auth_challenge_response" {
  function_name    = "yami-verify-auth-challenge-response"
  filename         = data.archive_file.verify_auth_challenge_zip.output_path
  source_code_hash = data.archive_file.verify_auth_challenge_zip.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.custom_auth_lambda.arn
  timeout          = 5

  environment {
    variables = {
      OTP_HASH_SECRET = random_password.otp_hash_secret.result
    }
  }
}

resource "aws_lambda_permission" "cognito_invoke_verify_auth_challenge" {
  statement_id  = "AllowCognitoInvokeVerifyAuthChallenge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.verify_auth_challenge_response.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.yami_users.arn
}
