# ---------------------------------------------------------------------------
# Cognito User Pool
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "yami_users" {
  name = "yami-user-pool"

  username_attributes     = ["phone_number"]
  auto_verified_attributes = ["phone_number"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  sms_configuration {
    external_id    = "yami-sms"
    sns_caller_arn = aws_iam_role.cognito_sms_role.arn
  }

  lambda_config {
    kms_key_id = aws_kms_key.cognito_otp_key.arn

    custom_sms_sender {
      lambda_arn     = aws_lambda_function.registration_otp_sender.arn
      lambda_version = "V1_0"
    }
    create_auth_challenge = aws_lambda_function.create_auth_challenge.arn
    define_auth_challenge = aws_lambda_function.define_auth_challenge.arn
    verify_auth_challenge_response = aws_lambda_function.verify_auth_challenge_response.arn
  }

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
    "ALLOW_CUSTOM_AUTH",
  ]
}

# IAM role Cognito assumes to publish SMS via SNS
resource "aws_iam_role" "cognito_sms_role" {
  name = "cognito-sms-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "cognito-idp.amazonaws.com" }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = "yami-sms" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cognito_sms_policy" {
  name = "cognito-sms-policy"
  role = aws_iam_role.cognito_sms_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = "*"
    }]
  })
}

resource "aws_kms_key" "cognito_otp_key" {
description = "Custom key for encrypting and decrypting cognito OTP"
key_usage   = "ENCRYPT_DECRYPT"
enable_key_rotation     = true
deletion_window_in_days = 7
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key_policy" "cognito_otp_key_policy" {
  key_id = aws_kms_key.cognito_otp_key.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCognitoToEncryptCodes"
        Effect    = "Allow"
        Principal = { Service = "cognito-idp.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:CreateGrant",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = aws_cognito_user_pool.yami_users.arn
          }
        }
      },
      {
        Sid       = "AllowSmsSenderLambdaToDecrypt"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.registration_otp.arn }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })
}


# ---------------------------------------------------------------------------
# Lambda: Registration OTP Sender — decrypts the OTP, forwards to the sender API
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "registration_otp_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "registration_otp" {
  name               = "yami-regisration-otp-role"
  assume_role_policy = data.aws_iam_policy_document.registration_otp_assume.json
}

resource "aws_iam_role_policy_attachment" "registration_otp_logs" {
  role       = aws_iam_role.registration_otp.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "cognito_otp_kms_decrypt" {
  name = "decrypt-cognito-otp"
  role = aws_iam_role.registration_otp.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:DescribeKey"]
      Resource = aws_kms_key.cognito_otp_key.arn
    }]
  })
}

data "archive_file" "registeration_otp_zip" {
  type        = "zip"
  source_dir  = "${var.lambda_function_path}/registration-otp"
  output_path = "${path.module}/registeration_otp.zip"
}

resource "aws_lambda_function" "registration_otp_sender" {
  function_name    = "yami-regisration-otp-sender"
  filename         = data.archive_file.registeration_otp_zip.output_path
  source_code_hash = data.archive_file.registeration_otp_zip.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.registration_otp.arn
  timeout          = 10

  environment {
    variables = {
      SMS_SENDER_APIKEY  = var.sms_sender_apikey
      SMS_SENDER_PROVIDER = var.sms_sender_provider
      KMS_KEY_ARN = aws_kms_key.cognito_otp_key.arn
    }
  }
}

resource "aws_lambda_permission" "cognito_invoke_registration_otp" {
  statement_id  = "AllowCognitoInvokeSmsSender"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.registration_otp_sender.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.yami_users.arn
}
