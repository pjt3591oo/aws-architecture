resource "aws_glue_catalog_database" "this" {
  name        = local.glue_database
  description = "Kinesis Analytics Demo"
}

resource "aws_glue_catalog_table" "this" {
  name          = local.glue_table
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification  = "json"
    compressionType = "gzip"
    typeOfData      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.this.bucket}/${local.raw_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }
    columns {
      name = "event_type"
      type = "string"
    }
    columns {
      name = "user_id"
      type = "string"
    }
    columns {
      name = "product_id"
      type = "string"
    }
    columns {
      name = "amount"
      type = "double"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
  }
}

resource "aws_athena_workgroup" "this" {
  name = local.athena_workgroup

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.this.bucket}/${local.athena_prefix}"
    }
  }
}
