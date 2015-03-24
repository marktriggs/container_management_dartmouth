class AspaceJsonToYaleContainerMapper

  include JSONModel

  def initialize(json, new_record)
    @json = json
    @new_record = new_record
    @new_top_containers = []
  end


  def call
    @json['instances'].each do |instance|

      if instance['sub_container'] || instance['digital_object']
        # Just need to make sure there are no conflicting ArchivesSpace containers
        instance.delete('container')
        next
      end

      top_container = get_or_create_top_container(instance)

      ensure_harmonious_values(top_container, instance['container'])

      subcontainer = {
        'top_container' => {'ref' => top_container.uri},
      }

      [2, 3].each do |level|
        # ArchivesSpace containers allow type_2/3 to be set without
        # indicator_2/3.  Provide a default if it's missing.
        if instance['container']["type_#{level}"]
          subcontainer["type_#{level}"] = instance['container']["type_#{level}"]
          subcontainer["indicator_#{level}"] = instance['container']["indicator_#{level}"] || get_default_indicator
        end
      end

      if instance['container']["type_3"] && !instance['container']["type_2"]
        # Promote type_3 to type_2 to stop validation blowing up
        subcontainer["type_2"] = instance['container']["type_3"]
        subcontainer["indicator_2"] = instance['container']["indicator_3"] || get_default_indicator

        subcontainer["type_3"] = nil
        subcontainer["indicator_3"] = nil
      end


      instance['sub_container'] = subcontainer

      # No need for the original value now.
      instance.delete('container')
    end
  end


  protected

  def try_matching_barcode(container)
    # If we have a barcode, attempt to locate an existing top container but create one if needed
    barcode = container['barcode_1']

    if barcode
      if (top_container = TopContainer.for_barcode(barcode))
        top_container
      else
        indicator = container['indicator_1'] || get_default_indicator
        TopContainer.create_from_json(JSONModel(:top_container).from_hash('barcode' => barcode,
                                                                          'indicator' => indicator,
                                                                          'container_locations' => container['container_locations']
                                                                         ))
      end
    else
      nil
    end
  end


  def series_for_current_record
    ao = if new_record? && @json['parent']
           ArchivalObject[JSONModel(:archival_object).id_for(@json['parent']['ref'])]
         elsif !new_record?
           ArchivalObject[JSONModel(:archival_object).id_for(@json['uri'])]
         else
           nil
         end

    if ao
      topmost = ao.topmost_archival_object

      if topmost.has_series_specific_fields?
        topmost
      else
        nil
      end
    end
  end

  def try_matching_indicator_within_series(series, container)
    indicator = container['indicator_1']

    find_top_container_within_subtree(series, indicator)
  end


  def try_matching_indicator_outside_of_series(container)
    indicator = container['indicator_1']

    return nil if !@json['resource']

    resource_id = JSONModel(:resource).id_for(@json['resource']['ref'])

    db = Instance.db

    # Sorry about this.  The general idea is that we join all the way from
    # Archival Object through to the Top Containers they link to.  Then we limit
    # to the Archival Objects within the current resource, and the top
    # containers that have the indicator we're looking for.
    #
    # That gives us a (hopefully short) list of possible top containers to link
    # to.  Then we do one final sweep to find one that isn't part of a series.
    #
    candidate_top_containers = db[:archival_object].
                               join(:instance, :archival_object_id => :archival_object__id).
                               join(:sub_container, :instance_id => :instance__id).
                               join(:top_container_link_rlshp, :sub_container_id => :sub_container__id).
                               join(:top_container, :id => :top_container_link_rlshp__top_container_id).
                               filter(:archival_object__root_record_id => resource_id).
                               filter(:top_container__indicator => indicator).
                               select(Sequel.as(:top_container__id, :top_container_id),
                                      Sequel.as(:archival_object__id, :archival_object_id))

    candidate_top_containers.each do |row|
      ao = ArchivalObject[row[:archival_object_id]]

      if !ao.series
        # Not in a series.  That's a match!
        return TopContainer[row[:top_container_id]]
      end
    end

    return nil
  end


  def try_matching_indicator_within_collection(container)
    indicator = container['indicator_1']

    top_record = if @json.is_a?(JSONModel(:archival_object)) && @json['resource']
                   Resource[JSONModel(:resource).id_for(@json['resource']['ref'])]
                 elsif @json.is_a?(JSONModel(:resource)) && @json['uri']
                   Resource[JSONModel(:resource).id_for(@json['uri'])]
                 else
                   nil
                 end

    if top_record
      resource_id = top_record.id
      find_top_container_by_instances(Instance.filter(:archival_object_id => ArchivalObject.filter(:root_record_id => resource_id).select(:id)).select(:id),
                                      indicator)
    else
      nil
    end

  end


  def try_matching_indicator_within_record(container)
    indicator = container['indicator_1']

    # Record is being created so nothing to search for yet.
    return nil if !@json['uri']

    model = if @json.is_a?(JSONModel(:archival_object))
               ArchivalObject
             elsif @json.is_a?(JSONModel(:resource))
               Resource
             elsif @json.is_a?(JSONModel(:accession))
               Accession
             else
               nil
             end

    return nil if !model

    id = @json.class.id_for(@json['uri'])
    record = model[id]

    if record
      join_column = model.association_reflection(:instance)[:key]
      find_top_container_by_instances(Instance.filter(join_column => top_record.id).select(:id), indicator)
    else
      nil
    end

  end


  def ensure_harmonious_values(top_container, aspace_container)
    properties = {:indicator => 'indicator_1', :barcode => 'barcode_1'}

    properties.each do |top_container_property, aspace_property|
      if aspace_container[aspace_property] && top_container[top_container_property] != aspace_container[aspace_property]

        raise ValidationException.new(:errors => {aspace_property => ["Mismatch when mapping between #{top_container_property} and #{aspace_property}"]},
                                      :object_context => {
                                        :top_container => top_container,
                                        :aspace_container => aspace_container
                                      })
      end
    end


    aspace_locations = Array(aspace_container['container_locations']).map {|container_location| container_location['ref']}
    top_container_locations = top_container.related_records(:top_container_housed_at).map(&:uri)

    if aspace_locations.empty? || ((top_container_locations - aspace_locations).empty? && (aspace_locations - top_container_locations).empty?)
    # All OK!
    elsif top_container_locations.empty?
      # We'll just take the incoming location if we don't have any better ideas
      top_container.refresh
      json = TopContainer.to_jsonmodel(top_container, :skip_restrictions => true)
      json['container_locations'] = aspace_container['container_locations']
      top_container.update_from_json(json)
      top_container.refresh
    else
      raise ValidationException.new(:errors => {'container_locations' => ["Locations in ArchivesSpace container don't match locations in existing top container"]},
                                    :object_context => {
                                      :top_container => top_container,
                                      :aspace_container => aspace_container,
                                      :top_container_locations => top_container_locations,
                                      :aspace_locations => aspace_locations,
                                    })
    end

  end



  private


  def new_record?
    @new_record
  end


  def get_or_create_top_container(instance)
    container = instance['container']

    if container['barcode_1'] && container['barcode_1'].strip == ""
      # Seriously?  Yeesh.  Bad barcode!  No biscuit!
      container['barcode_1'] = nil
    end

    if (result = try_matching_barcode(container))
      return result
    else
      indicator = container['indicator_1']

      match = try_matching_indicator(container, indicator)

      if match
        return match
      end
    end

    Log.info("Creating a new Top Container for a container with no barcode")

    created = TopContainer.create_from_json(JSONModel(:top_container).from_hash('indicator' => (container['indicator_1'] || get_default_indicator),
                                                                                'container_locations' => container['container_locations'],
                                                                               ))
    @new_top_containers << created
    created
  end


  def try_matching_indicator(container, indicator)
    return nil if !indicator

    # If we've created a matching top container for this record already, use that.
    @new_top_containers.each do |top_container|
      if top_container.indicator == indicator
        return top_container
      end
    end

    if @json.is_a?(JSONModel(:accession)) || @json.is_a?(JSONModel(:resource))
      return try_matching_indicator_within_record(container)
    else
      series = series_for_current_record

      if series
        return try_matching_indicator_within_series(series, container)
      else
        return try_matching_indicator_outside_of_series(container)
      end
    end
  end


  def get_default_indicator
    "system_indicator_#{SecureRandom.hex}"
  end


  def find_top_container_within_subtree(top_record, indicator)
    ao_ids = [top_record.id]

    # Find the IDs of all records under this point
    new_ao_ids = [top_record.id]

    while true
      new_ao_ids = ArchivalObject.filter(:parent_id => new_ao_ids).select(:id).map(&:id)

      if new_ao_ids.empty?
        break
      else
        ao_ids += new_ao_ids
      end
    end


    # Find all linked instances
    instance_ds = Instance.filter(:archival_object_id => ao_ids).select(:id)

    find_top_container_by_instances(instance_ds, indicator)
  end


  def find_top_container_by_instances(instance_ds, indicator)
    # All subcontainers linked to our instances
    subcontainer_ds = SubContainer.filter(:instance_id => instance_ds)

    relationship_model = SubContainer.find_relationship(:top_container_link)
    top_containers_for_subcontainers = relationship_model.filter(:sub_container_id => subcontainer_ds.select(:id)).select(:top_container_id)

    TopContainer[:indicator => indicator,
                 :id => top_containers_for_subcontainers]
  end

end
