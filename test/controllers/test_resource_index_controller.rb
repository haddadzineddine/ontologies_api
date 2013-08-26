require_relative '../test_case'

class TestResourceIndexController < TestCase

  DEBUG_MESSAGES = true

  # 1104 is BRO
  # 1104, BRO:Algorithm, http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Algorithm
  # 1104, BRO:Graph_Algorithm, http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Graph_Algorithm
  ONT_ID_SHORT = 'BRO'
  CLASS_ID_SHORT = 'BRO:Graph_Algorithm'
  ONT_ID_FULL = CGI::escape('http://data.bioontology.org/ontologies/BRO')
  CLASS_ID_FULL = CGI::escape('http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Graph_Algorithm')

  ONT_ID_SHORT_MISSING = 'MISSING_ONTOLOGY'
  CLASS_ID_SHORT_MISSING = 'BRO:MissingClass'
  ONT_ID_FULL_MISSING = CGI::escape('http://data.bioontology.org/ontologies/MISSING_ONTOLOGY')
  CLASS_ID_FULL_MISSING = CGI::escape('http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#MissingClass')

  RESOURCE_ID = 'AE'
  ELEMENT_ID = 'E-GEOD-19229'
  #resource_id = 'PM'  # PubMed
  #element_id = '10866208'

  def self._user( action, username = 'resource_index_user' )
    if action == 'create'
      test_user = User.new( username: username, email: "#{username}@example.org", password: 'password')
      test_user.save if test_user.valid?
      @@user = test_user.valid? ? test_user : User.find(username).first
    else
      @@user = nil
      user = User.find(username).first
      user.delete unless user.nil?
    end
  end

  # Populate the ontology dB
  def self.before_suite
    test_ontology_acronyms = ["BRO"]
    acronyms = []
    LinkedData::Models::Ontology.all {|o| acronyms << o.acronym}
    @@created_acronyms = []
    begin
      _user('create')
      test_ontology_acronyms.each do |acronym|
        next if acronyms.include?(acronym)
        ontology_data = {
            acronym: acronym,
            name: "#{acronym} ontology",
            administeredBy: [@@user]
        }
        ontology = LinkedData::Models::Ontology.new(ontology_data)
        ontology.save
        @@created_acronyms << acronym
        # Create a dummy ontology submission.
        ont_data = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 1, submission_count: 1)
        ont_new = ont_data[2][0]
        ont_new.bring(:submissions)
        submission = ont_new.submissions.last  # get the last submission, regardless of parsing status
        submission.bring_remaining
        submission.set_ready
        submission.uploadFilePath = "test/data/uploaded_ontologies/BROTEST-0/1/BRO_v3.2.owl"
        submission.ontology = ontology
        submission.save
      end
    rescue Exception => e
      puts "Failure to create ontology or user in before_suite: delete and recreate triple store.\n"
      raise e
    end
  end

  def self.after_suite
    begin
      LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
      _user('delete')
      @@created_acronyms.each do |acronym|
        ontology = LinkedData::Models::Ontology.find(acronym).first
        ontology.delete unless ontology.nil?
      end
    rescue Exception => e
      puts "Failure to delete ontology or user in after_suite\n"
      raise e
    end
  end


  # JSON Schema
  # json-schema for description and validation of REST json responses.
  # http://tools.ietf.org/id/draft-zyp-json-schema-03.html
  # http://tools.ietf.org/html/draft-zyp-json-schema-03

  PAGE_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "page",
    "description": "A Resource Index page of results.",
    "additionalProperties": false,
    "properties": {
      "page": { "type": "number", "required": true },
      "pageCount": { "type": "number", "required": true },
      "prevPage": { "type": ["number","null"], "required": true },
      "nextPage": { "type": ["number","null"], "required": true },
      "links": { "type": "object", "required": true },
      "collection": { "type": "array", "required": true }
    }
  }
  END_SCHEMA

  ONTOLOGIES_SCHEMA = <<-END_SCHEMA
  {
    "type": "array",
    "title": "ontologies",
    "description": "An array of Resource Index ontologies.",
    "items": { "type": "object" }
  }
  END_SCHEMA

  ONTOLOGY_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "ontology",
    "description": "A Resource Index ontology.",
    "additionalProperties": false,
    "properties": {
      "administeredBy": { "type": "array" },
      "acronym": { "type": "string", "required": true },
      "name": { "type": "string", "required": true },
      "@id": { "type": "string", "format": "uri", "required": true },
      "@type": { "type": "string", "format": "uri", "required": true },
      "links": { "type": "object", "required": true },
      "@context": { "type": "object", "required": true }
    }
  }
  END_SCHEMA

  SEARCH_RESOURCES_SCHEMA = <<-END_SCHEMA
  {
    "type": "array",
    "title": "resources",
    "description": "An array of Resource Index resource objects.",
    "items": { "type": "object" }
  }
  END_SCHEMA

  SEARCH_RESOURCE_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "search resource",
    "description": "A Resource Index resource.",
    "additionalProperties": false,
    "properties": {
      "id": { "type": "string", "required": true },
      "annotations": { "type": "array", "required": true },
      "annotatedElements": { "type": "object", "required": true }
    }
  }
  END_SCHEMA

  ANNOTATIONS_SCHEMA = <<-END_SCHEMA
  {
    "type": "array",
    "title": "annotations",
    "description": "An array of Resource Index annotation objects.",
    "items": { "type": "object" }
  }
  END_SCHEMA

  ANNOTATION_SCHEMA = <<-END_SCHEMA
  {
      "type": "object",
      "title": "annotation",
      "description": "A Resource Index annotation.",
      "additionalProperties": false,
      "properties": {
          "annotatedClass": { "type": "object", "required": true },
          "annotationType": { "type": "string", "required": true },
          "elementField": { "type": "string", "required": true },
          "elementId": { "type": "string", "required": true },
          "from": { "type": "number", "required": true },
          "to": { "type": "number", "required": true }
      }
  }
  END_SCHEMA

  RANKED_ELEMENTS_SCHEMA = <<-END_SCHEMA
  {
    "type": "array",
    "title": "ranked elements",
    "description": "An array of Resource Index ranked element objects.",
    "items": { "type": "object" }
  }
  END_SCHEMA

  RANKED_ELEMENT_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "ranked element",
    "description": "A Resource Index ranked element.",
    "additionalProperties": false,
    "properties": {
      "resourceId": { "type": "string", "required": true },
      "offset": { "type": "number", "required": true },
      "limit": { "type": "number", "required": true },
      "totalResults": { "type": "number", "required": true },
      "elements": { "type": "array", "required": true }
    }
  }
  END_SCHEMA

  RESOURCES_SCHEMA = <<-END_SCHEMA
  {
    "type": "array",
    "title": "resources",
    "description": "An array of Resource Index resource objects.",
    "items": { "type": "object" }
  }
  END_SCHEMA

  RESOURCE_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "resource",
    "description": "A Resource Index resource.",
    "additionalProperties": false,
    "properties": {
      "resourceName": { "type": "string", "required": true },
      "resourceId": { "type": "string", "required": true },
      "mainContext": { "type": "string", "required": true },
      "resourceURL": { "type": "string", "format": "uri", "required": true },
      "resourceElementURL": { "type": "string", "format": "uri" },
      "resourceDescription": { "type": "string" },
      "resourceLogo": { "type": "string", "format": "uri" },
      "lastUpdateDate": { "type": "string", "format": "datetime" },
      "totalElements": { "type": "number" }
    }
  }
  END_SCHEMA

  ELEMENTS_ANNOTATED_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "elements",
    "description": "A hash of Resource Index element objects."
  }
  END_SCHEMA

  ELEMENT_ANNOTATED_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "element",
    "description": "A Resource Index element."
  }
  END_SCHEMA

  ELEMENTS_SCHEMA = <<-END_SCHEMA
  {
    "type": "array",
    "title": "elements",
    "description": "An array of Resource Index element objects."
  }
  END_SCHEMA

  ELEMENT_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "element",
    "description": "A Resource Index element.",
    "additionalProperties": false,
    "properties": {
      "id": { "type": "string", "required": true },
      "fields": { "type": "object" }
    }
  }
  END_SCHEMA

  ELEMENT_FIELD_SCHEMA = <<-END_SCHEMA
  {
    "type": "object",
    "title": "element_field",
    "description": "A Resource Index element field.",
    "additionalProperties": false,
    "properties": {
      "associatedClasses": { "type": "array", "items": { "type": "string", "format": "uri" }, "required": true },
      "associatedOntologies": { "type": "array", "items": { "type": "string", "format": "uri" }, "required": true },
      "text": { "type": "string", "required": true },
      "weight": { "type": "number", "required": true }
    }
  }
  END_SCHEMA

  def test_get_search_classes
    #get "/resource_index/search?{classes}"  # such that {classes} is of the form:
    #classes[acronym1|URI1][classid1,..,classidN]&classes[acronym2|URI2][classid1,..,classidN]
    #
    rest_search = "/resource_index/search"
    rest_param_list = [
        "?classes[#{ONT_ID_SHORT}]=#{CLASS_ID_SHORT}",
        "?classes[#{ONT_ID_FULL}]=#{CLASS_ID_FULL}",
        "?classes[#{ONT_ID_SHORT}]=#{CLASS_ID_FULL}",
        "?classes[#{ONT_ID_FULL}]=#{CLASS_ID_SHORT}"
    ]
    rest_param_list.each do |param|
      rest_target = rest_search + param
      last_response = _get_response(rest_target)
      validate_json(last_response.body, PAGE_SCHEMA)
      page = MultiJson.load(last_response.body)
      annotations = page["collection"]
      assert_instance_of(Array, annotations)
      validate_json(MultiJson.dump(annotations), SEARCH_RESOURCE_SCHEMA, true)
      annotations.each do |a|
        validate_json(MultiJson.dump(a["annotations"]), ANNOTATION_SCHEMA, true)
        validate_annotated_elements(a["annotatedElements"])
      end
    end
  end


  def test_get_search_classes_failures
    #get "/resource_index/search?{classes}"  # such that {classes} is of the form:
    #classes[acronym1|URI1][classid1,..,classidN]&classes[acronym2|URI2][classid1,..,classidN]
    # 404 should be thrown for any 'missing' ontology or an ontology without a latest_submission.
    # TODO: Enable the missing class tests when the API can quickly determine whether classes exist or not.
    # TODO NOTE: The 404 errors are thrown by the resource_index_helper::get_classes method.
    rest_search = "/resource_index/search"
    rest_param_list = [
        "?classes[#{ONT_ID_SHORT_MISSING}]=#{CLASS_ID_SHORT}",
        "?classes[#{ONT_ID_FULL_MISSING}]=#{CLASS_ID_FULL}",
        "?classes[#{ONT_ID_SHORT_MISSING}]=#{CLASS_ID_SHORT_MISSING}",  # The missing class is irrelevant
        "?classes[#{ONT_ID_FULL_MISSING}]=#{CLASS_ID_FULL_MISSING}",    # The missing class is irrelevant
        #"?classes[#{ONT_ID_SHORT}]=#{CLASS_ID_SHORT_MISSING}",
        #"?classes[#{ONT_ID_FULL}]=#{CLASS_ID_FULL_MISSING}",
    ]
    rest_param_list.each do |param|
      rest_target = rest_search + param
      last_response = _get_response(rest_target, 404)
    end
  end


  def test_get_ontologies
    rest_target = '/resource_index/ontologies'
    last_response = _get_response(rest_target)
    # Note: ontologies is no longer a paged response
    #validate_json(last_response.body, PAGE_SCHEMA)
    #ontology_pages = MultiJson.load(last_response.body)
    #assert_instance_of(Hash, ontology_pages)
    #ontology_list = ontology_pages['collection']
    ontology_list = MultiJson.load(last_response.body)
    assert_instance_of(Array, ontology_list)
    ontology_json = MultiJson.dump(ontology_list)
    validate_json(ontology_json, ONTOLOGIES_SCHEMA)
    validate_json(ontology_json, ONTOLOGY_SCHEMA, true)
    # Note: there is no validation for the links or @context content.
  end

  def test_get_resources
    rest_target = '/resource_index/resources'
    last_response = _get_response(rest_target)
    # Note: resources is no longer a paged response
    #validate_json(last_response.body, PAGE_SCHEMA)
    #resources_pages = MultiJson.load(last_response.body)
    #assert_instance_of(Hash, resources_pages)
    #resources_list = resources_pages['collection']
    resources_list = MultiJson.load(last_response.body)
    assert_instance_of(Array, resources_list)
    resources_json = MultiJson.dump(resources_list)
    validate_json(resources_json, RESOURCES_SCHEMA)
    validate_json(resources_json, RESOURCE_SCHEMA, true)
  end

  def test_get_ranked_elements
    #get "/resource_index/ranked_elements?{classes}"  # such that {classes} is of the form:
    #classes[acronym1|URI1][classid1,..,classidN]&classes[acronym2|URI2][classid1,..,classidN]
    #
    #rest_target = "/resource_index/ranked_elements?classes[#{acronym}]=#{classid1},#{classid2}"
    rest_target = "/resource_index/ranked_elements?classes[#{ONT_ID_SHORT}]=#{CLASS_ID_SHORT}"
    last_response = _get_response(rest_target)
    validate_json(last_response.body, PAGE_SCHEMA)
    page = MultiJson.load(last_response.body)
    resources = page["collection"]
    refute_empty(resources, "ERROR: empty resources for ranked elements")
    validate_json(MultiJson.dump(resources), RANKED_ELEMENT_SCHEMA, true)
    resources.each { |r| validate_ranked_elements(r['elements']) if not r['elements'].empty? }
  end

  def test_get_resource_element
    rest_target = "/resource_index/resources/#{RESOURCE_ID}/elements/#{ELEMENT_ID}"
    last_response = _get_response(rest_target)
    element = MultiJson.load(last_response.body)
    validate_element(element)
  end

  def test_get_resource_element_annotations
    #resource_id = 'PM'  # PubMed
    #element_id = '10866208'
    element_id = "NCT00357513"
    resource_id = "CT"
    classes = "classes[BRO]=BRO:Graph_Algorithm"
    rest_target = "/resource_index/element_annotations?elements=#{element_id}&resources=#{resource_id}&#{classes}"
    last_response = _get_response(rest_target)
    validate_json(last_response.body, ANNOTATION_SCHEMA, true)
  end

private


  def _get_response(rest_target, expected_status=200)
    puts rest_target if DEBUG_MESSAGES
    get rest_target
    _response_status(expected_status, last_response)
    return last_response
  end

  def _response_status(status, response)
    if DEBUG_MESSAGES
      assert_equal(status, response.status, response.body)
    else
      assert_equal(status, response.status)
    end
  end

  def validate_annotated_elements(elements)
    validate_json(MultiJson.dump(elements), ELEMENTS_ANNOTATED_SCHEMA)
    elements.each_value do |e|
      validate_json(MultiJson.dump(e), ELEMENT_ANNOTATED_SCHEMA)
      e.each_value do |field|
        validate_json(MultiJson.dump(field), ELEMENT_FIELD_SCHEMA)
      end
    end
  end

  def validate_ranked_elements(elements)
    validate_json(MultiJson.dump(elements), ELEMENT_SCHEMA, true)
    elements.each {|e| validate_element(e) }
  end

  def validate_element(element)
    validate_json(MultiJson.dump(element), ELEMENT_SCHEMA)
    # fields are optional
    if element.include? 'fields'
      element["fields"].each_value do |field|
        validate_json(MultiJson.dump(field), ELEMENT_FIELD_SCHEMA)
      end
    end
  end

end

