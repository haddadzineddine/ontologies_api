class InstancesController < ApplicationController

  # Display individuals for a class
  get '/ontologies/:ontology/classes/:cls/instances' do

    ont, sub = get_ontology_and_submission
    check_last_modified_segment(LinkedData::Models::Instance, [ont.acronym])
    cls = get_class(sub)
    error 404 if cls.nil?
    page, size = page_params

    unmapped =  (includes_param && includes_param.include?(:all))
    page_data = LinkedData::Models::Instance.where(cls.id.nil? ? nil :{types: RDF::URI.new(cls.id.to_s)}).in(sub)
                                            .include(LinkedData::Models::Instance.attributes).page(page,size).all

    if unmapped && page_data.length > 0
      LinkedData::Models::Instance.in(sub).models(page_data).include(:unmapped).all
    end
    reply page_data
  end

  namespace "/ontologies/:ontology/instances" do
    # Display individuals for an ontology
    get do
      ont, sub = get_ontology_and_submission
      check_last_modified_segment(LinkedData::Models::Instance, [ont.acronym])
      page, size = page_params

      unmapped = (includes_param && includes_param.include?(:all))
      page_data = LinkedData::Models::Instance.in(sub)
                                              .include(LinkedData::Models::Instance.attributes)
                                              .page(page,size).all

      if unmapped && page_data.length > 0
        LinkedData::Models::Instance.in(sub).models(page_data).include(:unmapped).all
      end
      reply page_data
    end

  end
end


