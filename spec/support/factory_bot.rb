# frozen_string_literal: true

# Load FactoryBot factories from test/factories
FactoryBot.definition_file_paths = [
  Rails.root.join('test', 'factories'),
  Rails.root.join('spec', 'factories')
]
FactoryBot.find_definitions

