# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CDN Asset URLs' do
  let(:cdn_host) { 'https://cdn-test.example.com' }

  before do
    # Mock the CDN_HOST configuration
    allow(Rails.application.config).to receive(:asset_host).and_return(cdn_host)
  end

  describe 'Login page assets' do
    before { visit new_user_session_path }

    it 'uses CDN for JavaScript bundles' do
      page.all('script[src]').to_a.each do |script|
        src = script['src']
        next if src.blank?
        next if src.start_with?('data:') # Skip inline/data URIs
        next unless src.include?('/packs/') # Only check Vite assets

        expect(src).to start_with(cdn_host),
                       "Script src '#{src}' doesn't use CDN_HOST"
      end
    end

    it 'uses CDN for stylesheets' do
      page.all('link[rel="stylesheet"]').to_a.each do |link|
        href = link['href']
        next if href.blank?
        next unless href.include?('/packs/') # Only check Vite assets

        expect(href).to start_with(cdn_host),
                        "Stylesheet href '#{href}' doesn't use CDN_HOST"
      end
    end

    it 'uses CDN for module preloads' do
      page.all('link[rel~="preload"], link[rel~="modulepreload"]').to_a.each do |link|
        href = link['href']
        next if href.blank?
        next unless href.include?('/packs/') # Only check Vite assets

        expect(href).to start_with(cdn_host),
                        "Preload href '#{href}' doesn't use CDN_HOST"
      end
    end

    it 'has cdn-host meta tag with correct value' do
      meta = page.find('meta[name="cdn-host"]', visible: false)
      expect(meta['content']).to eq(cdn_host)
    end

    it 'has crossorigin attribute on CDN assets' do
      page.all('script[src], link[rel="stylesheet"]').to_a.each do |tag|
        url = tag['src'] || tag['href']
        next unless url&.start_with?(cdn_host)

        expect(tag['crossorigin']).to eq('anonymous'),
                                      "CDN asset missing crossorigin=anonymous: #{url}"
      end
    end
  end

  describe 'Public timeline assets' do
    before do
      visit root_path
    end

    it 'uses CDN for all script tags' do
      page.all('script[src]').to_a.each do |script|
        src = script['src']
        next if src.blank?
        next if src.start_with?('data:')
        next unless src.include?('/packs/')

        expect(src).to start_with(cdn_host),
                       "Script src '#{src}' doesn't use CDN_HOST"
      end
    end

    it 'uses CDN for all stylesheets' do
      page.all('link[rel="stylesheet"]').to_a.each do |link|
        href = link['href']
        next if href.blank?
        next unless href.include?('/packs/')

        expect(href).to start_with(cdn_host),
                        "Stylesheet href '#{href}' doesn't use CDN_HOST"
      end
    end
  end

  describe 'Asset helper methods' do
    it 'cdn_host helper returns correct value' do
      # Test the helper directly
      helper_class = Class.new do
        include ApplicationHelper
      end

      helper = helper_class.new
      allow(Rails.application.config).to receive(:asset_host).and_return(cdn_host)

      expect(helper.cdn_host).to eq(cdn_host)
    end

    it 'cdn_host? returns true when CDN is configured' do
      helper_class = Class.new do
        include ApplicationHelper
      end

      helper = helper_class.new
      allow(Rails.application.config).to receive(:asset_host).and_return(cdn_host)

      expect(helper.cdn_host?).to be true
    end

    it 'cdn_host? returns false when CDN is not configured' do
      helper_class = Class.new do
        include ApplicationHelper
      end

      helper = helper_class.new
      allow(Rails.application.config).to receive(:asset_host).and_return(nil)

      expect(helper.cdn_host?).to be false
    end
  end

  describe 'Without CDN configuration' do
    let(:cdn_host) { nil }

    before do
      allow(Rails.application.config).to receive(:asset_host).and_return(nil)
      visit new_user_session_path
    end

    it 'uses relative paths for JavaScript bundles' do
      page.all('script[src]').to_a.each do |script|
        src = script['src']
        next if src.blank?
        next if src.start_with?('data:')
        next unless src.include?('/packs/')

        expect(src).to start_with('/packs/'),
                       "Script src '#{src}' should use relative path when CDN not configured"
      end
    end

    it 'does not have cdn-host meta tag' do
      expect(page).to have_no_css('meta[name="cdn-host"]', visible: :all)
    end
  end
end
