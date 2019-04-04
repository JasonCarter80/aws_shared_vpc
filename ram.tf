resource "aws_ram_resource_share" "this" {
  count                     = "${length(var.subnets) - 1}"
  name                      = "${format("subnets-for-%s", element(var.subnets, count.index + 1 ))}"
  allow_external_principals = false

 tags = "${merge(
        var.tags,
      )
    }"
}