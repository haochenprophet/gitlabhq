# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Reports::Sbom::Component, feature_category: :dependency_management do
  let(:component_type) { 'library' }
  let(:name) { 'component-name' }
  let(:purl_type) { 'npm' }
  let(:purl) { Sbom::PackageUrl.new(type: purl_type, name: name, version: version) }
  let(:version) { 'v0.0.1' }
  let(:source_package_name) { 'source-component' }

  subject(:component) do
    described_class.new(
      type: component_type,
      name: name,
      purl: purl,
      version: version,
      source_package_name: source_package_name
    )
  end

  it 'has correct attributes' do
    expect(component).to have_attributes(
      component_type: component_type,
      name: name,
      purl: an_object_having_attributes(type: purl_type),
      version: version,
      source_package_name: source_package_name
    )
  end

  describe '#name' do
    subject { component.name }

    it { is_expected.to eq(name) }

    context 'with namespace' do
      let(:purl) do
        Sbom::PackageUrl.new(type: 'maven', namespace: 'org.NameSpace', name: 'Name', version: 'v0.0.1')
      end

      it { is_expected.to eq('org.NameSpace/Name') }
    end
  end

  describe '#purl_type' do
    subject { component.purl_type }

    it { is_expected.to eq(purl_type) }
  end

  describe '#type' do
    subject { component.type }

    it { is_expected.to eq(component_type) }
  end

  describe '#<=>' do
    where do
      purl_a = Sbom::PackageUrl.new(type: 'npm', name: 'component-a', version: '1.0.0')
      purl_b = Sbom::PackageUrl.new(type: 'npm', name: 'component-b', version: '1.0.0')
      purl_composer = Sbom::PackageUrl.new(type: 'composer', name: 'component-a', version: '1.0.0')

      {
        'equal' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_a,
          b_purl: purl_a,
          a_version: '1.0.0',
          b_version: '1.0.0',
          expected: 0
        },
        'name lesser' => {
          a_name: 'component-a',
          b_name: 'component-b',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_a,
          b_purl: purl_b,
          a_version: '1.0.0',
          b_version: '1.0.0',
          expected: -1
        },
        'name greater' => {
          a_name: 'component-b',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_b,
          b_purl: purl_a,
          a_version: '1.0.0',
          b_version: '1.0.0',
          expected: 1
        },
        'purl type lesser' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_composer,
          b_purl: purl_a,
          a_version: '1.0.0',
          b_version: '1.0.0',
          expected: -1
        },
        'purl type greater' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_a,
          b_purl: purl_composer,
          a_version: '1.0.0',
          b_version: '1.0.0',
          expected: 1
        },
        'purl type nulls first' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: nil,
          b_purl: purl_a,
          a_version: '1.0.0',
          b_version: '1.0.0',
          expected: -1
        },
        'version lesser' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_a,
          b_purl: purl_a,
          a_version: '1.0.0',
          b_version: '2.0.0',
          expected: -1
        },
        'version greater' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_a,
          b_purl: purl_a,
          a_version: '2.0.0',
          b_version: '1.0.0',
          expected: 1
        },
        'version nulls first' => {
          a_name: 'component-a',
          b_name: 'component-a',
          a_type: 'library',
          b_type: 'library',
          a_purl: purl_a,
          b_purl: purl_a,
          a_version: nil,
          b_version: '1.0.0',
          expected: -1
        }
      }
    end

    with_them do
      specify do
        a = described_class.new(
          name: a_name,
          type: a_type,
          purl: a_purl,
          version: a_version
        )

        b = described_class.new(
          name: b_name,
          type: b_type,
          purl: b_purl,
          version: b_version
        )

        expect(a <=> b).to eq(expected)
      end
    end
  end

  describe '#ingestible?' do
    subject { component.ingestible? }

    context 'when component_type is invalid' do
      let(:component_type) { 'invalid' }

      it { is_expected.to be(false) }
    end

    context 'when purl_type is invalid' do
      let(:purl_type) { 'invalid' }

      it { is_expected.to be(false) }
    end

    context 'when component_type is valid' do
      where(:component_type) { ::Enums::Sbom.component_types.keys.map(&:to_s) }

      with_them do
        it { is_expected.to be(true) }
      end
    end

    context 'when purl_type is valid' do
      where(:purl_type) { ::Enums::Sbom.purl_types.keys.map(&:to_s) }

      with_them do
        it { is_expected.to be(true) }
      end
    end

    context 'when there is no purl' do
      let(:purl) { nil }

      it { is_expected.to be(true) }
    end
  end
end
