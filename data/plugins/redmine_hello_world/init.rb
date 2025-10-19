# plugins/redmine_hello_world/init.rb
Redmine::Plugin.register :redmine_hello_world do
  name        'Hello World'
  author      'You'
  description 'A minimal Redmine plugin that says hello'
  version     '0.0.1'
  url         'https://example.com'   # optional
  author_url  'https://example.com'   # optional

  # Add a top menu item that points to our controller/action
  menu :top_menu,
       :hello_world,                          # internal id
       { controller: 'hello_world', action: 'index' },
       caption: 'Hello',                      # what appears in the top menu
       if: Proc.new { User.current.logged? }  # only show when logged in (optional)
end
