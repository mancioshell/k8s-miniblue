include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/resource-group"
}

# naming_suffix, location, tags supplied by root.hcl inputs.
