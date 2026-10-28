#!/usr/bin/env ruby
# render.rb — render the Apple CI/CD workflow templates into a project.
#
# Usage:
#   ruby render.rb --app-name SayIt --scheme SayIt --xcodeproj SayIt.xcodeproj \
#     --change-paths "^(SayIt/|SayIt\.xcodeproj/)" --out <project>/.github/workflows

require "fileutils"

args = {}
ARGV.each_slice(2) { |k, v| args[k.sub(/^--/, "").tr("-", "_")] = v if k.start_with?("--") }

required = %w[app_name scheme xcodeproj out]
missing = required.select { |k| args[k].nil? || args[k].empty? }
abort "missing required args: #{missing.join(", ")}" unless missing.empty?

tpl_dir = File.join(__dir__)
out_dir = File.expand_path(args["out"])

tokens = {
  "__APP_NAME__"      => args["app_name"],
  "__SCHEME__"        => args["scheme"],
  "__XCODEPROJ__"     => args["xcodeproj"],
  "__BUNDLE_ID__"     => args["bundle_id"] || "com.example.#{args["app_name"]}",
  "__CHANGE_PATHS__"  => args["change_paths"] || "^(?i)(app/|#{Regexp.escape(args["xcodeproj"])}/)",
}

%w[pr-checks.yml.tmpl build-release.yml.tmpl].each do |tpl|
  content = File.read(File.join(tpl_dir, tpl))
  tokens.each { |k, v| content = content.gsub(k, v) }
  dest = File.join(out_dir, tpl.sub(/\.tmpl$/, ""))
  FileUtils.mkdir_p(out_dir)
  File.write(dest, content)
  puts "rendered #{dest}"
end

# Sanity: no unreplaced tokens left.
Dir.glob(File.join(out_dir, "*.yml")).each do |f|
  body = File.read(f)
  if (leftovers = body.scan(/__[A-Z_]+__/).uniq).any?
    abort "#{f}: unreplaced tokens: #{leftovers.join(", ")}"
  end
end
puts "OK"
