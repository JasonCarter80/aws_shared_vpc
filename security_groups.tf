resource "aws_security_group" "all_offices" {
  name        = "All Ports - Offices"
  description = "Allow all traffic from within the Offices"
  vpc_id      = "${aws_vpc.this.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    
  }
}