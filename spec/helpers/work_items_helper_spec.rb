# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkItemsHelper, feature_category: :team_planning do
  describe '#work_items_show_data' do
    subject(:work_items_show_data) { helper.work_items_show_data(project) }

    let_it_be(:project) { build(:project) }

    it 'returns the expected data properties' do
      expect(work_items_show_data).to include(
        {
          full_path: project.full_path,
          issues_list_path: project_issues_path(project),
          register_path: new_user_registration_path(redirect_to_referer: 'yes'),
          sign_in_path: user_session_path(redirect_to_referer: 'yes'),
          new_comment_template_path: profile_comment_templates_path,
          report_abuse_path: add_category_abuse_reports_path
        }
      )
    end
  end

  describe '#work_items_list_data' do
    let_it_be(:group) { build(:group) }

    subject(:work_items_list_data) { helper.work_items_list_data(group) }

    it 'returns expected data' do
      expect(work_items_list_data).to include(
        {
          full_path: group.full_path
        }
      )
    end
  end
end
