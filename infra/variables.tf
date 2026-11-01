variable "project" {
  type    = string
  default = "cloud-portfolio"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_profile" {
  description = "사용할 AWS CLI 프로필"
  type        = string
  default     = "personal"
}

variable "aws_account_id" {
  description = "이 계정이 아니면 Terraform이 실행을 거부한다"
  type        = string
  default     = "458255180711"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "container_port" {
  description = "컨테이너 안에서 gunicorn이 듣는 포트 (Dockerfile과 같아야 한다)"
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "동시에 실행할 태스크(컨테이너) 수. AZ마다 하나씩 두려고 2개."
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "태스크 CPU (256 = 0.25 vCPU, Fargate 최소 사양)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "태스크 메모리 MiB (256 CPU일 때 최소 512)"
  type        = number
  default     = 512
}

variable "db_instance_class" {
  description = "RDS 인스턴스 사양 (가장 작은 Graviton 사양)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "quiz"
}

variable "db_username" {
  type    = string
  default = "quiz"
}
