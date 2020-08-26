variable domain {
    type = string
}

variable address {
    type = string
}

variable password_special_chars {
    type = string
}

resource "random_string" "password" {
    length = 16
    special = true
    override_special = var.password_special_chars
}

output uri {
    value = "smtp://${var.address}:${random_string.password.result}@smtp.${var.domain}"
}
