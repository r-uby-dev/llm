# frozen_string_literal: true

source "https://rubygems.org"
gemspec

##
# TODO: do we need this? what for?
gem "cgi", "~> 0.4.2"

##
# JSON parsers
gem "oj", require: false
gem "yajl-ruby", require: false

##
# Gems that don't work on Windows
# out of the box. The 'curses' gem
# is required for the console, and
# it _might_ work if you are able to
# compile the curses gem on Windows.
gem "curb", "~> 1.3", install_if: -> { !Gem.win_platform? }
gem "curses", "~> 1.6", install_if: -> { !Gem.win_platform? }
