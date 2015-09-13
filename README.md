# Autorespawn

[![Build Status](https://travis-ci.org/doudou/autorespawn.svg?branch=master)](https://travis-ci.org/doudou/autorespawn)
[![Gem Version](https://badge.fury.io/rb/autorespawn.svg)](http://badge.fury.io/rb/autorespawn)
[![Coverage Status](https://coveralls.io/repos/doudou/autorespawn/badge.svg?branch=master&service=github)](https://coveralls.io/github/doudou/autorespawn?branch=master)
[![Documentation](http://b.repl.ca/v1/yard-docs-blue.png)](http://rubydoc.info/gems/autorespawn/frames)

Autorespawn is an implementation of the popular autoreload scheme, which reloads
Ruby program files when they change, but instead execs/spawns the underlying
program again. This avoids common issues related to the load mechanism.

## Usage

Require all the files you need autorespawn to watch and then do

~~~
Autorespawn.autorespawn do
   # Add the program's functionality here
end
~~~

If you touch ARGV and $0, you will want to pass the program and arguments
explicitely

~~~
Autorespawn.autorespawn 'program', 'argument0', 'argument1' do
end
~~~

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'autorespawn'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install autorespawn

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/doudou/autorespawn.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

