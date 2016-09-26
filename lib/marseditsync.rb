# coding: utf-8
require "marseditsync/version"
require 'fileutils'
require 'optparse'
require 'yaml'

module Marseditsync
  DROPBOX_DIR = File.expand_path("~/Dropbox/app/MarsEdit")
  MARSEDIT_DIR = File.expand_path("~/Library/Application Support/MarsEdit")
  LINK_DIRS = ['LocalDrafts', 'PendingUploads']

  PREFERENCES_DIR = File.expand_path("~/Library/Preferences")
  MAIN_PLIST_FILE = File.expand_path(File.join(PREFERENCES_DIR, 'com.red-sweater.marsedit.macappstore.plist'))
  # DataSources.plistも必要？  
  DATASOURCES_PLIST_FILE = File.expand_path(File.join(MARSEDIT_DIR, 'DataSources.plist'))
  PLIST_FILES = [MAIN_PLIST_FILE, DATASOURCES_PLIST_FILE]

  class Config
    def initialize(yaml)
      @yaml = yaml
      @common_original_host = config_value('common', 'original_host', true)
    end
    attr_reader :common_original_host

    def config_value(section, key, require)
      value = @yaml[section][key]
      if require && (value.nil? || value.empty?)
        raise RuntimeError, "#{section}:#{key}: is empty"
      end
      value
    end        
  end

  class Command
    def self.run(argv)
      STDOUT.sync = true
      opts = {}
      opt = OptionParser.new(argv)
      opt.banner = "Usage: #{opt.program_name} [options] <backup|restore>"
      opt.separator "options:"
      opt.on('-h', '--help', 'Show this message') do |v|
        puts opt.help
        exit
      end
      # 冗長メッセージ
      opt.on('-v', '--verbose', 'Verbose message') {|v| opts[:v] = v}
      opt.on('-n', '--dry-run', 'Message only') {|v| opts[:n] = v}
      opt.on('-c', '--config', 'Config file') {|v| opts[:c] = v} 
      opt.order!(argv)

      # 最後の引数を:jに入れて送る
      cmd = ARGV.shift
      opts[:j] = cmd
      yamlfile = opts[:c] || '~/.marseditsyncrc'
      config = Config.new(YAML.load_file(File.expand_path(yamlfile)))
      command = Command.new(config, opts)
      command.run
    end

    def self.create_dir(dir)
      # コピー先ディレクトリの確認
      if FileTest.directory?(dir)
        puts "dir already exists. #{dir}"
      else
        FileUtils.mkdir(dir)
      end
      unless FileTest.directory?(dir)
        puts "dir is not directory. #{dir}"
        return false
      end
      true
    end

    def self.cp_new(srcfile, dstfile, check_mtime = false)
      return unless FileTest.file?(srcfile)

      srcfile_mtime = File.mtime(srcfile)
      dstfile_mtime = nil
      if FileTest.file?(dstfile)
        dstfile_mtime = File.mtime(dstfile)
      end

      new_file = dstfile_mtime.nil? || srcfile_mtime > dstfile_mtime

      puts "cp #{srcfile}(#{srcfile_mtime}) #{dstfile}(#{dstfile_mtime})"      
      if !check_mtime || new_file
        FileUtils.cp(srcfile, dstfile, :preserve => true)
      else
        puts "=>skip by mtime"
      end    
    end

    def initialize(config, opts)
      @config = config
      @opts = opts
    end
    
    def run
      puts "##### marseditsync start #####"
      result = false
      if @opts[:j] == 'backup'
        result = backup
      elsif @opts[:j] == 'restore'
        result = restore
      end
      puts "##### marseditsync end(#{result}) #####" 
    end

    private
    def hostname
      `hostname`.strip
    end
    
    def original_host?
      hostname == @config.common_original_host
    end
    
    def backup
      # バックアップできるのはオリジナルホストだけ
      unless original_host?
        puts "This mac cannot use for backup. #{hostname}"
        return false
      end
      unless backup_links
        return false
      end
      unless backup_plists
        return false
      end
      true
    end
    
    def backup_links
      puts "# backup_links"

      return false unless self.class.create_dir(DROPBOX_DIR)

      # コピー実行
      LINK_DIRS.each do |link_dir|
        srcdir = File.join(MARSEDIT_DIR, link_dir)
        dstdir = File.join(DROPBOX_DIR, link_dir)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        if FileTest.directory?(srcdir) && !FileTest.symlink?(srcdir)
          puts "cp #{srcdir} #{DROPBOX_DIR}"
          # ファイルコピー実行
          unless FileTest.directory?(dstdir)
            FileUtils.cp_r(srcdir, DROPBOX_DIR)
          end
          # オリジナルはバックアップとして残す(なぜか他の親フォルダにmvできない?)
          backupdir = File.join(MARSEDIT_DIR, link_dir + '_' + timestamp)
          puts "mv #{srcdir} #{backupdir}"
          FileUtils.mv(srcdir, backupdir)
          puts "ln #{dstdir} #{srcdir}"
          FileUtils.symlink(dstdir, srcdir)
        end
      end

      true
    end

    def backup_plists
      puts "# backup_plists"
      return false unless self.class.create_dir(DROPBOX_DIR)
      PLIST_FILES.each do |srcfile|
        basename = File.basename(srcfile)
        dstfile = File.join(DROPBOX_DIR, basename)
        self.class.cp_new(srcfile, dstfile)
      end
      true
    end

    def restore
      if original_host?
        puts "This mac cannot use for restore. #{hostname}"
        return false
      end

      unless restore_links
        return false
      end
      unless restore_plists
        return false
      end
      true      
    end

    def restore_links
      puts "# restore_links"
      unless FileTest.directory?(MARSEDIT_DIR)
        print "dir is not directory. #{MARSEDIT_DIR}"
        return false
      end
      LINK_DIRS.each do |link_dir|
        srcdir = File.join(DROPBOX_DIR, link_dir)
        dstdir = File.join(MARSEDIT_DIR, link_dir)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        if FileTest.directory?(srcdir) 
          if FileTest.directory?(dstdir) && !FileTest.symlink?(dstdir)
            # オリジナルはバックアップとして残す(なぜか他の親フォルダにmvできない?)
            backupdir = File.join(MARSEDIT_DIR, link_dir + '_' + timestamp)
            puts "mv #{dstdir} #{backupdir}"
            FileUtils.mv(dstdir, backupdir)
          end
          puts "ln #{srcdir} #{dstdir}"
          FileUtils.symlink(srcdir, dstdir)
        end
      end
      true
    end

    def restore_plists
      puts "# restore_plists"
      PLIST_FILES.each do |dstfile|
        basename = File.basename(dstfile)
        srcfile = File.join(DROPBOX_DIR, basename)
        self.class.cp_new(srcfile, dstfile)
      end
      true      
    end
  end
end
