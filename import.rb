require 'bible_parser'
require 'bible_ref'
require 'bundler/setup'
require 'dotenv'
require 'mysql2'
require 'optparse'
require 'sequel'

Dotenv.load

@options = {
  bibles_path: './bibles'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby import.rb [options]'

  opts.on('-t', '--translation=NAME', 'Only import a single translation (e.g. eng-ylt.osis.xml)') do |name|
    @options[:translation] = name
  end

  opts.on('--bibles-path=PATH', 'Specify custom path for open-bibles (default: #{@options[:bibles_path].inspect})') do |path|
    @options[:bibles_path] = path
  end

  opts.on('--overwrite', 'Overwrite any existing data') do
    @options[:overwrite] = true
  end

  opts.on('--drop-tables', 'Drop all tables first (and recreate them)') do
    @options[:drop_tables] = true
  end

  opts.on('-h', '--help') do
    puts opts
    exit
  end
end.parse!

unless ENV['DATABASE_URL']
  puts 'Must set the DATABASE_URL environment variable (probably in .env)'
  exit 1
end

DB = Sequel.connect(ENV['DATABASE_URL'].sub(%r{mysql://}, 'mysql2://'), encoding: 'utf8mb4')

puts "\n=== STARTING PROGRAM ==="
puts "Current directory: #{Dir.pwd}"
puts "ENV['DATABASE_URL']: #{ENV['DATABASE_URL']}"

puts "\n=== ENVIRONMENT LOADED ==="
puts "After Dotenv.load, DATABASE_URL: #{ENV['DATABASE_URL']}"

# 测试数据库连接
begin
  DB.test_connection
  puts "✓ Database connection successful!"
  puts "Tables: #{DB.tables.inspect}"
rescue => e
  puts "✗ Database connection failed!"
  puts "Error: #{e.message}"
  puts e.backtrace
  exit 1
end

class Importer
  def import(path, translation_id)
    puts "  importing from path: #{path}"
    puts "  translation_id: #{translation_id}"
    
    unless File.exist?(path)
      puts "  ERROR: File not found: #{path}"
      return
    end
    
    begin
      DB.run("SET FOREIGN_KEY_CHECKS=0")
      DB.run("ALTER TABLE verses DISABLE KEYS")
      
      DB.transaction do
        bible = BibleParser.new(File.open(path))
        verse_count = 0
        batch_size = 1000
        verses_batch = []
        
        bible.each_verse do |verse|
          data = verse.to_h
          data[:book] = data.delete(:book_title)
          data[:chapter] = data.delete(:chapter_num)
          data[:verse] = data.delete(:num)
          data[:translation_id] = translation_id
          
          verses_batch << data
          verse_count += 1
          
          if verses_batch.size >= batch_size
            print "  Importing batch of #{batch_size} verses (total: #{verse_count})...\r"
            DB[:verses].multi_insert(verses_batch)
            verses_batch = []
          end
        end
        
        DB[:verses].multi_insert(verses_batch) unless verses_batch.empty?
        puts "\n  Successfully imported #{verse_count} verses"
      end
      
    rescue => e
      puts "  ERROR: #{e.message}"
      puts e.backtrace
    ensure
      DB.run("ALTER TABLE verses ENABLE KEYS")
      DB.run("SET FOREIGN_KEY_CHECKS=1")
    end
  end
end

if @options[:drop_tables]
  DB.run("SET FOREIGN_KEY_CHECKS=0")
  DB.drop_table? :translations
  DB.drop_table? :verses
  DB.run("SET FOREIGN_KEY_CHECKS=1")
end

DB.create_table? :translations, charset: 'utf8mb4' do
  primary_key :id
  String :identifier
  String :name
  String :language
  String :language_code
  String :license
end

DB.create_table? :verses, charset: 'utf8mb4' do
  primary_key :id
  Fixnum :book_num
  String :book_id
  String :book
  Fixnum :chapter
  Fixnum :verse
  String :text, text: true
  Fixnum :translation_id
end

puts "\n=== TABLES CREATED ==="
puts "Current tables: #{DB.tables.inspect}"

importer = Importer.new

puts "\n=== SCANNING FILES ==="
puts "Looking in: #{@options[:bibles_path]}"
puts "Full path: #{File.expand_path(@options[:bibles_path])}"
Dir.glob("#{@options[:bibles_path]}/*.{xml,usfx,osis}").each do |f|
  puts "Found file: #{f}"
end

translations = Dir.glob("#{@options[:bibles_path]}/*.{xml,usfx,osis}").map do |path|
  filename = File.basename(path)
  lang_code_and_id = filename.split('.').first
  lang_parts = lang_code_and_id.split('-')
  
  {
    identifier: lang_parts[1],
    name: lang_parts[1].upcase,
    language: lang_parts[0],
    language_code: lang_parts[0]
  }
end

puts "\n=== PROCESSING TRANSLATIONS ==="
puts "Total translations found: #{translations.length}"

puts "\nFound translations:"
translations.each do |t|
  puts "  - #{t.inspect}"
end
puts "\n"

translations.each do |translation|
  puts "\nProcessing translation: #{translation.inspect}"
  
  if @options[:translation]
    next unless File.basename("#{@options[:bibles_path]}/#{translation[:language_code]}-#{translation[:identifier]}.usfx.xml") == @options[:translation]
    path = "#{@options[:bibles_path]}/#{@options[:translation]}"
  else
    path = "#{@options[:bibles_path]}/#{translation[:language_code]}-#{translation[:identifier]}"
    path += case File.exist?("#{path}.usfx.xml")
            when true then ".usfx.xml"
            when false then ".osis.xml"
            end
  end

  puts "Full path: #{path}"
  puts "File exists? #{File.exist?(path)}"
  
  translation[:language_code] = "zh-tw" if translation[:language_code] == "chi"
  puts "Updated translation: #{translation.inspect}"

  existing_id = DB["select id from translations where identifier = ?", translation[:identifier]].first&.fetch(:id, nil)
  puts "Existing ID: #{existing_id}"
  
  if existing_id
    if @options[:overwrite]
      puts "Deleting existing data..."
      DB[:verses].where(translation_id: existing_id).delete
      DB[:translations].where(identifier: translation[:identifier]).delete
    else
      puts "  skipping existing translation (pass --overwrite)"
      next
    end
  end

  puts "Inserting translation..."
  id = DB[:translations].insert(translation)
  puts "Inserted with ID: #{id}"
  
  puts "Starting import..."
  importer.import(path, id)
end
