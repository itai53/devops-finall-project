resource "aws_secretsmanager_secret" "db_secret" {
  name        = var.secret_name
  description = "Database credentials for RDS PostgreSQL"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode(var.secret_data)
}
