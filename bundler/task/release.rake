# frozen_string_literal: true

require "bundler/gem_tasks"
task :build => ["build_metadata", "man:build", "generate_files"] do
  Rake::Task["build_metadata:clean"].tap(&:reenable).real_invoke
end
task :release => ["man:require", "man:build", "release:verify_files", "release:verify_github", "build_metadata"]

namespace :release do
  task :verify_files do
    git_list = IO.popen("git ls-files -z", &:read).split("\x0").select {|f| f.match(%r{^(lib|exe)/}) }
    git_list += %w[CHANGELOG.md LICENSE.md README.md bundler.gemspec]
    git_list += Dir.glob("man/**/*")

    gem_list = Gem::Specification.load("bundler.gemspec").files

    extra_files = gem_list.to_set - git_list.to_set

    error_msg = <<~MSG

      You intend to ship some files with the gem that are not generated man pages
      nor source control files. Please review the extra list of files and try
      again:

      #{extra_files.to_a.join("\n  ")}

    MSG

    raise error_msg if extra_files.any?

    puts "The file list is correct for a release."
  end

  def gh_api_post(opts)
    gem "netrc", "~> 0.11.0"
    require "netrc"
    require "net/http"
    require "json"
    _username, token = Netrc.read["api.github.com"]

    host = opts.fetch(:host) { "https://api.github.com/" }
    path = opts.fetch(:path)
    uri = URI.join(host, path)
    uri.query = [uri.query, "access_token=#{token}"].compact.join("&")
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/vnd.github.v3+json",
      "Authorization" => "token #{token}",
    }.merge(opts.fetch(:headers, {}))
    body = opts.fetch(:body) { nil }

    response = if body
      Net::HTTP.post(uri, body.to_json, headers)
    else
      Net::HTTP.get_response(uri)
    end

    if response.code.to_i >= 400
      raise "#{uri}\n#{response.inspect}\n#{begin
                                              JSON.parse(response.body)
                                            rescue JSON::ParseError
                                              response.body
                                            end}"
    end
    JSON.parse(response.body)
  end

  task :verify_github do
    require "pp"
    gh_api_post :path => "/user"
  end

  def confirm(prompt = "")
    loop do
      print(prompt)
      print(": ") unless prompt.empty?
      break if $stdin.gets.strip == "y"
    end
  rescue Interrupt
    abort
  end

  def gh_api_request(opts)
    require "net/http"
    require "json"
    host = opts.fetch(:host) { "https://api.github.com/" }
    path = opts.fetch(:path)
    response = Net::HTTP.get_response(URI.join(host, path))

    links = Hash[*(response["Link"] || "").split(", ").map do |link|
      href, name = link.match(/<(.*?)>; rel="(\w+)"/).captures

      [name.to_sym, href]
    end.flatten]

    parsed_response = JSON.parse(response.body)

    if n = links[:next]
      parsed_response.concat gh_api_request(:host => host, :path => n)
    end

    parsed_response
  end

  def release_notes(version)
    title_token = "## "
    current_version_title = "#{title_token}#{version}"
    current_minor_title = "#{title_token}#{version.segments[0, 2].join(".")}"
    text = File.open("CHANGELOG.md", "r:UTF-8", &:read)
    lines = text.split("\n")

    current_version_index = lines.find_index {|line| line.strip =~ /^#{current_version_title}($|\b)/ }
    unless current_version_index
      raise "Update the changelog for the last version (#{version})"
    end
    current_version_index += 1
    previous_version_lines = lines[current_version_index.succ...-1]
    previous_version_index = current_version_index + (
      previous_version_lines.find_index {|line| line.start_with?(title_token) && !line.start_with?(current_minor_title) } ||
      lines.count
    )

    relevant = lines[current_version_index..previous_version_index]

    relevant.join("\n").strip
  end

  task :github, :version do |_t, args|
    version = Gem::Version.new(args.version)
    tag = "v#{version}"

    gh_api_post :path => "/repos/bundler/bundler/releases",
                :body => {
                  :tag_name => tag,
                  :name => tag,
                  :body => release_notes(version),
                  :prerelease => version.prerelease?,
                }
  end

  task :release do |args|
    Rake::Task["release:github"].invoke(args.version)
  end

  desc "Make a patch release with the PRs from master in the patch milestone"
  task :patch, :version do |_t, args|
    version = args.version

    version ||= begin
      version = bundler_spec.version
      segments = version.segments
      if segments.last.is_a?(String)
        segments << "1"
      else
        segments[-1] += 1
      end
      segments.join(".")
    end

    confirm "You are about to release #{version}, currently #{bundler_spec.version}"

    milestones = gh_api_request(:path => "repos/bundler/bundler/milestones?state=open")
    unless patch_milestone = milestones.find {|m| m["title"] == version }
      abort "failed to find #{version} milestone on GitHub"
    end
    prs = gh_api_request(:path => "repos/bundler/bundler/issues?milestone=#{patch_milestone["number"]}&state=all")
    prs.map! do |pr|
      abort "#{pr["html_url"]} hasn't been closed yet!" unless pr["state"] == "closed"
      next unless pr["pull_request"]
      pr["number"].to_s
    end
    prs.compact!

    bundler_spec.version = version

    branch = version.split(".", 3)[0, 2].push("stable").join("-")
    sh("git", "checkout", branch)

    version_file = "lib/bundler/version.rb"
    version_contents = File.read(version_file)
    unless version_contents.sub!(/^(\s*VERSION = )"#{Gem::Version::VERSION_PATTERN}"/, "\\1#{version.to_s.dump}")
      abort "failed to update #{version_file}, is it in the expected format?"
    end
    File.open(version_file, "w") {|f| f.write(version_contents) }

    commits = `git log --oneline origin/master --`.split("\n").map {|l| l.split(/\s/, 2) }.reverse
    commits.select! {|_sha, message| message =~ /(Auto merge of|Merge pull request|Merge) ##{Regexp.union(*prs)}/ }

    abort "Could not find commits for all PRs" unless commits.size == prs.size

    if commits.any? && !system("git", "cherry-pick", "-x", "-m", "1", *commits.map(&:first))
      warn "Opening a new shell to fix the cherry-pick errors"
      abort unless system("zsh")
    end

    prs.each do |pr|
      system("open", "https://github.com/bundler/bundler/pull/#{pr}")
      confirm "Add to the changelog"
    end

    confirm "Update changelog"
    sh("git", "commit", "-am", "Version #{version} with changelog")
    sh("rake", "release")
    sh("git", "checkout", "master")
    sh("git", "pull")
    sh("git", "merge", "v#{version}", "--no-edit")
    sh("git", "push")
  end

  desc "Open all PRs that have not been included in a stable release"
  task :open_unreleased_prs do
    def prs(on = "master")
      commits = `git log --oneline origin/#{on} --`.split("\n")
      commits.reverse_each.map {|c| c =~ /(Auto merge of|Merge pull request|Merge) #(\d+)/ && $2 }.compact
    end

    last_stable = `git ls-remote origin`.split("\n").map {|r| r =~ %r{refs/tags/v([\d.]+)$} && $1 }.compact.map {|v| Gem::Version.create(v) }.max
    last_stable = last_stable.segments[0, 2].<<("stable").join("-")

    in_release = prs("HEAD") - prs(last_stable)

    in_release.each do |pr|
      system("open", "https://github.com/bundler/bundler/pull/#{pr}")
      confirm
    end
  end
end
