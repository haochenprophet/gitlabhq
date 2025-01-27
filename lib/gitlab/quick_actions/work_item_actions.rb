# frozen_string_literal: true

module Gitlab
  module QuickActions
    module WorkItemActions
      extend ActiveSupport::Concern
      include Gitlab::QuickActions::Dsl

      included do
        desc { _('Change work item type') }
        explanation do |target_type|
          format(_("Converts work item to %{type}. Widgets not supported in new type are removed."), type: target_type)
        end
        types WorkItem
        params 'Task | Objective | Key Result | Issue'
        command :type do |type_name|
          @execution_message[:type] = update_type(type_name, :type)
        end

        desc { _('Promote work item') }
        explanation do |type_name|
          format(_("Promotes work item to %{type}."), type: type_name)
        end
        types WorkItem
        params 'issue | objective'
        condition { supports_promotion? }
        command :promote_to do |type_name|
          @execution_message[:promote_to] = update_type(type_name, :promote_to)
        end

        desc { _('Change work item parent') }
        explanation do |parent_param|
          format(_("Change work item's parent to %{parent_ref}."), parent_ref: parent_param)
        end
        types WorkItem
        params 'Parent #iid, reference or URL'
        condition { supports_parent? && can_admin_link? }
        command :set_parent do |parent_param|
          @updates[:set_parent] = extract_work_items(parent_param).first
          @execution_message[:set_parent] = success_msg[:set_parent]
        end

        desc { _('Remove work item parent') }
        explanation do
          format(
            _("Remove %{parent_ref} as this work item's parent."),
            parent_ref: work_item_parent.to_reference(quick_action_target)
          )
        end
        types WorkItem
        condition { work_item_parent.present? && can_admin_link? }
        command :remove_parent do
          @updates[:remove_parent] = true
          @execution_message[:remove_parent] = success_msg[:remove_parent]
        end

        desc { _('Add children to work item') }
        explanation do |child_param|
          format(_("Add %{child_ref} to this work item as child(ren)."), child_ref: child_param)
        end
        types WorkItem
        params 'Children #iids, references or URLs'
        condition { supports_children? && can_admin_link? }
        command :add_child do |child_param|
          @updates[:add_child] = extract_work_items(child_param)
          @execution_message[:add_child] = success_msg[:add_child]
        end
      end

      private

      # rubocop:disable Gitlab/ModuleWithInstanceVariables
      def update_type(type_name, command)
        new_type = ::WorkItems::Type.find_by_name(type_name.titleize)
        error_message = command == :type ? validate_type(new_type) : validate_promote_to(new_type)
        return error_message if error_message.present?

        @updates[:issue_type] = new_type.base_type
        @updates[:work_item_type] = new_type

        success_msg[command]
      end
      # rubocop:enable Gitlab/ModuleWithInstanceVariables

      def validate_type(type)
        return error_msg(:not_found) unless type.present?
        return error_msg(:same_type) if quick_action_target.work_item_type == type
        return error_msg(:forbidden) unless current_user.can?(:"create_#{type.base_type}", quick_action_target)

        nil
      end

      # rubocop: disable CodeReuse/ActiveRecord
      def extract_work_items(params)
        return if params.nil?

        issuable_type = params.include?('work_items') ? :work_item : :issue
        issuables = extract_references(params, issuable_type)
        return unless issuables

        WorkItem.find(issuables.pluck(:id))
      end
      # rubocop: enable CodeReuse/ActiveRecord

      def validate_promote_to(type)
        return error_msg(:not_found, action: 'promote') unless type && supports_promote_to?(type.name)
        return if current_user.can?(:"create_#{type.base_type}", quick_action_target)

        error_msg(:forbidden, action: 'promote')
      end

      def current_type
        quick_action_target.work_item_type
      end

      def supports_promotion?
        current_type.base_type.in?(promote_to_map.keys)
      end

      def supports_promote_to?(type_name)
        type_name == promote_to_map[current_type.base_type]
      end

      def promote_to_map
        { issue: 'Incident', task: 'Issue' }.with_indifferent_access
      end

      def error_msg(reason, action: 'convert')
        message = {
          not_found: 'Provided type is not supported',
          forbidden: 'You have insufficient permissions',
          same_type: 'Types are the same'
        }.freeze

        format(_("Failed to %{action} this work item: %{reason}."), { action: action, reason: message[reason] })
      end

      def success_msg
        {
          type: _('Type changed successfully.'),
          promote_to: _("Work item promoted successfully."),
          set_parent: _('Work item parent set successfully'),
          remove_parent: _('Work item parent removed successfully'),
          add_child: _('Child work item(s) added successfully')
        }
      end

      def work_item_parent
        quick_action_target.work_item_parent
      end

      def supports_parent?
        ::WorkItems::HierarchyRestriction.find_by_child_type_id(quick_action_target.work_item_type_id).present?
      end

      def supports_children?
        ::WorkItems::HierarchyRestriction.find_by_parent_type_id(quick_action_target.work_item_type_id).present?
      end

      def can_admin_link?
        current_user.can?(:admin_issue_link, quick_action_target)
      end
    end
  end
end
