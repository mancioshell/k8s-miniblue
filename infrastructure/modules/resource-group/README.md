# resource-group

Creates the Azure resource group that contains every other emulated resource (miniblue).

| Input | Type | Required | Notes |
|-------|------|----------|-------|
| `naming_suffix` | string | yes | Composed into the name (`rg-<suffix>`). |
| `location` | string | yes | Emulated region. |
| `tags` / `additional_tags` | map(string) | no | Merged onto the RG. |

| Output | Notes |
|--------|-------|
| `id` | Resource group ID. |
| `resource_group_name` | Name consumed by all downstream units. |
| `location` | Region. |
