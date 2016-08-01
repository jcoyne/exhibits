require 'rails_helper'

describe DorHarvester do
  let(:exhibit) { FactoryGirl.create(:exhibit) }

  let :blacklight_solr do
    double
  end

  subject { harvester }
  let(:harvester) { described_class.new druid_list: druid, exhibit: exhibit }
  let(:druid) { 'xf680rd3068' }

  before do
    allow(harvester).to receive(:exhibit).and_return(exhibit)
    allow(harvester).to receive(:blacklight_solr).and_return(blacklight_solr)
    allow(harvester).to receive(:to_global_id).and_return('x')
  end

  describe '.instance' do
    subject { described_class.instance(exhibit) }

    before do
      subject.save!
    end

    it 'behaves like a singleton' do
      expect(described_class.instance(exhibit)).to eq subject
    end
  end

  describe '#druids' do
    context 'with a single item' do
      subject { described_class.new druid_list: 'xf680rd3068' }

      it 'extracts an array of DRUIDs from the list of druids' do
        expect(subject.druids).to match_array 'xf680rd3068'
      end
    end

    context 'with multiple items' do
      subject { described_class.new druid_list: "xf680rd3068\nxf680rd3069" }

      it 'extracts an array of DRUIDs from the list of druids' do
        expect(subject.druids).to match_array %w(xf680rd3068 xf680rd3069)
      end
    end

    context 'with crazy whitespace' do
      subject { described_class.new druid_list: "\t xf680rd3068\t\r\nxf680rd3067\t\t" }

      it 'extracts an array of DRUIDs from the list of druids' do
        expect(subject.druids).to match_array %w(xf680rd3068 xf680rd3067)
      end
    end
  end

  describe '#on_success' do
    let(:resource) { instance_double(Harvestdor::Indexer::Resource, bare_druid: druid) }
    it 'records a successful index for a druid' do
      expect do
        subject.on_success(resource)
      end.to change { subject.druid_info[druid] }.from(nil).to hash_including(ok: true)
    end
  end

  describe '#on_error' do
    let(:resource) { instance_double(Harvestdor::Indexer::Resource, bare_druid: druid) }
    it 'records an indexing error for a druid' do
      expect do
        subject.on_error(resource, 'error message')
      end.to change { subject.druid_info[druid] }.from(nil).to hash_including(ok: false, message: 'error message')
    end
  end

  describe '#waiting!' do
    let(:resource) do
      instance_double(Harvestdor::Indexer::Resource, bare_druid: druid,
                                                     exists?: true,
                                                     collection?: true,
                                                     items: [1, 2, 3])
    end

    before do
      allow(Spotlight::Dor::Resources.indexer).to receive(:resource).with(druid).and_return(resource)

      # populate some old data
      subject.druid_info[:x] = { old: :data }
    end

    it 'clears out existing status logging' do
      expect { subject.waiting! }.to change { subject.druid_info.size }.from(1).to(0)
    end

    it 'retrieves collection metadata' do
      subject.waiting!

      expect(subject.collections[druid]).to eq 'size' => 3
    end
  end

  describe '#resources' do
    let(:resource) { subject.resources.first }

    it 'is a Harvestdor::Indexer resource' do
      expect(resource).to be_a_kind_of Harvestdor::Indexer::Resource
    end

    it 'has the correct druid' do
      expect(resource.druid).to eq 'xf680rd3068'
    end

    it 'has the correct indexer' do
      expect(resource.indexer).to eq Spotlight::Dor::Resources.indexer.harvestdor
    end
  end

  describe '#indexable_resources' do
    subject { harvester.indexable_resources.to_a }

    context 'with a published druid' do
      let(:resource) { instance_double(Harvestdor::Indexer::Resource, exists?: true, bare_druid: druid, items: []) }

      before do
        allow(Spotlight::Dor::Resources.indexer).to receive(:resource).with(druid).and_return(resource)
      end

      it 'includes resources' do
        expect(subject.size).to eq 1
        expect(subject.first.bare_druid).to eq druid
      end
    end

    context 'with an unpublished druid' do
      let(:missing_resource) { instance_double(Harvestdor::Indexer::Resource, exists?: false, bare_druid: druid) }

      before do
        allow(Spotlight::Dor::Resources.indexer).to receive(:resource).with(druid).and_return(missing_resource)
      end

      it 'excludes missing resources' do
        expect(subject).to be_empty
      end
    end

    context 'with a collection' do
      let(:items) { [child].each } # `#each` converts the array to an enumerable
      let(:resource) { instance_double(Harvestdor::Indexer::Resource, exists?: true, bare_druid: druid, items: items) }
      let(:child) { instance_double(Harvestdor::Indexer::Resource, exists?: true, bare_druid: druid, items: []) }

      before do
        allow(Spotlight::Dor::Resources.indexer).to receive(:resource).with(druid).and_return(resource)
      end

      it 'includes child resources' do
        expect(subject.size).to eq 2
        expect(subject.first.bare_druid).to eq resource.bare_druid
        expect(subject.last.bare_druid).to eq child.bare_druid
      end
    end
  end

  describe '#reindex' do
    let(:resource) { subject.resources.first }

    before do
      allow(Spotlight::Dor::Resources.indexer).to receive(:solr_document).and_return(upstream: true)
      allow(resource).to receive(:collection?).and_return(false)
      allow_any_instance_of(SolrDocument).to receive(:to_solr).and_return({})
    end

    let(:solr_data) do
      [{ spotlight_resource_id_ssim: subject.to_global_id,
         spotlight_resource_type_ssim: 'dor_harvesters',
         upstream: true }]
    end

    it 'adds a document to solr' do
      expect(blacklight_solr).to receive(:update).with(params: { commitWithin: 500 },
                                                       data: solr_data.to_json,
                                                       headers: { 'Content-Type' => 'application/json' })
      expect(subject).to receive(:commit)
      subject.reindex
    end
  end
end
