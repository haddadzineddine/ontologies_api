
require 'ncbo_resource_index_client'

class ResourceIndexController < ApplicationController

  # Note: methods from resource_index_helper.rb :
  #  -  get_options(params)
  #  -  get_ontology_virtual_id(ontology_acronym)

  namespace "/resource_index" do

    get '/search' do
      options = get_options(params)
      classes = get_classes(params)
      if classes.empty?
        # TODO: reply with syntax error message?
      else
        options[:elementDetails] = true
        result = NCBO::ResourceIndex.find_by_concept(classes, options)
        reply massage_search(result, options)
      end
    end

    get '/ranked_elements' do
      options = get_options(params)
      classes = get_classes(params)
      if classes.empty?
        # TODO: reply with syntax error message?
      else
        result = NCBO::ResourceIndex.ranked_elements(classes, options)
        result.resources.each do |r|
          r[:elements] = massage_elements(r[:elements])
        end
        reply result
      end
    end

    # Return all resources
    get "/resources" do
      options = get_options(params)
      result = NCBO::ResourceIndex.resources(options)
      reply massage_resources(result)
    end

    # Return specific resources
    get "/resources/:resources" do
      options = get_options(params)
      result = NCBO::ResourceIndex.resources(options)
      reply massage_resources(result)
    end

    # Return specific elements from specific resources
    get "/resources/:resources/elements/:elements" do
      options = get_options(params)
      result = NCBO::ResourceIndex.resources(options)
      # TODO: Use the element method instead (Paul is fixing bug)
      #result = NCBO::ResourceIndex.element(params["element_id"], params["resource_id"], options)
      #binding.pry
      reply massage_resources(result)
    end

    #
    # TODO: enable POST methods?
    #

    def massage_search(old_response, options)
      resources = {}
      old_response.each do |resource|
        elements = {}
        annotations = []
        resource.annotations.each do |a|
          annotated_class = get_annotated_class_from_concept(a.concept)
          # NOTE: Skipping nil class_uri values, could mess with paging details
          # The nil values are marginal cases for OBO terms
          next if annotated_class.nil?
          # NOTE: options[:scored] is not related to element weights.
          element = massage_element(a.element, options[:elementDetails])
          el_id = element["id"]
          elements[el_id] = element["fields"] unless elements.include?(el_id)
          annotations.push massage_search_annotation(a, annotated_class)
        end
        # TODO: add search option to exclude 0-element resources?
        resources[resource.resource] = {
            "annotations" => annotations,
            "annotatedElements" => elements
        }
      end
      return resources
    end

    # @param concept [{:localConceptId => 'version_id/term_id'}]
    # @return nil or annotated_class = { :id => 'term_uri', :ontology => 'ontology_uri'}
    def get_annotated_class_from_concept(concept)
      version_id, short_id = concept[:localConceptId].split('/')
      class_uri = uri_from_short_id(version_id, short_id)
      return nil if class_uri.nil?
      # undo the comment for testing purposes, only when class_uri.nil?
      #class_uri = concept[:localConceptId] if class_uri.nil?
      ontology_acronym = acronym_from_version_id(version_id)
      return nil if ontology_acronym.nil?
      ontology_uri = ontology_uri_from_acronym(ontology_acronym)
      return nil if ontology_uri.nil?
      annotated_class = {
          :id => class_uri,
          :ontology => ontology_uri
      }
      return annotated_class
    end

    def massage_search_annotation(a, annotated_class)
      # annotations is a hash of annotation hashes,
      # this method will modify it directly (by reference).
      annotationTypeMap = {
          "mgrepContext" => "direct",
          "mappingContext" => "mapping",
          "isaContext" => "hierarchy"
      }
      annotation = {
          :annotatedClass => annotated_class,
          :annotationType => annotationTypeMap[ a.context[:contextType] ],
          :elementField => a.context[:contextName],
          :elementId => a.element[:localElementId],
          :from => a.context[:from],
          :to => a.context[:to],
          #:score => a.score
      }
      return annotation
    end

    def massage_elements(element_array)
      # TODO: change this to use map! instead of each loop?
      elements = []
      element_array.each { |e| elements.push massage_element(e) }
      return elements
    end

    def massage_element(e, with_fields=true)
      element = { "id" => e[:localElementId] }
      if with_fields
        fields = {}
        e[:text].each do |name, description|
          # TODO: Parse the text field to translate the term IDs into a list of URIs?
          #"text"=> "1351/D020224> 1351/D019295> 1351/D008969> 1351/D001483> 1351/D017398> 1351/D000465> 1351/D005796> 1351/D008433> 1351/D009690> 1351/D005091",
          #
          # Parse the associated ontologies to return a list of ontology URIs
          ontIDs = [e[:ontoIds][name]].compact  # Wrap Fixnum or Array into Array
          ontIDs.delete_if {|x| x == 0 }
          ontIDs.each_with_index do |id, i|     # Try to convert to ontology URIs
            uri = ontology_uri_from_virtual_id(id)
            if uri.nil?
              ontIDs[i] = id.to_s # conform to expected data type for JSON validation
            else
              ontIDs[i] = uri
            end
          end

          weight = 0.0
          e[:weights].each {|hsh| weight = hsh[:weight] if hsh[:name] == name}
          fields[name] = {
            "text" => description,
            "associatedOntologies" => ontIDs,
            "weight" => weight
          }
        end
        element["fields"] = fields
      end
      return element
    end

    def massage_resources(resource_array)
      # Remove resource content
      resource_array.each do |r|
        r.delete :workflowCompletedDate
        r.delete :contexts
      end
      return resource_array
    end

  end # namespace "/resource_index"

end # class ResourceIndexController
