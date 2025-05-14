#!/usr/bin/env ruby

require 'open3'
require 'fileutils'
require 'open-uri'

# Ensure required gems
begin
  require 'zip'
rescue LoadError
  abort "Please install the rubyzip gem: `gem install rubyzip`"
end

begin
  require 'ruby-progressbar'
rescue LoadError
  abort "Please install the ruby-progressbar gem: `gem install ruby-progressbar`"
end

# Configurable constants
PATH_FILE        = 'CLIPath.txt'
CLI_ZIP_URL      = 'https://github.com/arduino/arduino-cli/releases/download/v0.35.3/arduino-cli_0.35.3_Windows_64bit.zip'
CLI_DIR          = File.expand_path(File.join(__dir__, 'arduino-cli'))
CLI_ZIP_FILE     = File.join(__dir__, 'arduino-cli.zip')
CLI_EXE          = File.join(CLI_DIR, 'arduino-cli.exe')
SKETCH_ZIP_URL   = 'https://github.com/huh445/Digispark-Scripts/archive/refs/heads/main.zip'
SKETCH_DIR       = File.expand_path(File.join(__dir__, 'sketches'))
SKETCH_ZIP_FILE  = File.join(__dir__, 'sketches.zip')
BOARD            = 'digistump:avr:digispark-tiny'

# Execute a shell command and raise on failure
def run_cmd(cmd)
  stdout, stderr, status = Open3.capture3(cmd)
  puts stdout
  unless status.success?
    puts stderr
    raise "Command failed (exit #{status.exitstatus})"
  end
  stdout
end

# Download a file with a progress bar using open-uri
def download_file(url, dest)
  URI.open(url, "rb") do |source|
    total = (source.meta["content-length"] || 0).to_i
    progress = if total > 0
                 ProgressBar.create(title: File.basename(dest), total: total, format: '%t: |%B| %p%%')
               else
                 ProgressBar.create(title: File.basename(dest), format: '%t: |%B|')
               end
    File.open(dest, "wb") do |io|
      while (chunk = source.read(16 * 1024))
        io.write(chunk)
        progress.progress += chunk.size if total > 0
      end
    end
    progress.finish
  end
  puts "Downloaded to #{dest}\n"
rescue OpenURI::HTTPError => e
  abort "Download failed: #{e.message}"
end

# Unzip a file with a progress bar
def unzip(src, dest)
  unless File.size?(src) && File.size(src) > 0
    abort "Zip file #{src} is empty or missing"
  end
  Zip::File.open(src) do |zip|
    entries = zip.entries
    progress = ProgressBar.create(title: 'Extracting', total: entries.size, format: '%t: |%B| %p%%')
    entries.each do |entry|
      target = File.join(dest, entry.name)
      FileUtils.mkdir_p(File.dirname(target))
      entry.extract(target) { true }
      progress.increment
    end
    progress.finish
  end
  puts "Extraction complete\n"
end

# Install Arduino-CLI automatically
def install_cli
  FileUtils.rm_rf(CLI_DIR)
  puts 'Downloading and installing Arduino-CLI...'
  download_file(CLI_ZIP_URL, CLI_ZIP_FILE)
  unzip(CLI_ZIP_FILE, CLI_DIR)
  File.delete(CLI_ZIP_FILE) if File.exist?(CLI_ZIP_FILE)
  run_cmd(%("#{CLI_EXE}" config init))
  run_cmd(%("#{CLI_EXE}" config add board_manager.additional_urls https://raw.githubusercontent.com/digistump/arduino-boards-index/master/package_digistump_index.json))
  run_cmd(%("#{CLI_EXE}" core install digistump:avr))
  File.write(PATH_FILE, %("#{CLI_EXE}"))
  puts "Arduino-CLI installed at #{CLI_EXE}\n"
end

# Fetch sketches from GitHub
def fetch_sketches
  FileUtils.rm_rf(SKETCH_DIR)
  puts 'Fetching sketches from GitHub...'
  download_file(SKETCH_ZIP_URL, SKETCH_ZIP_FILE)
  unzip(SKETCH_ZIP_FILE, SKETCH_DIR)
  File.delete(SKETCH_ZIP_FILE) if File.exist?(SKETCH_ZIP_FILE)
end

# Check if Digispark core is installed
def has_digispark?(cli)
  output = run_cmd(%("#{cli}" core list))
  output.lines.any? { |l| l.include?('digistump:avr') }
rescue
  false
end

# Ensure Arduino-CLI is present, auto-install if missing or invalid
def verify_cli
  if File.exist?(PATH_FILE)
    cli = File.read(PATH_FILE).strip.gsub(/^"|"$/, '')
    return cli if File.exist?(cli) && has_digispark?(cli)
  end
  if File.exist?(CLI_EXE) && has_digispark?(CLI_EXE)
    File.write(PATH_FILE, %("#{CLI_EXE}"))
    return CLI_EXE
  end
  install_cli
  CLI_EXE
end

# List all .ino files in sketches directory
def list_sketches
  Dir.glob(File.join(SKETCH_DIR, '**', '*.ino'))
end

# Prompt the user to choose a sketch
def choose_sketch(sketches)
  sketches.each_with_index { |s, i| puts "#{i+1}. #{File.basename(s, '.ino')}" }
  print 'Select sketch number: '
  sketches.fetch(gets.to_i - 1)
end

# Compile and upload the chosen sketch
def compile_and_upload(cli, sketch)
  run_cmd(%("#{cli}" compile -b #{BOARD} "#{sketch}"))
  puts 'Compilation successful.'
  puts 'Please plug in Digispark now...'
  sleep 2
  run_cmd(%("#{cli}" upload -b #{BOARD} "#{sketch}"))
  puts 'Upload complete.'
end

# Main flow
def run
  cli = verify_cli
  fetch_sketches
  sketches = list_sketches
  abort 'No sketches found.' if sketches.empty?
  choice = choose_sketch(sketches)
  compile_and_upload(cli, choice)
end

run if __FILE__ == $0
