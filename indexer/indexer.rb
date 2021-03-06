class CommonIndexer

  @@record_types << :top_container
  @@resolved_attributes << 'container_profile'
  @@resolved_attributes << 'container_locations'

  add_indexer_initialize_hook do |indexer|

    indexer.add_document_prepare_hook {|doc, record|
      if record['record']['jsonmodel_type'] == 'top_container'
        doc['title'] = record['record']['long_display_string']
        doc['display_string'] = record['record']['display_string']

        if record['record']['series']
          doc['series_uri_u_sstr'] = record['record']['series'].map {|series| series['ref']}
          doc['series_title_u_sstr'] = record['record']['series'].map {|series| series['display_string']}
          doc['series_level_u_sstr'] = record['record']['series'].map {|series| series['level_display_string']}
          doc['series_identifier_stored_u_sstr'] = record['record']['series'].map {|series| series['identifier']}
          doc['series_identifier_u_stext'] = record['record']['series'].map {|series|
            CommonIndexer.generate_permutations_for_identifier(series['identifier'])
          }.flatten
        end

        if record['record']['collection']
          doc['collection_uri_u_sstr'] = record['record']['collection'].map {|collection| collection['ref']}
          doc['collection_display_string_u_sstr'] = record['record']['collection'].map {|collection| collection['display_string']}
          doc['collection_identifier_stored_u_sstr'] = record['record']['collection'].map {|collection| collection['identifier']}
          doc['collection_identifier_u_stext'] = record['record']['collection'].map {|collection|
            CommonIndexer.generate_permutations_for_identifier(collection['identifier'])
          }.flatten
        end

        if record['record']['container_profile']
          doc['container_profile_uri_u_sstr'] = record['record']['container_profile']['ref']
          doc['container_profile_display_string_u_sstr'] = record['record']['container_profile']['_resolved']['display_string']
        end

        if record['record']['container_locations'].length > 0
          record['record']['container_locations'].each do |container_location|
            if container_location['status'] == 'current'
              doc['location_uri_u_sstr'] = container_location['ref']
              doc['location_uris'] = container_location['ref']
              doc['location_display_string_u_sstr'] = container_location['_resolved']['title']
            end
          end
        end
        doc['exported_u_sbool'] = record['record'].has_key?('exported_to_ils')
        doc['empty_u_sbool'] = record['record']['collection'].empty?

        doc['typeahead_sort_key_u_sort'] = record['record']['indicator'].to_s.rjust(255, '#')
      end
    }


    indexer.add_document_prepare_hook {|doc, record|
      if ['resource', 'archival_object', 'accession'].include?(doc['primary_type'])
        # we no longer want the contents of containers to be indexed at the container's location
        doc.delete('location_uris')

        # index the top_container's linked via a sub_container
        ASUtils.wrap(record['record']['instances']).each{|instance|
          if instance['sub_container'] && instance['sub_container']['top_container']
            doc['top_container_uri_u_sstr'] = instance['sub_container']['top_container']['ref']
          end
        }
      end
    }
  end

  @@record_types << :container_profile

  self.add_indexer_initialize_hook do |indexer|
    indexer.add_document_prepare_hook {|doc, record|
      if doc['primary_type'] == 'container_profile'
        doc['json'] = record['record'].to_json
        doc['title'] = record['record']['display_string']
        doc['display_string'] = record['record']['display_string']

        ['width', 'height', 'depth'].each do |property|
          doc["container_profile_#{property}_u_sstr"] = record['record'][property]
        end

        doc["container_profile_dimension_units_u_sstr"] = record['record']['dimension_units']

        doc['typeahead_sort_key_u_sort'] = record['record']['display_string']
      end
    }
  end


  def self.generate_permutations_for_identifier(identifer)
    return [] if identifer.nil?

    [
      identifer,
      identifer.gsub(/[[:punct:]]+/, " "),
      identifer.gsub(/[[:punct:] ]+/, ""),
      identifer.scan(/([0-9]+|[^0-9]+)/).flatten(1).join(" ")
    ].uniq
  end

end
