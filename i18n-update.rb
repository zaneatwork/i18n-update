#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'
require 'optparse'
require 'debug'


OPTIONS = {
  base_locale_file: 'config/locales/en.yml'
}

OptionParser.new do |opt|
  opt.on('-y') { OPTIONS[:auto_yes] = true }

  opt.on('-u', '--unstaged', 'Only translate unstaged changes') do
    OPTIONS[:use_unstaged] = true
  end

  opt.on('-b, 
    --base-locale BASELOCALE', 
    'Use different base locale. (default is config/locales/en.yml)') do |b|
    OPTIONS[:base_locale_file] = b 
  end
end.parse!

BACKUP_FILE = "#{OPTIONS[:base_locale_file]}.old"
LAST_COMMIT_FILE = "#{OPTIONS[:base_locale_file]}.last_commit"

def run_command(cmd)
  puts "Running: #{cmd}"
  output = `#{cmd}`
  unless $?.success?
    puts "Warning: Command failed with status #{$?.exitstatus}"
  end
  output
end

def get_changed_lines
  diff_from = OPTIONS[:only_unstaged] ? 'HEAD' : '--staged' 
  diff_output = run_command("git diff #{diff_from} #{OPTIONS[:base_locale_file]}")
  
  changed_lines = []
  diff_output.each_line do |line|
    if line =~ /^[+-]\s+\w/ && !line.start_with?('+++', '---')
      changed_lines << line[1..-1].strip
    end
  end
  
  puts "Found #{changed_lines.length} #{'unstaged' if OPTIONS[:only_unstaged]} changed lines in diff"
  changed_lines
end

def extract_keys_from_lines(locale_file, changed_lines)
  yaml_content = YAML.load_file(locale_file)
  keys = []
  
  changed_lines.each do |line|
    if line =~ /^(\s*)([a-z_][a-z0-9_]*):(.*)$/i
      indent = $1
      key_name = $2
      
      full_keys = find_full_key_paths(locale_file, key_name, line)
      if full_keys
        keys += full_keys
      end
    end
  end
  
  keys.uniq
end

def find_full_key_paths(file_path, key_name, target_line)
  lines = File.readlines(file_path)
  key_prefix_stack = []
  full_key_matches = []
  
  lines.each_with_index do |line, idx|
    # Skip the root language key (en:, es:, etc)
    next if line =~ /^[a-z]{2}:\s*$/
    
    if line =~ /^(\s*)([a-z_][a-z0-9_]*):(.*)$/i
      indent_level = $1.length / 2
      current_key = $2
      value = $3
      
      # Adjust stack to current indent level
      key_prefix_stack = key_prefix_stack[0...indent_level-1]
      
      if line.strip == target_line.strip
        full_key_matches << (key_prefix_stack + [current_key]).join('.')
      end
      
      key_has_children = value.strip.empty? || value.strip == '|' || value.strip == '>'
      key_prefix_stack << current_key if key_has_children
    end
  end
  
  full_key_matches if full_key_matches.length
end

def backup_file
  puts "\nCreating backup of unstaged changed locale values"
  FileUtils.cp(OPTIONS[:base_locale_file], BACKUP_FILE)
  puts "Created backup: #{BACKUP_FILE}"
end

def remove_keys(keys)
  puts "\nRemoving keys from all locale files so we can retranslate"
  keys.each do |key|
    puts "  Removing key: #{key}"
    run_command("bundle exec i18n-tasks rm '#{key}'")
  end
end

def restore_backup
  puts "\nRestoring unstaged changes to base locale"
  FileUtils.cp(BACKUP_FILE, OPTIONS[:base_locale_file])
  puts "Restored #{OPTIONS[:base_locale_file]} from backup"
end

def translate_missing
  puts "\nTranslating the updated locale keys"
  run_command("bundle exec i18n-tasks translate-missing")
end

def delete_file file
  if File.exist?(file)
    FileUtils.rm(file)
    puts "Deleted #{file}"
  end
end

def confirm message
  if !OPTIONS[:auto_yes]
    puts message
    response = STDIN.gets.chomp.downcase
    unless response == 'y' || response == 'yes'
      puts "Aborted."
      exit 0
    end
  end
end

def create_copy_of_last_commit
  run_command("git show HEAD:#{OPTIONS[:base_locale_file]} > #{LAST_COMMIT_FILE}")
end

begin
  changed_lines = get_changed_lines
  if changed_lines.empty?
    puts "\nNo changes detected in #{OPTIONS[:base_locale_file]}. Exiting."
    exit 0
  end
  
  keys = if OPTIONS[:only_unstaged]
    # keys that are removed don't exist in the file anymore and have to be 
    # picked from the last commit instead of the unstaged changes diff.
    unstaged_keys = extract_keys_from_lines(OPTIONS[:base_locale_file], changed_lines)

    create_copy_of_last_commit
    last_commit_keys = extract_keys_from_lines(LAST_COMMIT_FILE, lines)
    delete_file LAST_COMMIT_FILE 

    keys_removed = last_commit_keys - unstaged_keys
    unstaged_keys + keys_removed
  else 
    create_copy_of_last_commit
    keys = extract_keys_from_lines(LAST_COMMIT_FILE, changed_lines)
    delete_file LAST_COMMIT_FILE 
    keys
  end

  if keys.empty?
    puts "\nNo valid i18n keys found in changes. Exiting."
    exit 0
  end

  puts "\n=== Locale keys to retranslate ==="
  keys.each { |k| puts "  - #{k}" }

  confirm "\nContinue retranslating? [y/N]"
  backup_file
  remove_keys(keys)
  restore_backup
  translate_missing
  
  puts "\n=== Process complete! ==="
  puts "The following keys have been retranslated:"
  keys.each { |k| puts "  - #{k}" }
  
  delete_file BACKUP_FILE 
  
rescue => e
  puts "\nError: #{e.message}"
  puts e.backtrace.join("\n")
  
  if File.exist?(BACKUP_FILE)
    puts "\nAttempting to restore backup..."
    FileUtils.cp(BACKUP_FILE, OPTIONS[:base_locale_file])
    puts "Backup restored due to error"
  end
  
  exit 1
end
