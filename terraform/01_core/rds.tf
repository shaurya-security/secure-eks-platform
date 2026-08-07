module "postgres" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.12.0"

  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "17"

  family               = "postgres17"
  major_engine_version = "17"

  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  manage_master_user_password = true

  vpc_security_group_ids = [aws_security_group.rds.id]

  db_subnet_group_name = module.vpc.database_subnet_group_name

  publicly_accessible = false

  deletion_protection = false
  skip_final_snapshot = true

  multi_az = false

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_security_group" "rds" {

  name        = "${var.project_name}-rds"
  description = "PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from EKS"

    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"

    cidr_blocks = [
      var.vpc_cidr
    ]
  }

  egress {

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds"
  }
}
