# 원본 스크립트 8~10단계: ALB / Target Group / Listener
resource "aws_lb" "demo" {
  name               = "demo-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = slice(data.aws_subnets.default.ids, 0, 2)
  security_groups    = [aws_security_group.demo.id]
}

resource "aws_lb_target_group" "demo" {
  name        = "demo-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "demo" {
  load_balancer_arn = aws_lb.demo.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
}
