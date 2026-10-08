#!/usr/bin/env ruby
# exclude_prune — the feedstock's exclude: axis on a staging tree
# (spec 13 §9; globs in the spec 03 §5 imaging-exclusion grammar).
#
#   exclude_prune.rb [--check] ROOT GLOB...
#
# Default (prune) mode: delete every ROOT-relative path matching a glob —
# a matched directory prunes its whole subtree. --check mode: print every
# match and exit 1 (the boot-smoke absence assertion on the extracted
# image). Globs follow fnmatch flag-0 semantics (a `*` run spans `/`,
# `\` quotes, `[...]` classes); a trailing `/` names the directory.
# Malformed globs are a hard error, never a silent drop: empty after
# normalization, an absolute spelling, or a `.`/`..` component (the
# match root is the payload root — there is nothing above it).

require 'fileutils'
require 'find'

check = ARGV.delete('--check')
root = ARGV.shift or abort "usage: exclude_prune.rb [--check] ROOT GLOB..."
globs = ARGV.map do |raw|
  g = raw.strip.sub(%r{/+\z}, '')
  if g.empty?
    abort "exclude_prune: invalid pattern #{raw.inspect} — empty (a pattern names a payload-root-relative path)"
  end
  if g.start_with?('/')
    abort "exclude_prune: invalid pattern #{raw.inspect} — patterns are relative to the payload root (drop the leading '/')"
  end
  if g.split('/').any? { |c| %w[. ..].include?(c) }
    abort "exclude_prune: invalid pattern #{raw.inspect} — '.' and '..' components are meaningless against the payload root"
  end
  g
end
abort 'exclude_prune: no globs given' if globs.empty?

hits = []
Find.find(root) do |path|
  next if path == root
  rel = path.delete_prefix("#{root}/")
  next unless globs.any? { |g| File.fnmatch(g, rel, 0) }
  hits << rel
  if File.directory?(path) && !File.symlink?(path)
    FileUtils.rm_rf(path) unless check
    Find.prune
  else
    FileUtils.rm_f(path) unless check
  end
end

if check
  unless hits.empty?
    hits.each { |h| warn "excluded path present: /#{h}" }
    exit 1
  end
else
  hits.each { |h| puts "exclude: pruned /#{h}" }
end
