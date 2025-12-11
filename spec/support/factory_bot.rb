# frozen_string_literal: true

# Load FactoryBot factories from spec/factories
FactoryBot.definition_file_paths = [
  Rails.root.join('spec', 'factories')
]
FactoryBot.find_definitions

