require "rubygems/version"
require "net/http"
require "json"
require "uri"

def bump_from_master_branch
  versions.last.yield_self { |version| version if version.segments[1...3] == [0, 0] }
end

def bump_from_version_specific_branch(name)
  # This helps to ensure branch does exist.
  branch = version_specific_branches.find { |b| b["name"] == name }
  return unless branch

  # Find latest version for the branch (compare by major and minor).
  # We use find here since versions are sorted in descending order.
  latest_version = versions.reverse.find { |v| v.segments[1...3] == branch[:version].segments[1...3] }
  return unless latest_version

  # Increment patch version, tag, and push.
  candidate_version = Gem::Version.new(latest_version.segments.dup.tap { |s| s[2] += 1 })
  tag_n_push(candidate_version.to_s)
end

def tag_n_push(tag)
  %x( git config --global user.email "builds@travis-ci.com" )
  %x( git config --global user.name "Travis CI" )
  %x( git tag #{tag} -a -m "Generated tag from TravisCI build #{ENV["TRAVIS_BUILD_NUMBER"]}" )
  %x( git push https://yivo:#{ENV.fetch("GITHUB_API_KEY")}@github.com/yivo/peatio-test #{tag} )
end

def versions
  JSON.load(Net::HTTP.get(URI.parse("https://api.github.com/repos/yivo/peatio-test/tags"))).map do |x|
    Gem::Version.new(x.fetch("name"))
  end
end

def version_specific_branches
  branches = JSON.load(Net::HTTP.get(URI.parse("https://api.github.com/repos/yivo/peatio-test/branches")))
  branches.map do |x|
    if x.fetch("name") =~ /\A(\d)-(\d)-\w+\z/
      { name: x["name"], version: Gem::Version.new($1 + "." + $2) }
    end
  end.compact
end

def generic_semver?(version)
  version.segments.count == 3 && version.segments.all? { |segment| segment.match?(/\A[0-9]+\z/) }
end

if ENV["TRAVIS_REPO_SLUG"] == "yivo/peatio-test" &&
  ENV["TRAVIS_PULL_REQUEST"] == "false" &&
  !ENV["TRAVIS_BRANCH"].to_s.empty? &&
  !ENV["GITHUB_API_KEY"].to_s.empty? &&
  ENV["TRAVIS_TAG"].to_s.empty?

  if ENV["TRAVIS_BRANCH"] == "master"
    bump_from_master_branch
  else
    bump_from_version_specific_branch(ENV["TRAVIS_BRANCH"])
  end
end

