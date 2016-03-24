#!/usr/bin/ruby

f = File.new(ARGV[0], 'a')
f.seek((ARGV[1].to_i * 1024 * 1024 * 1024) - 1, IO::SEEK_SET)
f.write()
f.close
