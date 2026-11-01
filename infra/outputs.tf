output "alb_url" {
  description = "브라우저에서 열 주소"
  value       = "http://${aws_lb.main.dns_name}"
}

output "deployed_image" {
  value = "${data.aws_ecr_repository.app.repository_url}:${try(data.aws_ecr_image.latest.image_tags[0], "untagged")}"
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service" {
  value = aws_ecs_service.app.name
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}
