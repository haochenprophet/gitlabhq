# frozen_string_literal: true

require 'httparty'
require 'json'

module Gitlab
  module Housekeeper
    class GitlabClient
      Error = Class.new(StandardError)

      def initialize
        @token = ENV.fetch("HOUSEKEEPER_GITLAB_API_TOKEN")
        @base_uri = 'https://gitlab.com/api/v4'
      end

      # This looks at the system notes of the merge request to detect if it has been updated by anyone other than the
      # current housekeeper user. If it has then it assumes that they did this for a reason and we can skip updating
      # this detail of the merge request. Otherwise we assume we should generate it again using the latest output.
      def non_housekeeper_changes(
        source_project_id:,
        source_branch:,
        target_branch:,
        target_project_id:
      )

        iid = get_existing_merge_request(
          source_project_id: source_project_id,
          source_branch: source_branch,
          target_branch: target_branch,
          target_project_id: target_project_id
        )

        return [] if iid.nil?

        merge_request_notes = get_merge_request_notes(target_project_id: target_project_id, iid: iid)

        changes = Set.new

        merge_request_notes.each do |note|
          next false unless note["system"]
          next false if note["author"]["id"] == current_user_id

          changes << :title if note['body'].start_with?("changed title from")
          changes << :description if note['body'] == "changed the description"
          changes << :code if note['body'].match?(/added \d+ commit/)

          changes << :reviewers if note['body'].include?('requested review from')
          changes << :reviewers if note['body'].include?('removed review request for')
        end

        resource_label_events = get_merge_request_resource_label_events(target_project_id: target_project_id, iid: iid)

        resource_label_events.each do |event|
          next if event["user"]["id"] == current_user_id

          # Labels are routinely added by both humans and bots, so addition events aren't cause for concern.
          # However, if labels have been removed it may mean housekeeper added an incorrect label, and we shouldn't
          # re-add them.
          #
          # TODO: Inspect the actual labels housekeeper wants to add, and add if they haven't previously been removed.
          changes << :labels if event["action"] == "remove"
        end

        changes.to_a
      end

      # rubocop:disable Metrics/ParameterLists
      def create_or_update_merge_request(
        change:,
        source_project_id:,
        source_branch:,
        target_branch:,
        target_project_id:,
        update_title:,
        update_description:,
        update_labels:,
        update_reviewers:
      )
        existing_iid = get_existing_merge_request(
          source_project_id: source_project_id,
          source_branch: source_branch,
          target_branch: target_branch,
          target_project_id: target_project_id
        )

        if existing_iid
          update_existing_merge_request(
            change: change,
            existing_iid: existing_iid,
            target_project_id: target_project_id,
            update_title: update_title,
            update_description: update_description,
            update_labels: update_labels,
            update_reviewers: update_reviewers
          )
        else
          create_merge_request(
            change: change,
            source_project_id: source_project_id,
            source_branch: source_branch,
            target_branch: target_branch,
            target_project_id: target_project_id
          )
        end
      end
      # rubocop:enable Metrics/ParameterLists

      private

      def get_merge_request_notes(target_project_id:, iid:)
        request(:get, "/projects/#{target_project_id}/merge_requests/#{iid}/notes", query: { per_page: 100 })
      end

      def get_merge_request_resource_label_events(target_project_id:, iid:)
        request(:get, "/projects/#{target_project_id}/merge_requests/#{iid}/resource_label_events",
          query: { per_page: 100 })
      end

      def current_user_id
        @current_user_id ||= request(:get, "/user")['id']
      end

      def get_existing_merge_request(source_project_id:, source_branch:, target_branch:, target_project_id:)
        data = request(:get, "/projects/#{target_project_id}/merge_requests", query: {
          state: :opened,
          source_branch: source_branch,
          target_branch: target_branch,
          source_project_id: source_project_id
        })

        return nil if data.empty?

        iids = data.pluck('iid')

        raise Error, "More than one matching MR exists: iids: #{iids.join(',')}" unless data.size == 1

        iids.first
      end

      def create_merge_request(
        change:,
        source_project_id:,
        source_branch:,
        target_branch:,
        target_project_id:
      )
        request(:post, "/projects/#{source_project_id}/merge_requests", body: {
          title: change.title,
          description: change.mr_description,
          labels: Array(change.labels).join(','),
          source_branch: source_branch,
          target_branch: target_branch,
          target_project_id: target_project_id,
          remove_source_branch: true,
          reviewer_ids: usernames_to_ids(change.reviewers)
        })
      end

      def update_existing_merge_request(
        change:,
        existing_iid:,
        target_project_id:,
        update_title:,
        update_description:,
        update_labels:,
        update_reviewers:
      )
        body = {}

        body[:title] = change.title if update_title
        body[:description] = change.mr_description if update_description
        body[:add_labels] = Array(change.labels).join(',') if update_labels
        body[:reviewer_ids] = usernames_to_ids(change.reviewers) if update_reviewers

        return if body.empty?

        request(:put, "/projects/#{target_project_id}/merge_requests/#{existing_iid}", body: body)
      end

      def usernames_to_ids(usernames)
        usernames.map do |username|
          data = request(:get, "/users", query: { username: username })
          data[0]['id']
        end
      end

      def request(method, path, query: {}, body: {})
        response = HTTParty.public_send(method, "#{@base_uri}#{path}", query: query, body: body.to_json, headers: { # rubocop:disable GitlabSecurity/PublicSend
          'Private-Token' => @token,
          'Content-Type' => 'application/json'
        })

        unless (200..299).cover?(response.code)
          raise Error,
            "Failed with response code: #{response.code} and body:\n#{response.body}"
        end

        JSON.parse(response.body)
      end
    end
  end
end
