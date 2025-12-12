#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'
require 'optparse'

OPTIONS = {
  base_locale_file: 'config/locales/en.yml'
}
OptionParser.new do |opt|
  opt.on('-y') { OPTIONS[:auto_yes] = true }

  opt.on('-s', '--staged', 'Use staged changes') do
    OPTIONS[:use_staged] = true
  end

  opt.on('-b, 
    --base-locale BASELOCALE', 
    'Use different base locale. (default is config/locales/en.yml)') do |b|
    OPTIONS[:base_locale_file] = b 
  end
end.parse!

BACKUP_FILE = "#{OPTIONS[:base_locale_file]}.old"

def run_command(cmd)
  puts "Running: #{cmd}"
  output = `#{cmd}`
  unless $?.success?
    puts "Warning: Command failed with status #{$?.exitstatus}"
  end
  output
end

def get_changed_lines
  diff_from = OPTIONS[:use_staged] ? '--staged' : 'HEAD'
  diff_output = run_command("git diff #{diff_from} #{OPTIONS[:base_locale_file]}")
  
  changed_lines = []
  diff_output.each_line do |line|
    if line =~ /^[+-]\s+\w/ && !line.start_with?('+++', '---')
      changed_lines << line[1..-1].strip
    end
  end
  
  puts "Found #{changed_lines.length} changed lines in #{OPTIONS[:use_staged] ? 'staged' : 'unstaged'} diff"
  changed_lines
end

def extract_keys_from_lines(changed_lines)
  yaml_content = YAML.load_file(OPTIONS[:base_locale_file])
  keys = []
  
  changed_lines.each do |line|
    if line =~ /^(\s*)([a-z_][a-z0-9_]*):(.*)$/i
      indent = $1
      key_name = $2
      
      full_keys = find_full_key_paths(OPTIONS[:base_locale_file], key_name, line)
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

def cleanup_backup
  if File.exist?(BACKUP_FILE)
    FileUtils.rm(BACKUP_FILE)
    puts "Cleaned up backup file"
  end
end

begin
  changed_lines = get_changed_lines
  if changed_lines.empty?
    puts "\nNo changes detected in #{OPTIONS[:base_locale_file]}. Exiting."
    exit 0
  end
  
  keys = extract_keys_from_lines(changed_lines)
  if keys.empty?
    puts "\nNo valid i18n keys found in changes. Exiting."
    exit 0
  end

  # TODO: handle when a key is removed instead of updated or added
  # Get full base locale from last commit.
  # Get keys from changed lines and run 'extract_keys_from_lines' using 
  #   changed_lines on that bad boy.
  # Compare those keys to the current, if any keys exist in last commit but not 
  #   the current staged/unstaged changes then those need retranslated.
  
  puts "\n=== Locale keys to retranslate ==="
  keys.each { |k| puts "  - #{k}" }

  if !OPTIONS[:auto_yes]
    puts "\nContinue retranslating? [y/N]"
    response = STDIN.gets.chomp.downcase
    unless response == 'y' || response == 'yes'
      puts "Aborted."
      exit 0
    end
  end
  
  backup_file
  remove_keys(keys)
  restore_backup
  translate_missing
  
  puts "\n=== Process complete! ==="
  puts "The following keys have been retranslated:"
  keys.each { |k| puts "  - #{k}" }
  
  cleanup_backup
  
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
