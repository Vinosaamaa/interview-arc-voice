#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

workflow_path, action_path = ARGV
abort "usage: validate-artifact-workflow.rb WORKFLOW ACTION" unless workflow_path && action_path

workflow = YAML.safe_load(File.read(workflow_path), aliases: true)
triggers = workflow.fetch("on", workflow[true])
abort "workflow must run for pull requests and main pushes" unless triggers.key?("pull_request") && triggers.key?("push")
abort "workflow requires Actions read permission" unless workflow.dig("permissions", "actions") == "read"

pr_job = workflow.dig("jobs", "test-and-package")
main_job = workflow.dig("jobs", "promote-or-package-main")
abort "missing PR or main job" unless pr_job && main_job

pr_steps = pr_job.fetch("steps")
main_steps = main_job.fetch("steps")
abort "PR job must use the canonical package action" unless pr_steps.any? { |step| step["uses"] == "./.github/actions/package-voice" }
fallback = main_steps.find { |step| step["uses"] == "./.github/actions/package-voice" }
abort "main fallback must use the canonical package action" unless fallback&.fetch("if", "")&.include?("available != 'true'")

promotion_script = main_steps.find { |step| step["id"] == "promotion" }&.fetch("run", "") || ""
abort "promotion must evaluate every tree-equivalent candidate" unless promotion_script.include?("artifact-provenance.py candidates") && promotion_script.include?("while IFS=")
abort "promotion must require a successful pull-request run" unless promotion_script.include?('run.get("event") == "pull_request"') && promotion_script.include?('run.get("conclusion") == "success"')

download = main_steps.find { |step| step["uses"] == "actions/download-artifact@v4" }
abort "missing promoted artifact download" unless download&.dig("with", "run-id")
verify = main_steps.find { |step| step.fetch("run", "").include?("artifact-provenance.py verify") }
abort "missing embedded tree verification" unless verify

uploads = [pr_steps, main_steps].flat_map { |steps| steps.select { |step| step["uses"] == "actions/upload-artifact@v4" } }
abort "both PR and main artifacts must be retained for 14 days" unless uploads.length == 2 && uploads.all? { |step| step.dig("with", "retention-days") == 14 }

pr_archive = pr_steps.find { |step| step.fetch("run", "").include?("archive-app.sh") }
abort "PR artifact must archive the app before upload" unless pr_archive
main_archive = main_steps.find { |step| step.fetch("run", "").include?("archive-app.sh") }
abort "rebuilt main artifact must archive the app before upload" unless main_archive&.fetch("if", "")&.include?("available != 'true'")

action = YAML.safe_load(File.read(action_path), aliases: true)
abort "package action must be composite" unless action.dig("runs", "using") == "composite"
commands = action.dig("runs", "steps").map { |step| step["run"] }.compact.join("\n")
%w[
  audit-public-safety.sh
  ArtifactPromotionPolicyTests.sh
  swift\ test
  SigningPolicyTests.sh
  package-app.sh
].each do |required|
  abort "canonical package action is missing #{required}" unless commands.include?(required.tr("\\", ""))
end

puts "Artifact workflow policy is valid."
