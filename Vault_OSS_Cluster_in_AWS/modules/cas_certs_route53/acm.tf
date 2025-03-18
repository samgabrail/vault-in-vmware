data "aws_partition" "current" {}

resource "aws_acmpca_certificate_authority_certificate" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn

  certificate       = aws_acmpca_certificate.root.certificate
  certificate_chain = aws_acmpca_certificate.root.certificate_chain
}

resource "aws_acmpca_certificate" "root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.root.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:${data.aws_partition.current.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority" "root" {
  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"


    subject {
      common_name = var.domain
    }
  }
  type = "ROOT"

  tags = var.common_tags
}


resource "aws_acmpca_permission" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn
  actions                   = ["IssueCertificate", "GetCertificate", "ListPermissions"]
  principal                 = "acm.amazonaws.com"
}



resource "aws_acmpca_certificate_authority_certificate" "subordinate" {
  certificate_authority_arn = aws_acmpca_certificate_authority.subordinate.arn

  certificate       = aws_acmpca_certificate.subordinate.certificate
  certificate_chain = aws_acmpca_certificate.subordinate.certificate_chain
}

resource "aws_acmpca_certificate" "subordinate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.subordinate.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"

  template_arn = "arn:${data.aws_partition.current.partition}:acm-pca:::template/SubordinateCACertificate_PathLen0/V1"

  validity {
    type  = "YEARS"
    value = 5
  }
}

resource "aws_acmpca_certificate_authority" "subordinate" {
  type = "SUBORDINATE"

  certificate_authority_configuration {
    key_algorithm     = "RSA_2048"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name = var.domain
    }
  }
}

# Create a delay for the subordinate CA to be ready before creating the vault certificate
resource "time_sleep" "wait_120_seconds" {
  depends_on = [aws_acmpca_certificate_authority_certificate.subordinate]

  create_duration = "120s"
}

resource "aws_acm_certificate" "vault" {
  key_algorithm             = "RSA_2048"
  domain_name               = var.lb_fqdn
  certificate_authority_arn = aws_acmpca_certificate_authority.subordinate.arn
  tags                      = var.common_tags

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [time_sleep.wait_120_seconds]
}
