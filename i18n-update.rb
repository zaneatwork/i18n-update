#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'
require 'optparse'


def run_command(cmd)
  verbose_log "Running: #{cmd}"
  output = `#{cmd}`
  unless $?.success?
    verbose_log "Warning: Command failed with status #{$?.exitstatus}"
  end
  output
end

def get_keys_from_diff(file, use_staged=false)
  diff_from = use_staged ? '--staged' : 'HEAD'
  diff_file = "#{file}.diff"
  run_command("git diff #{diff_from} -W #{file} > #{diff_file}")
  
  key_prefix_stack = []
  full_key_matches = []
  
  File.readlines(diff_file).each_with_index do |line, idx|
    # Skip the root language key (en:, es:, etc)
    next if line =~ /^[a-z]{2}:\s*$/
    
    if line =~ /^[-|+]?(\s*)([a-z_][a-z0-9_]*):(.*)$/i
      indent_level = $1.length / 2
      current_key = $2
      value = $3
      
      # Adjust stack to current indent level
      key_prefix_stack = key_prefix_stack[0...indent_level-1]
      
      if !value.strip.empty? && (line.start_with?("+") || line.start_with?("-"))
        full_key_matches << (key_prefix_stack + [current_key]).join('.')
      end
      
      key_has_children = value.strip.empty? || value.strip == '|' || value.strip == '>'
      key_prefix_stack << current_key if key_has_children
    end
  end

  delete_file diff_file
  
  full_key_matches.uniq if full_key_matches.length
end

def remove_keys keys
  verbose_log "\nRemoving keys from all locale files so we can retranslate"
  keys.each do |key|
    verbose_log "  Removing key: #{key}"
    run_command("bundle exec i18n-tasks rm '#{key}'")
  end
end

def translate_missing
  verbose_log "\nTranslating the updated locale keys"
  run_command("bundle exec i18n-tasks translate-missing")
end

def delete_file file
  if File.exist? file
    FileUtils.rm file
    verbose_log "Deleted #{file}"
  end
end

def backup_file file
  backup_file = "#{file}.old"
  verbose_log "\nCreating backup of unstaged changed locale values"
  FileUtils.cp(file, backup_file)
  verbose_log "Created backup: #{backup_file}"
end

def restore_file_from_backup file
  backup_file = "#{file}.old"
  verbose_log "\nRestoring unstaged changes to base locale"
  FileUtils.cp(backup_file, file)
  verbose_log "Restored #{file} from backup"
end

def cleanup_backup file
  backup_file = "#{file}.old"
  delete_file backup_file
end

def confirm(message, auto_approve=false)
  if !OPTIONS[:auto_yes]
    puts message
    response = STDIN.gets.chomp.downcase
    unless response == 'y' || response == 'yes'
      puts "Aborted."
      exit 0
    end
  end
end

OPTIONS = {
  base_locale_file: 'config/locales/en.yml'
}

OptionParser.new do |opt|
  opt.on('-b, 
    --base-locale BASELOCALE', 
    'Use different base locale. (default is config/locales/en.yml)') do |b|
    OPTIONS[:base_locale_file] = b 
  end

  opt.on('-s', '--staged', 'Translate staged changes') do
    OPTIONS[:staged] = true
  end

  opt.on('-v', '--verbose', 'Verbose mode') do
    OPTIONS[:verbose] = true
  end

  opt.on('-y') { OPTIONS[:auto_yes] = true }
end.parse!

def verbose_log message
  puts message if OPTIONS[:verbose]
end


begin
  keys = get_keys_from_diff(OPTIONS[:base_locale_file], OPTIONS[:staged])

  if keys.empty?
    puts "\nNo changes detected in #{OPTIONS[:base_locale_file]}. Exiting."
    exit 0
  end

  puts "\n=== Locale keys to update ==="
  keys.each { |k| puts "  - #{k}" }

  confirm("\nContinue? [y/N]", OPTIONS[:auto_yes])

  backup_file OPTIONS[:base_locale_file]
  remove_keys keys
  restore_file_from_backup OPTIONS[:base_locale_file]
  cleanup_backup OPTIONS[:base_locale_file]
  translate_missing
  
  puts "\n=== Translation complete! ==="
  verbose_log "The following keys have been updated:"
  keys.each { |k| verbose_log "  - #{k}" }
  
rescue => e
  puts "\nError: #{e.message}"
  puts e.backtrace.join("\n")
  
  if File.exist?("#{OPTIONS[:base_locale_file]}.old")
    verbose_log "\nAttempting to restore backup..."
    restore_file_from_backup OPTIONS[:base_locale_file]
    verbose_log "Backup restored due to error"
  end
  
  exit 1
end
