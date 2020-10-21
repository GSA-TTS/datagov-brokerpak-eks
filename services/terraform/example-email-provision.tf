variable domain {
    type = string
}

variable username {
    type = string
}

output email {
    value = "${var.username}@${var.domain}"
}
