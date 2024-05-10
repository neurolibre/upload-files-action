require "octokit"
require "pathname"

def gh_token
  gh_token_from_env = ENV['BOT_TOKEN'].to_s.strip
  gh_token_from_env = ENV['GH_ACCESS_TOKEN'].to_s.strip if gh_token_from_env.empty?
  raise "!! ERROR: Invalid GitHub Token" if gh_token_from_env.empty?
  gh_token_from_env
end

def github_client
  @github_client ||= Octokit::Client.new(access_token: gh_token, auto_paginate: true)
end

def get_main_ref(repo)
  main_ref = github_client.refs(repo).select { |r| r[:ref] == "refs/heads/main" }.first
  if main_ref.nil?
    main_ref = github_client.refs(repo).select { |r| r[:ref] == "refs/heads/master" }.first
  end
  main_ref.object.sha
end

issue_id = ENV["ISSUE_ID"]
pdf_path = ENV["PDF_PATH"].to_s.strip
jats_path = ENV["JATS_PATH"].to_s.strip
crossref_path = ENV["CROSSREF_PATH"].to_s.strip
papers_repo = ENV["PAPERS_REPO"]
branch_prefix = ENV["BRANCH_PREFIX"]

id = "%05d" % issue_id
branch = branch_prefix.empty? ? id.to_s : "#{branch_prefix}.#{id}"
ref = "heads/#{branch}"

begin
  # Check branch existence
  github_client.ref(papers_repo, ref)
  # Delete old branch and create it again
  github_client.delete_ref(papers_repo, ref)
  github_client.create_ref(papers_repo, ref, get_main_ref(papers_repo))
rescue Octokit::NotFound
  # Create branch if it doesn't exist
  github_client.create_ref(papers_repo, ref, get_main_ref(papers_repo))
end

pdf_uploaded_path = "#{branch}/10.21105.#{branch}.pdf"
jats_uploaded_path = "#{branch}/10.21105.#{branch}.jats"
crossref_uploaded_path = "#{branch}/10.21105.#{branch}.crossref.xml"

# Add PDF file if present
if !pdf_path.empty? && File.exist?(pdf_path)
  gh_response = github_client.create_contents(papers_repo,
                                              pdf_uploaded_path,
                                              "Creating 10.21105.#{branch}.pdf",
                                              File.open("#{pdf_path.strip}").read,
                                              branch: branch)

  system("echo 'pdf_html_url=#{gh_response.content.html_url}' >> $GITHUB_OUTPUT")
  system("echo 'pdf_download_url=#{gh_response.content.download_url}' >> $GITHUB_OUTPUT")
end

# Add Crossref XML file if present
if !crossref_path.empty? && File.exist?(crossref_path)
  crossref_gh_response = github_client.create_contents(papers_repo,
                                              crossref_uploaded_path,
                                              "Creating 10.21105.#{branch}.crossref.xml",
                                              File.open("#{crossref_path.strip}").read,
                                              branch: branch)

  system("echo 'crossref_html_url=#{crossref_gh_response.content.html_url}' >> $GITHUB_OUTPUT")
  system("echo 'crossref_download_url=#{crossref_gh_response.content.download_url}' >> $GITHUB_OUTPUT")
end

# Add all files in the JATS' directory if present
if !jats_path.empty? && File.exist?(jats_path)
  jats_files_folder = File.dirname(jats_path)
  jats_files = Dir[File.join(jats_files_folder, "**/*.*")]
  jats_files.each do |jats_file|
      jats_file_name = Pathname(jats_file).relative_path_from(jats_files_folder).to_s

      if jats_file_name == "paper.jats"
        commit_message = "Creating 10.21105.#{branch}.jats"
        jats_file_uploaded_path = "#{branch}/paper.jats/10.21105.#{branch}.jats"
      else
        commit_message = "Adding JATS media file: #{jats_file_name}"
        jats_file_uploaded_path = "#{branch}/paper.jats/#{jats_file_name}"
      end

      jats_gh_response = github_client.create_contents(papers_repo,
                                                       jats_file_uploaded_path,
                                                       commit_message,
                                                       File.open(jats_file).read,
                                                       branch: branch)
      if jats_file_name == "paper.jats"
        system("echo 'jats_html_url=#{jats_gh_response.content.html_url}' >> $GITHUB_OUTPUT")
        system("echo 'jats_download_url=#{jats_gh_response.content.download_url}' >> $GITHUB_OUTPUT")
      end
  end
end
