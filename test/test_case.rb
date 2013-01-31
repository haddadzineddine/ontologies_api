# Start simplecov if this is a coverage task
if ENV["COVERAGE"].eql?("true")
  require 'simplecov'
  SimpleCov.start do
    add_filter "/test/"
    add_filter "app.rb"
    add_filter "init.rb"
    add_filter "/config/"
  end
end

require_relative '../app'
require 'test/unit'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

# All tests should inherit from this class.
# Use 'rake test' from the command line to run tests.
# See http://www.sinatrarb.com/testing.html for testing information
class TestCase < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
    set :raise_errors, true
    set :dump_errors, false
    set :show_exceptions, false
  end

  def teardown
    delete_ontologies_and_submissions
  end

  ##
  # Creates a set of Ontology and OntologySubmission objects and stores them in the triplestore
  # @param [Hash] options the options to create ontologies with
  # @option options [Fixnum] :ont_count Number of ontologies to create
  # @option options [Fixnum] :submission_count How many submissions each ontology should have (acts as max number when random submission count is used)
  # @option options [TrueClass, FalseClass] :random_submission_count Use a random number of submissions between 1 and :submission_count
  def create_ontologies_and_submissions(options = {})
    LinkedData::Models::SubmissionStatus.init
    delete_ontologies_and_submissions
    ont_count = options[:ont_count] || 5
    submission_count = options[:submission_count] || 5
    random_submission_count = options[:random_submission_count].nil? ? true : options[:random_submission_count]

    u = LinkedData::Models::User.new(username: "tim", email: "tim@example.org")
    u.save unless u.exist? || !u.valid?

    of = LinkedData::Models::OntologyFormat.new(acronym: "OWL")
    of.save unless of.exist? || !of.valid?

    ont_acronyms = []
    ontologies = []
    ont_count.to_i.times do |count|
      acronym = "TST-ONT-#{count}"
      ont_acronyms << acronym

      o = LinkedData::Models::Ontology.new({
        acronym: acronym,
        name: "Test Ontology ##{count}",
        administeredBy: u
      })

      if o.valid?
        o.save
        ontologies << o
      end

      # Random submissions (between 1 and max)
      max = random_submission_count ? (1..submission_count.to_i).to_a.shuffle.first : submission_count
      max.times do
        os = LinkedData::Models::OntologySubmission.new({
          ontology: o,
          hasOntologyLanguage: of,
          submissionStatus: LinkedData::Models::SubmissionStatus.new(:code => "UPLOADED"),
          submissionId: o.next_submission_id,
          definitionProperty: (RDF::IRI.new "http://bioontology.org/ontologies/biositemap.owl#definition")
        })
        if (options.include? :process_submission)
          file_path = nil
          if os.submissionId < 3
            file_path = "test/data/ontology_files/BRO_v3.#{os.submissionId}.owl"
          else
            raise ArgumentError, "create_ontologies_and_submissions does not support process submission with more than 2 versions"
          end
          uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(o.acronym, os.submissionId, file_path)
          os.uploadFilePath = uploadFilePath
        else
          os.pullLocation = RDF::IRI.new("http://example.com")
        end
        os.save if os.valid?
      end
    end

    # Get ontology objects if empty
    if ontologies.empty?
      ont_acronyms.each do |ont_id|
        ontologies << LinkedData::Models::Ontology.find(ont_id)
      end
    end

    if options.include? :process_submission
      ontologies.each do |o|
        o.load unless o.loaded?
        o.submissions.each do |ss|
          ss.load unless ss.loaded?
          ss.ontology.load unless ss.ontology.loaded?
          ss.process_submission Logger.new(STDOUT)
        end
      end
    end

    return ont_count, ont_acronyms, ontologies
  end

  ##
  # Delete all ontologies and their submissions. This will look for all ontologies starting with TST-ONT- and ending in a Fixnum
  def delete_ontologies_and_submissions
    LinkedData::Models::Ontology.all.each do |ont|
      ont.load unless ont.nil? || ont.loaded
      subsmissions = ont.submissions
      subsmissions.each do |ss|
        ss.load unless ss.loaded?
        ss.delete
      end
      ont.delete
    end

    u = LinkedData::Models::User.find("tim")
    u.delete unless u.nil?

    of = LinkedData::Models::OntologyFormat.find("OWL")
    of.delete unless of.nil?
  end

end
