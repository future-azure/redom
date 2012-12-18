require File.expand_path('../lib/redom/version', __FILE__)

Gem::Specification.new do |s|
  s.name          = 'redom'
  s.version       = Redom::VERSION
  s.platform      = Gem::Platform::RUBY
  s.summary       = 'A distributed object based server-centric web framework'
  s.description   = 'A distributed object based server-centric web framework.'
  s.author        = ['Yi Hu', 'Sasada Koichi']
  s.email         = 'future.azure@gmail.com'
  s.homepage      = 'https://github.com/future-azure/redom'

  s.require_paths = ['lib']
  s.files         = ['README.md', 'LICENSE', 'redom.gemspec']
  s.files        += ['lib/redom.rb'] + Dir['lib/redom/**/*.rb']
  s.files        += Dir['bin/redom']
  s.executables   = ['redom']

  s.add_dependency 'em-websocket', '>= 0.3.5'
  s.add_dependency 'opal', '>= 0.3.27'
end
