# frozen_string_literal: true

require 'digest'
require 'faraday'
require_relative 'extraction'

module Macros
  # IIIF canvas extraction
  module Canvas
    ##
    # Note: This method assumes an "enhanced" canvas with additional properties
    # added beyond the IIIF Canvas model.
    def extract_canvas_label
      lambda do |record, accumulator, _context|
        labels = [record['label'].to_s, record['manifest_label'].to_s].reject(&:empty?)
        accumulator << labels.join(': ')
      end
    end

    ##
    # Note: This method assumes an "enhanced" canvas with additional properties
    # added beyond the IIIF Canvas model.
    def extract_canvas_label_sort
      lambda do |record, accumulator, _context|
        labels = [record['manifest_label'].to_s, record['label'].to_s].reject(&:empty?)
        accumulator << labels.join(': ')
      end
    end

    def extract_record(field)
      lambda do |record, accumulator, _context|
        return if record[field].blank?

        accumulator.push(*Array(record[field]).map(&:to_s))
      end
    end

    def extract_canvas_annotation_list_urls
      lambda do |record, accumulator, _context|
        return if record['otherContent'].blank?
        record['otherContent'].each do |link|
          next unless link['@type'] == 'sc:AnnotationList'
          accumulator << link['@id'].to_s
        end
      end
    end

    def extract_canvas_annotations
      lambda do |record, accumulator, _context|
        return if record['otherContent'].blank?
        record['otherContent'].each do |link|
          next unless link['@type'] == 'sc:AnnotationList'
          extract_annotations_from_list(accumulator, link['@id'].to_s)
        end
      end
    end

    private

    def extract_annotations_from_list(accumulator, url)
      annotation_list = JSON.parse(Faraday.get(url).body)
      return unless annotation_list['@type'] == 'sc:AnnotationList' && annotation_list['resources']
      annotation_list['resources'].each do |resource|
        next unless resource['@type'] == 'oa:Annotation'
        next if resource['resource']['chars'].blank?
        accumulator << resource['resource']['chars'].to_s
      end
    end
  end
end
