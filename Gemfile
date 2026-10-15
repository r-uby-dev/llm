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
# `curb` binds libcurl and `curses` binds ncurses. Both gems are source
# releases, neither publishes a mingw build, and a Windows image has
# neither library to bind. They are declared here rather than in the
# gemspec because this is the file that can say where a dependency is
# installed: a bundle that stopped at `bundle install` over a gem that
# could never load there is a worse answer than a bundle without it.
gem "curb", "~> 1.3", install_if: -> { !Gem.win_platform? }
gem "curses", "~> 1.6", install_if: -> { !Gem.win_platform? }
