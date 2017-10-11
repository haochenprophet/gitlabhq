require 'set'

module Gitlab
  # Module that can be used to detect if a path points to a special file such as
  # a README or a CONTRIBUTING file.
  module FileDetector
    PATTERNS = {
      # Project files
      readme: /\Areadme[^\/]*\z/i,
      changelog: /\A(changelog|history|changes|news)[^\/]*\z/i,
      license: /\A(licen[sc]e|copying)(\.[^\/]+)?\z/i,
      contributing: /\Acontributing[^\/]*\z/i,
      version: 'version',
      avatar: /\Alogo\.(png|jpg|gif)\z/,

      # Configuration files
      gitignore: '.gitignore',
      koding: '.koding.yml',
      gitlab_ci: '.gitlab-ci.yml',
      route_map: '.gitlab/route-map.yml',

      # Dependency files
      cartfile: /\ACartfile[^\/]*\z/,
      composer_json: 'composer.json',
      gemfile: /\A(Gemfile|gems\.rb)\z/,
      gemfile_lock: 'Gemfile.lock',
      gemspec: /\A[^\/]*\.gemspec\z/,
      godeps_json: 'Godeps.json',
      package_json: 'package.json',
      podfile: 'Podfile',
      podspec_json: /\A[^\/]*\.podspec\.json\z/,
      podspec: /\A[^\/]*\.podspec\z/,
      requirements_txt: /\A[^\/]*requirements\.txt\z/,
      yarn_lock: 'yarn.lock'
    }.freeze

    # Returns an Array of file types based on the given paths.
    #
    # This method can be used to check if a list of file paths (e.g. of changed
    # files) involve any special files such as a README or a LICENSE file.
    #
    # Example:
    #
    #     types_in_paths(%w{README.md foo/bar.txt}) # => [:readme]
    def self.types_in_paths(paths)
      types = Set.new

      paths.each do |path|
        type = type_of(path)

        types << type if type
      end

      types.to_a
    end

    # Returns the type of a file path, or nil if none could be detected.
    #
    # Returned types are Symbols such as `:readme`, `:version`, etc.
    #
    # Example:
    #
    #     type_of('README.md') # => :readme
    #     type_of('VERSION') # => :version
    def self.type_of(path)
      PATTERNS.each do |type, search|
        did_match = if search.is_a?(Regexp)
                      path =~ search
                    else
                      path.casecmp(search) == 0
                    end

        return type if did_match
      end

      nil
    end
  end
end
