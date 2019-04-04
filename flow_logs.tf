resource "aws_flow_log" "flowlogs" {
  log_destination      = "arn:aws:s3:::${var.flow_logs_bucket}"
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = "${aws_vpc.this.id}"
}

