locals {
#    max_subnets_per_segment = "${length(var.subnets_per_segment) > length(data.aws_availability_zones.available.names) ? length(data.aws_availability_zones.available.names) : length(var.subnets_per_segment)}"
    max_subnets_per_segment = "${var.subnets_per_segment > length(data.aws_availability_zones.available.names) ? length(data.aws_availability_zones.available.names) : var.subnets_per_segment}"   
    nat_gateway_count = "${local.max_subnets_per_segment}"
    total_subnets_per_segment = "${length(var.subnets) * local.max_subnets_per_segment}"
    
    public_base         = "${0 * local.max_subnets_per_segment}"
    private_base        = "${1 * local.max_subnets_per_segment}"
    database_base       = "${(2 * local.max_subnets_per_segment) + 1}"
    intra_base          = "${(2 * local.max_subnets_per_segment) + 2}"
    elasticache_base    = "${(2 * local.max_subnets_per_segment) + 3}"
    redshift_base       = "${(2 * local.max_subnets_per_segment) + 4 }"
}

data "aws_availability_zones" "available" {}

################
# Publiс routes
################
resource "aws_route_table" "public" {
  count = "1"

  vpc_id = "${aws_vpc.this.id}"

  tags = "${merge(
          var.tags,
          var.public_route_table_tags,
          map("Name", format("%s-public", var.name)),
        )
      }"

  lifecycle {
    create_before_destroy = true
  }    
}

resource "aws_route" "public_internet_gateway" {
  count = "1"

  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.this.id}"

  timeouts {
    create = "5m"
  }

  lifecycle {
    create_before_destroy = true
  }  
}
resource "aws_route" "private_nat_gateway" {
  count = "${var.enable_nat_gateway ? local.nat_gateway_count : 0}"

  route_table_id         = "${element(aws_route_table.private.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.this.*.id, count.index)}"

  timeouts {
    create = "5m"
  }

  lifecycle {
    create_before_destroy = true
  }  
}



#################
# Private routes
# There are so many routing tables as the largest amount of subnets of each type (really?)
#################
resource "aws_route_table" "private" {
  count = "${local.max_subnets_per_segment}"

  vpc_id = "${aws_vpc.this.id}"

  tags = "${merge(
          var.tags,
          var.private_route_table_tags,
          map("Name", format("%s-private-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])), 
        )
      }"

  lifecycle {
    # When attaching VPN gateways it is common to define aws_vpn_gateway_route_propagation
    # resources that manipulate the attributes of the routing table (typically for the private subnets)
    ignore_changes = ["propagating_vgws"]
  }
}



#################
# Intra routes
#################
resource "aws_route_table" "intra" {
  count = "${var.create_intra_subnets ? local.max_subnets_per_segment : 0}"

  vpc_id = "${aws_vpc.this.id}"

  tags = "${merge(
        var.tags,
        var.intra_route_table_tags,
        map("Name", format("%s-intra-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])), 
      )
    }"
}


################
# Public subnet
################
resource "aws_subnet" "public" {
  count = "${local.total_subnets_per_segment}"

  vpc_id                  = "${aws_vpc.this.id}"
  cidr_block              = "${cidrsubnet(cidrsubnet(var.cidr, 4, (count.index  / local.max_subnets_per_segment) ),4, (count.index % local.max_subnets_per_segment) + local.public_base) }"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment]}"
  map_public_ip_on_launch = "${var.map_public_ip_on_launch}"

  tags = "${merge(
        var.tags,
        var.public_subnet_tags,
        map("subnet-type", "public"),
        map("Name", format("%s-public-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])),         
      )
    }"

  lifecycle {
    create_before_destroy = true
  }
}

#################
# Private subnet
#################
resource "aws_subnet" "private" {
  count = "${local.total_subnets_per_segment}"

  vpc_id                  = "${aws_vpc.this.id}"
  cidr_block              = "${cidrsubnet(cidrsubnet(var.cidr, 4, (count.index  / local.max_subnets_per_segment) ), 4, (count.index % local.max_subnets_per_segment)  + local.private_base) }"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment]}"

  tags = "${merge(
        var.tags,
        var.private_subnet_tags,
        map("subnet-type", "private"),
        map("Name", format("%s-private-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])),         
      )
    }"
  
  lifecycle {
    create_before_destroy = true
  }
}


##################
# Database subnet
##################
resource "aws_subnet" "database" {
  count = "${var.create_db_subnets ? local.total_subnets_per_segment : 0}"

  vpc_id            = "${aws_vpc.this.id}"
  cidr_block        = "${cidrsubnet(cidrsubnet(cidrsubnet(var.cidr, 4, (count.index  / local.max_subnets_per_segment) ), 4, local.database_base), 2, count.index % local.max_subnets_per_segment) }"
  availability_zone = "${data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment]}"

  tags = "${merge(
        var.tags,
        var.database_subnet_tags,
        map("subnet-type", "database"),        
        map("Name", format("%s-db-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])),         
      )
    }"
  
  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_db_subnet_group" "database" {
#   count = "${var.create_db_subnets ? 1 : 0}"

#   name        = "${lower(var.name)}"
#   description = "Database subnet group for ${var.name}"
#   subnet_ids  = ["${aws_subnet.database.*.id}"]

#   tags = "${merge(
#         var.tags,
#         var.database_subnet_group_tags,
#         map("Name", format("%s-db",var.name)),         
#       )
#     }"
  
#   lifecycle {
#     create_before_destroy = true
#   }
# }

##################
# Redshift subnet
##################
resource "aws_subnet" "redshift" {
  count = "${var.create_redshift_subnets ? local.total_subnets_per_segment : 0}"
  

  vpc_id            = "${aws_vpc.this.id}"
  cidr_block        = "${cidrsubnet(cidrsubnet(cidrsubnet(var.cidr, 4, (count.index  / local.max_subnets_per_segment) ), 4, local.redshift_base), 2, count.index % local.max_subnets_per_segment)  }"
  availability_zone = "${data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment]}"

  tags = "${merge(
        var.tags,
        var.redshift_subnet_tags,
        map("subnet-type", "redshift"),
        map("Name", format("%s-redshift-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])),         
      )
    }"
  
  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_redshift_subnet_group" "redshift" {
#   count = "${var.create_redshift_subnets ? 1 : 0}"

#   name        = "${var.name}"
#   description = "Redshift subnet group for ${var.name}"
#   subnet_ids  = ["${aws_subnet.redshift.*.id}"]

#   tags = "${merge(
#       var.tags,
#       var.redshift_subnet_group_tags,
#       map("Name", format("%s", var.name)),
#     )
#   }"

#   lifecycle {
#     create_before_destroy = true
#   }

# }

#####################
# ElastiCache subnet
#####################
resource "aws_subnet" "elasticache" {
  count = "${var.create_elasticache_subnets ? local.total_subnets_per_segment : 0}"

  vpc_id            = "${aws_vpc.this.id}"
  cidr_block        = "${cidrsubnet(cidrsubnet(cidrsubnet(var.cidr, 4, (count.index  / local.max_subnets_per_segment) ), 4, local.elasticache_base), 2, count.index % local.max_subnets_per_segment) }"
  availability_zone = "${data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment]}"


  tags = "${merge(
      var.tags,
      var.elasticache_subnet_tags,
      map("subnet-type", "elasticache"),
      map("Name", format("%s-elasticache-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])),         
    )
  }"

  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_elasticache_subnet_group" "elasticache" {
#   count = "${var.create_elasticache_subnets ? 1 : 0}"

#   name        = "${var.name}"
#   description = "ElastiCache subnet group for ${var.name}"
#   subnet_ids  = ["${aws_subnet.elasticache.*.id}"]
# }

#####################################################
# intra subnets - private subnet without NAT gateway
#####################################################
resource "aws_subnet" "intra" {
  count = "${var.create_intra_subnets ? local.total_subnets_per_segment : 0}"

  vpc_id            = "${aws_vpc.this.id}"
  cidr_block        = "${cidrsubnet(cidrsubnet(cidrsubnet(var.cidr, 4, (count.index  / local.max_subnets_per_segment) ), 4, local.intra_base), 2, count.index % local.max_subnets_per_segment) }"
  availability_zone = "${data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment]}"

  tags = "${merge(
        var.tags,
        var.intra_subnet_tags,
        map("subnet-type", "intra"),
        map("Name", format("%s-intra-%s", element(var.subnets, count.index / local.max_subnets_per_segment), data.aws_availability_zones.available.names[count.index % local.max_subnets_per_segment])),         
      )
    }"
  
  lifecycle {
    create_before_destroy = true
  }
}



##########################
# Route table association
##########################



resource "aws_route_table_association" "redshift" {
  count = "${var.create_redshift_subnets ? length(var.subnets) * var.subnets_per_segment : 0}"

  subnet_id      = "${element(aws_subnet.redshift.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "elasticache" {
  count = "${var.create_elasticache_subnets ? length(var.subnets) * var.subnets_per_segment : 0}"

  subnet_id      = "${element(aws_subnet.elasticache.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "intra" {
  count = "${var.create_intra_subnets ? length(var.subnets) * var.subnets_per_segment : 0}"

  subnet_id      = "${element(aws_subnet.intra.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.intra.*.id, 0)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "public" {
  count = "${length(var.subnets) * var.subnets_per_segment}"

  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "private" {
  count = "${length(var.subnets) * var.subnets_per_segment}"

  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "database" {
  count = "${var.create_db_subnets ? length(var.subnets) * var.subnets_per_segment : 0}"
  
  subnet_id      = "${element(aws_subnet.database.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"

  lifecycle {
    create_before_destroy = true
  }
}
