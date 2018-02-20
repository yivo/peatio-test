require "rubygems/version"
require "net/http"
require "json"
require "uri"
# require "pry-byebug"

def bump_from_master_branch
  return unless (latest_version = versions.last)

  linked_branch = version_specific_branches.find { |b| b[:version].segments == latest_version.segments[0...2] }
  return if linked_branch

  candidate_version = Gem::Version.new(latest_version.segments.dup.tap { |s| s[2] += 1 }.join("."))
  tag_n_push(candidate_version.to_s) unless versions.include?(candidate_version)
end

def bump_from_version_specific_branch(name)
  # This helps to ensure branch does exist.
  branch = version_specific_branches.find { |b| b[:name] == name }
  return unless branch

  # Find latest version for the branch (compare by major and minor).
  # We use find here since versions are sorted in descending order.
  latest_version = versions.reverse.find { |v| v.segments[0...2] == branch[:version].segments }
  return unless latest_version

  # Increment patch version, tag, and push.
  candidate_version = Gem::Version.new(latest_version.segments.dup.tap { |s| s[2] += 1 }.join("."))
  tag_n_push(candidate_version.to_s) unless versions.include?(candidate_version)
end

def tag_n_push(tag)
  %x( git config --global user.email "bot@peatio-test.com" )
  %x( git config --global user.name "Peatio Test" )
  %x( git tag #{tag} -a -m "Automatically generated tag from TravisCI build #{ENV.fetch("TRAVIS_BUILD_NUMBER")}." )
  %x( git push https://yivo:#{ENV.fetch("GITHUB_API_KEY")}@github.com/yivo/peatio-test #{tag} )
end

def versions
  puts github_api_authenticated_get("https://api.github.com/repos/yivo/peatio-test/tags?access_token=")

  @versions ||= github_api_authenticated_get("https://api.github.com/repos/yivo/peatio-test/tags?access_token=").map do |x|
    Gem::Version.new(x.fetch("name"))
  end.sort
end

def version_specific_branches
  @branches ||= github_api_authenticated_get("https://api.github.com/repos/yivo/peatio-test/branches").map do |x|
    if x.fetch("name") =~ /\A(\d)-(\d)-\w+\z/
      { name: x["name"], version: Gem::Version.new($1 + "." + $2) }
    end
  end.compact
end

def github_api_authenticated_get(url)
  JSON.load(Net::HTTP.get(URI.parse(url + "?access_token=" + ENV.fetch("GITHUB_API_KEY"))))
end

def generic_semver?(version)
  version.segments.count == 3 && version.segments.all? { |segment| segment.match?(/\A[0-9]+\z/) }
end

# Build must not run on a fork.
bump   = ENV["TRAVIS_REPO_SLUG"] == "yivo/peatio-test"
# Skip PRs.
bump &&= ENV["TRAVIS_PULL_REQUEST"] == "false"
# Build must run on branch.
bump &&= !ENV["TRAVIS_BRANCH"].to_s.empty?
# GitHub API key must be available.
bump &&= !ENV["GITHUB_API_KEY"].to_s.empty?
# Build must not run on tag.
bump &&= ENV["TRAVIS_TAG"].to_s.empty?

if bump
  if ENV["TRAVIS_BRANCH"] == "master"
    bump_from_master_branch
  else
    bump_from_version_specific_branch(ENV["TRAVIS_BRANCH"])
  end
end

