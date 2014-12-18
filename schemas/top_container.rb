{
  :schema => {
    "$schema" => "http://www.archivesspace.org/archivesspace.json",
    "version" => 1,
    "type" => "object",
    "uri" => "/repositories/:repo_id/top_containers",

    "properties" => {

      "uri" => {"type" => "string", "required" => false},

      "type" => {"type" => "string", "dynamic_enum" => "container_type", "ifmissing" => "error"},
      "indicator" => {"type" => "string", "maxLength" => 255, "minLength" => 1, "ifmissing" => "error" },

      "display_string" => {"type" => "string", "readonly" => true},

      "barcode" => {"type" => "string", "maxLength" => 255, "minLength" => 1},
      "voyager_id" => {"type" => "string", "maxLength" => 255, "minLength" => 1},
      "exported_to_voyager" => {"type" => "boolean", "default" => false},
      "restricted" => {"type" => "boolean", "default" => false},

      "container_locations" => {
        "type" => "array",
        "items" => {
          "type" => "JSONModel(:container_location) object",
        }
      },

      "container_profile" => {
        "type" => "object",
        "subtype" => "ref",
        "properties" => {
          "ref" => {"type" => "JSONModel(:container_profile) uri"},
          "_resolved" => {
            "type" => "object",
            "readonly" => "true"
          }
        }
      }
    }
  }
}