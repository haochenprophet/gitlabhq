# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting organization information', feature_category: :cell do
  include GraphqlHelpers

  let(:query) { graphql_query_for(:organization, { id: organization.to_global_id }, organization_fields) }
  let(:current_user) { user }
  let(:organization_fields) do
    <<~FIELDS
      id
      path
      groups {
        nodes {
          id
        }
      }
    FIELDS
  end

  let_it_be(:organization_user) { create(:organization_user) }
  let_it_be(:organization) { organization_user.organization }
  let_it_be(:user) { organization_user.user }
  let_it_be(:project) { create(:project, organization: organization) { |p| p.add_developer(user) } }
  let_it_be(:other_group) do
    create(:group, name: 'other-group', organization: organization) { |g| g.add_developer(user) }
  end

  subject(:request_organization) { post_graphql(query, current_user: current_user) }

  context 'when the user does not have access to the organization' do
    let(:current_user) { create(:user) }

    it 'returns the organization as all organizations are public' do
      request_organization

      expect(graphql_data_at(:organization, :id)).to eq(organization.to_global_id.to_s)
    end
  end

  context 'when user has access to the organization' do
    it_behaves_like 'a working graphql query' do
      before do
        request_organization
      end
    end

    context 'when requesting organization user' do
      let(:organization_fields) do
        <<~FIELDS
          organizationUsers {
            nodes {
              badges {
                text
                variant
              }
              id
              user {
                id
              }
            }
          }
        FIELDS
      end

      it 'returns correct organization user fields' do
        request_organization

        organization_user_node = graphql_data_at(:organization, :organizationUsers, :nodes).first
        expected_attributes = {
          "badges" => [{ "text" => "It's you!", "variant" => 'muted' }],
          "id" => organization_user.to_global_id.to_s,
          "user" => { "id" => user.to_global_id.to_s }
        }
        expect(organization_user_node).to match(expected_attributes)
      end

      it 'avoids N+1 queries for all the fields' do
        base_query_count = ActiveRecord::QueryRecorder.new { run_query }

        organization_user_2 = create(:organization_user, organization: organization)
        other_group.add_developer(organization_user_2.user)
        organization_user_from_project = create(:organization_user, organization: organization)
        project.add_developer(organization_user_from_project.user)

        expect { run_query }.not_to exceed_query_limit(base_query_count)
      end

      private

      def run_query
        run_with_clean_state(query, context: { current_user: current_user })
      end
    end

    context 'when requesting groups' do
      let(:groups) { graphql_data_at(:organization, :groups, :nodes) }
      let_it_be(:parent_group) { create(:group, name: 'parent-group', organization: organization) }
      let_it_be(:public_group) do
        create(:group, name: 'public-group', parent: parent_group, organization: organization)
      end

      let_it_be(:private_group) do
        create(:group, :private, name: 'private-group', organization: organization)
      end

      before_all do
        create(:group, :private, name: 'no-access', organization: organization)
        private_group.add_developer(user)
        public_group.add_developer(user)
        create(:group) { |g| g.add_developer(user) } # outside organization
      end

      context 'when resolve_organization_groups feature flag is disabled' do
        before do
          stub_feature_flags(resolve_organization_groups: false)
        end

        it 'returns no groups' do
          request_organization

          expect(graphql_data_at(:organization)).not_to be_nil
          expect(graphql_data_at(:organization, :groups, :nodes)).to be_empty
        end
      end

      it 'does not return ancestors of authorized groups' do
        request_organization

        expect(groups.pluck('id')).not_to include(parent_group.to_global_id.to_s)
      end

      context 'with `search` argument' do
        let(:search) { 'oth' }
        let(:organization_fields) do
          <<~FIELDS
            id
            path
            groups(search: "#{search}") {
              nodes {
                id
                name
              }
            }
          FIELDS
        end

        it 'filters groups by name' do
          request_organization

          expect(groups).to contain_exactly(a_graphql_entity_for(other_group))
        end
      end

      context 'with `sort` argument' do
        using RSpec::Parameterized::TableSyntax

        let(:authorized_groups) { [public_group, private_group, other_group] }

        where(:field, :direction, :sorted_groups) do
          'id'   | 'asc'  | lazy { authorized_groups.sort_by(&:id) }
          'id'   | 'desc' | lazy { authorized_groups.sort_by(&:id).reverse }
          'name' | 'asc'  | lazy { authorized_groups.sort_by(&:name) }
          'name' | 'desc' | lazy { authorized_groups.sort_by(&:name).reverse }
          'path' | 'asc'  | lazy { authorized_groups.sort_by(&:path) }
          'path' | 'desc' | lazy { authorized_groups.sort_by(&:path).reverse }
        end

        with_them do
          let(:sort) { "#{field}_#{direction}".upcase }
          let(:organization_fields) do
            <<~FIELDS
              id
              path
              groups(sort: #{sort}) {
                nodes {
                  id
                }
              }
            FIELDS
          end

          it 'sorts the groups' do
            request_organization

            expect(groups.pluck('id')).to eq(sorted_groups.map(&:to_global_id).map(&:to_s))
          end
        end
      end
    end

    context 'when requesting projects' do
      let(:projects) { graphql_data_at(:organization, :projects, :nodes) }
      let(:organization_fields) do
        <<~FIELDS
          projects {
            nodes {
              id
            }
          }
        FIELDS
      end

      before_all do
        create(:project) { |p| p.add_developer(user) } # some other project that shouldn't show up in our results
      end

      before do
        request_organization
      end

      it_behaves_like 'a working graphql query'

      it 'returns projects' do
        expect(projects).to contain_exactly(a_graphql_entity_for(project))
      end

      it_behaves_like 'sorted paginated query' do
        include_context 'no sort argument'

        let_it_be(:another_project) { create(:project, organization: organization) { |p| p.add_developer(user) } }
        let_it_be(:another_project2) { create(:project, organization: organization) { |p| p.add_developer(user) } }
        let(:first_param) { 2 }
        let(:data_path) { [:organization, :projects] }
        let(:all_records) { [another_project2, another_project, project].map { |p| global_id_of(p).to_s } }
      end

      def pagination_query(params)
        graphql_query_for(
          :organization, { id: organization.to_global_id },
          query_nodes(:projects, :id, include_pagination_info: true, args: params)
        )
      end
    end
  end
end
