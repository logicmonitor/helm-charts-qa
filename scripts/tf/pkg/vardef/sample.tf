variable "lm-container-configuration2" {
  type = object({
    argus = object({
      image = optional(object({
        tag = optional(string)
      }))
    })
  })
}

locals {
  lm-container-configuration = defaults(var.lm-container-configuration, {
    argus = {
      image = {
        tag = ""
      }
    }
  })
}

