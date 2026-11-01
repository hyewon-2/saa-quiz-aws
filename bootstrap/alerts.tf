# 알림 통로: CloudWatch 알람(infra/monitoring.tf) → SNS 주제 → Amazon Q Developer(구 AWS Chatbot) → Slack
# 항상 켜 두는 레이어에 둔다. 비용이 없고, Slack 연결을 매일 다시 만들 필요가 없다.

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

# Chatbot API는 일부 리전에만 있다. 서울에는 없어서 us-west-2로 호출한다 (SNS 주제는 서울에 있어도 된다).
provider "aws" {
  alias   = "chatbot"
  region  = "us-west-2"
  profile = var.aws_profile

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Layer     = "bootstrap"
    }
  }
}

data "aws_iam_policy_document" "chatbot_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

# Slack 메시지에 알람 그래프를 붙일 때 CloudWatch를 읽는다. 쓰기 권한은 없다.
resource "aws_iam_role" "chatbot" {
  name               = "${var.project}-chatbot"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume.json
}

resource "aws_iam_role_policy_attachment" "chatbot_cloudwatch_read" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "alerts" {
  provider = aws.chatbot

  configuration_name = "${var.project}-alerts"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id
  sns_topic_arns     = [aws_sns_topic.alerts.arn]

  # Slack 채널에서 누가 명령을 입력해도 읽기 이상은 못 하게 상한을 둔다. 기본값은 관리자 권한이다.
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  logging_level         = "ERROR"
}
