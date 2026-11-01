# 비용을 아끼려고 NAT Gateway(월 4만 원 이상)를 쓰지 않는다.
# 대신 태스크를 퍼블릭 서브넷에 두고 공인 IP를 붙여서 ECR 이미지를 받게 한다.
# 외부에서 태스크로 직접 들어오는 트래픽은 보안그룹에서 막는다 (security_groups.tf).

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # ALB는 최소 2개 AZ에 서브넷이 있어야 만들 수 있다.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  # 10.0.0.0/24, 10.0.1.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)

  tags = { Name = "${var.project}-public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # VPC 밖으로 나가는 모든 트래픽은 인터넷 게이트웨이로 보낸다.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# 프라이빗 서브넷: RDS 전용. 인터넷으로 나가는 경로가 아예 없다.
# RDS는 밖으로 나갈 일이 없어서 NAT Gateway 없이도 문제없다.
# ---------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  # 10.0.10.0/24, 10.0.11.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 10)

  tags = { Name = "${var.project}-private-${local.azs[count.index]}" }
}

# 라우트를 하나도 넣지 않는다. VPC 내부(local) 경로만 남는다.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
