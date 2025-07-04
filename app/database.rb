require 'active_record'

module Database
  DB_FILE = File.expand_path(File.join(__dir__, '..', 'db', 'history.sqlite3'))
  MIGRATIONS_PATH = File.expand_path(File.join(__dir__, '..', 'db', 'migrate'))

  def self.init
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: DB_FILE)
    run_migrations
  end

  def self.run_migrations
    migration_context = ActiveRecord::MigrationContext.new(MIGRATIONS_PATH)
    migration_context.migrate
  end
end
