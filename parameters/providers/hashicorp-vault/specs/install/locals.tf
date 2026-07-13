locals {
  # Attributes are passed straight to the parameter_storage_configuration module,
  # but a null kubernetes_role is dropped: the spec schema types it as a string,
  # so emitting `null` in userpass mode would fail server-side validation. The key
  # is only included when set (i.e. auth_mode = "kubernetes").
  instance_attributes = {
    for key, instance in var.instances : key => {
      sensibility = instance.attributes.sensibility
      setup = merge(
        {
          address   = instance.attributes.setup.address
          auth_mode = instance.attributes.setup.auth_mode
        },
        instance.attributes.setup.kubernetes_role == null ? {} : {
          kubernetes_role = instance.attributes.setup.kubernetes_role
        }
      )
    }
  }
}
