source "https://rubygems.org"
gem 'rails', '4.2.5'
gem 'mysql2'
gem 'sqlite3'

gem 'coffee-script'
gem 'spree',             github: 'spree/spree',             branch: '3-0-stable'

# Provides basic authentication functionality for testing parts of your engine
gem 'spree_auth_devise', github: 'spree/spree_auth_devise', :branch => '3-0-stable'

# gem 'spree_wallet', :git => 'git://github.com/vinsol/spree_wallet.git', branch: 'master'
gem 'spree_wallet', path: '../spree_wallet/'
gem 'sass-rails'
gem 'unified_payment', github: 'vinsol/Unified-Payments', tag: '1.1.0'

gem 'delayed_job_active_record', :tag => 'v4.0.0'

group :test do
  gem 'rspec-rails', '~> 3.0'
  gem 'shoulda-matchers', '~> 3.1'
  gem 'simplecov', :require => false
  gem 'database_cleaner'
  gem 'rspec-html-matchers'
  gem 'test-unit'
end
gemspec
