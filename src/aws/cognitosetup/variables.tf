variable "lambda_function_path" {
  description = "path to the Lambda function code"
  type        = string
//  default     = "src/aws/lambdas/sms_sender"
}

variable "sms_sender_provider" {
  description = "endpoint URL for sending SMS OTP"
  type        = string
  # default     = "https://v3.api.termii.com/api/sms/send"
}

variable "sms_sender_apikey" {
  description = "API key for the SMS sender provider"
  type        = string
}
