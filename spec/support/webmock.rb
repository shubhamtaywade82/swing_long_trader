# frozen_string_literal: true

require "webmock/rspec"

WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    "chromedriver.storage.googleapis.com", # For system tests
    "github.com", # For gem installations in CI
  ],
)
