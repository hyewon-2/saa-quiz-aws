# 알람이 울리면 bootstrap/alerts.tf의 SNS 주제로 보내고, 거기서 Slack으로 전달된다.
# 장애 대응 흐름: 알람(무엇이 잘못됐나) → Logs Insights 저장 쿼리(어디서, 왜) → 원인 수정

data "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

locals {
  alarm_actions = [data.aws_sns_topic.alerts.arn]
  alb_dims      = { LoadBalancer = aws_lb.main.arn_suffix }
  tg_dims       = { LoadBalancer = aws_lb.main.arn_suffix, TargetGroup = aws_lb_target_group.app.arn_suffix }
}

# ---------------------------------------------------------------------------
# 로그 → 지표: 앱이 남긴 JSON 로그의 event 필드를 세서 CloudWatch 지표로 만든다 (app/main.py).
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "db_unavailable" {
  name           = "db-unavailable"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.event = \"db_unavailable\" }"

  metric_transformation {
    namespace     = "SaaQuiz"
    name          = "DbUnavailable"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "unhandled_exception" {
  name           = "unhandled-exception"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.event = \"unhandled_exception\" }"

  metric_transformation {
    namespace     = "SaaQuiz"
    name          = "UnhandledException"
    value         = "1"
    default_value = "0"
  }
}

# ---------------------------------------------------------------------------
# 알람
# ---------------------------------------------------------------------------

# 앱이 5xx를 응답했다 (앱 버그, DB 장애 등).
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project}-target-5xx"
  alarm_description   = "앱(태스크)이 1분 동안 5xx를 5번 이상 응답했다. Logs Insights '5xx 요청' 쿼리로 경로와 에러를 확인한다."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dims
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching" # 요청이 없으면 지표가 비어 있다. 이건 정상으로 본다.
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ALB 자신이 5xx를 응답했다. 주로 정상 태스크가 하나도 없을 때(502/503) 또는 태스크가 응답하지 않을 때(504).
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.project}-elb-5xx"
  alarm_description   = "ALB가 1분 동안 5xx를 5번 이상 응답했다. 대상 그룹에 정상 태스크가 있는지, 보안그룹(ALB→앱)이 열려 있는지 확인한다."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = local.alb_dims
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# 헬스체크에 실패하는 태스크가 있다 (배포한 새 버전이 안 뜨는 경우 등).
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project}-unhealthy-hosts"
  alarm_description   = "헬스체크(/health)에 실패하는 태스크가 2분 이상 있다. ECS 태스크의 중지 이유와 앱 로그를 확인한다."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# 응답이 느리다. 평균은 느린 요청 몇 개를 가려 버려서 p95(느린 쪽 5%)를 본다.
resource "aws_cloudwatch_metric_alarm" "slow_responses" {
  alarm_name          = "${var.project}-slow-responses"
  alarm_description   = "응답 시간 p95가 3분 연속 1초를 넘었다. Logs Insights '느린 API' 쿼리로 어느 경로가 느린지 확인한다."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dims
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# 앱이 DB에 연결하지 못했다. 5xx 알람보다 원인이 구체적이라 따로 둔다.
resource "aws_cloudwatch_metric_alarm" "db_unavailable" {
  alarm_name          = "${var.project}-db-unavailable"
  alarm_description   = "앱이 DB에 연결하지 못했다. RDS 상태, 보안그룹(앱→DB 5432), DB 비밀번호(Secrets Manager)를 확인한다."
  namespace           = "SaaQuiz"
  metric_name         = "DbUnavailable"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------------------------------------------------------------------------
# Logs Insights 저장 쿼리: 알람이 울렸을 때 바로 열어 보는 용도
# CloudWatch 콘솔 → Logs Insights → 오른쪽 "쿼리" 탭 → 저장된 쿼리
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_query_definition" "errors" {
  name            = "${var.project}/5xx 요청과 에러"
  log_group_names = [aws_cloudwatch_log_group.app.name]
  query_string    = <<-EOT
    fields @timestamp, status, method, path, event, message, exception, host, version
    | filter status >= 500 or level = "ERROR"
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "slow_routes" {
  name            = "${var.project}/느린 API (경로별 응답 시간)"
  log_group_names = [aws_cloudwatch_log_group.app.name]
  query_string    = <<-EOT
    filter event = "request"
    | stats count(*) as requests, avg(duration_ms) as avg_ms, pct(duration_ms, 95) as p95_ms, max(duration_ms) as max_ms by route
    | sort p95_ms desc
  EOT
}
