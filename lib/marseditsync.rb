# coding: utf-8
require "marseditsync/version"
require 'fileutils'
require 'optparse'

module Marseditsync
  ORIGINAL_HOST = 'maroon'
  DROPBOX_DIR = File.expand_path("~/Dropbox/app/MarsEdit")
  MARSEDIT_DIR = File.expand_path("~/Library/Application Support/MarsEdit")
  LINK_DIRS = ['LocalDrafts', 'PendingUploads']

  PREFERENCES_DIR = File.expand_path("~/Library/Preferences")
  PLIST_FILE = 'com.red-sweater.marsedit.macappstore.plist' 
  
  class Command
    def self.run(argv)
      STDOUT.sync = true
      opts = {}
      opt = OptionParser.new(argv)
      opt.banner = "Usage: #{opt.program_name} [-h|--help] <args>"
      opt.separator('')
      opt.separator "#{opt.program_name} Available Options"
      opt.on_head('-h', '--help', 'Show this message') do |v|
        puts opt.help
        exit
      end
      # ジョブ
      opt.on('-j VAL', '--job=VAL', "Exec specific job(backup|restore)") {|v| opts[:j] = v}
      # 冗長メッセージ
      opt.on('-v', '--verbose', 'Verbose message') {|v| opts[:v] = v}
      opt.on('-n', '--dry-run', 'Message only') {|v| opts[:n] = v}
      opt.parse!(argv)

      command = Command.new(opts)
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

    def initialize(opts)
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
    def backup
      # バックアップできるのはオリジナルホストだけ
      host = `hostname`.strip
      if host != ORIGINAL_HOST
        puts "This mac cannot use for backup. #{host}"
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
      
      srcfile = File.join(PREFERENCES_DIR, PLIST_FILE)
      dstfile = File.join(DROPBOX_DIR, PLIST_FILE)

      srcfile_mtime = File.mtime(srcfile)
      dstfile_mtime = File.mtime(dstfile)

      puts "cp #{srcfile}(#{srcfile_mtime}) #{dstfile}(#{dstfile_mtime})"      
      if srcfile_mtime > dstfile_mtime
        FileUtils.cp(srcfile, dstfile, :preserve => true)
      else
        puts "=>skip by mtime"
      end
      true
    end

    def restore
      
    end
  end
end
