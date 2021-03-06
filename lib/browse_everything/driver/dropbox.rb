# frozen_string_literal: true

require 'dropbox_api'
require_relative 'authentication_factory'

module BrowseEverything
  module Driver
    class Dropbox < Base
      class FileEntryFactory
        def self.build(metadata:, key:)
          factory_klass = klass_for metadata
          factory_klass.build(metadata: metadata, key: key)
        end

        class << self
          private def klass_for(metadata)
            case metadata
            when DropboxApi::Metadata::File
              FileFactory
            else
              ResourceFactory
            end
          end
        end
      end

      class ResourceFactory
        def self.build(metadata:, key:)
          path = metadata.path_display
          BrowseEverything::FileEntry.new(
            path,
            [key, path].join(':'),
            File.basename(path),
            nil,
            nil,
            true
          )
        end
      end

      class FileFactory
        def self.build(metadata:, key:)
          path = metadata.path_display
          BrowseEverything::FileEntry.new(
            path,
            [key, path].join(':'),
            File.basename(path),
            metadata.size,
            metadata.client_modified,
            false
          )
        end
      end

      class << self
        attr_accessor :authentication_klass

        def default_authentication_klass
          DropboxApi::Authenticator
        end
      end

      # Constructor
      # @param config_values [Hash] configuration for the driver
      def initialize(config_values)
        self.class.authentication_klass ||= self.class.default_authentication_klass
        super(config_values)
      end

      def icon
        'dropbox'
      end

      def validate_config
        raise InitializationError, 'Dropbox driver requires a :client_id argument' unless config[:client_id]
        raise InitializationError, 'Dropbox driver requires a :client_secret argument' unless config[:client_secret]
      end

      def contents(path = '')
        response = client.list_folder(path)
        @entries = response.entries.map { |entry| FileEntryFactory.build(metadata: entry, key: key) }
        @sorter.call(@entries)
      end

      def details(path)
        metadata = client.get_metadata(path)
        FileEntryFactory.build(metadata: metadata, key: key)
      end

      def download(path)
        temp_file = Tempfile.open(File.basename(path), encoding: 'ascii-8bit')
        client.download(path) do |chunk|
          temp_file.write chunk
        end
        temp_file.close
        temp_file
      end

      def uri_for(path)
        temp_file = download(path)
        uri = ::Addressable::URI.new(scheme: 'file', path: temp_file.path)
        uri.to_s
      end

      def link_for(path)
        [uri_for(path), {}]
      end

      def auth_link
        authenticator.authorize_url
      end

      def connect(params, _data)
        auth_bearer = authenticator.get_token(params[:code])
        self.token = auth_bearer.token
      end

      def authorized?
        token.present?
      end

      private

        def session
          AuthenticationFactory.new(
            self.class.authentication_klass,
            config[:client_id],
            config[:client_secret]
          )
        end

        def authenticate
          session.authenticate
        end

        def authenticator
          @authenticator ||= authenticate
        end

        def client
          DropboxApi::Client.new(token)
        end
    end
  end
end
