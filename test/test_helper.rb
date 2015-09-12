begin
    require 'simplecov'
    require 'coveralls'
    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
        SimpleCov::Formatter::HTMLFormatter,
        Coveralls::SimpleCov::Formatter
    ]
    SimpleCov.start do
        add_filter "/test/"
    end
rescue LoadError
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'autorespawn'
require 'minitest/autorun'
require 'minitest/spec'
require 'flexmock/minitest'

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
    end
end
