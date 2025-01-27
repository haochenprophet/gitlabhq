# frozen_string_literal: true

require 'glfm_markdown'

# Use the glfm_markdown gem (https://gitlab.com/gitlab-org/ruby/gems/gitlab-glfm-markdown)
# to interface with the Rust based `comrak` parser
# https://github.com/kivikakk/comrak
module Banzai
  module Filter
    module MarkdownEngines
      class GlfmMarkdown < Base
        OPTIONS = {
          autolink: true,
          footnotes: true,
          full_info_string: true,
          github_pre_lang: true,
          hardbreaks: false,
          relaxed_autolinks: false,
          sourcepos: true,
          smart: false,
          strikethrough: true,
          table: true,
          tagfilter: false,
          tasklist: false, # still handled by a banzai filter/gem
          unsafe: true
        }.freeze

        def render(text)
          ::GLFMMarkdown.to_html(text, options: render_options)
        end

        private

        def render_options
          sourcepos_disabled? ? OPTIONS.merge(sourcepos: false) : OPTIONS
        end
      end
    end
  end
end

Banzai::Filter::MarkdownEngines::GlfmMarkdown.prepend_mod
