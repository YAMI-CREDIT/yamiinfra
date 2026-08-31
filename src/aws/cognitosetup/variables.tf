variable "backend_user_registration_url" {
  description = "HTTPS endpoint on backend that receives confirmed user registration"
  type        = string
  default     = "https://yamicredit.com/api/v1/users"
}