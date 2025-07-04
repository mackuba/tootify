require 'active_record'
require 'fileutils'

module Database
  DB_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'history.sqlite3'))
  MIGRATIONS_PATH = File.expand_path(File.join(__dir__, '..', 'db', 'migrate'))

  def self.connect
    FileUtils.mkdir_p(File.dirname(DB_FILE))
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: DB_FILE)
    run_migrations
  end

  def self.run_migrations
    ActiveRecord::Migration.verbose = false
    migration_context = ActiveRecord::MigrationContext.new(MIGRATIONS_PATH)
    migration_context.migrate
  end
end
