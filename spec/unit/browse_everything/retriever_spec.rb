# frozen_string_literal: true

describe BrowseEverything::Retriever, vcr: { cassette_name: 'retriever', record: :none } do
  let(:retriever) { described_class.new }
  let(:datafile) { File.expand_path('../../fixtures/file_system/file_1.pdf', __dir__) }
  let(:datafile_with_spaces) { File.expand_path('../../fixtures/file_system/file 1.pdf', __dir__) }
  let(:data) { File.open(datafile, 'rb', &:read) }
  let(:data_with_spaces) { File.open(datafile_with_spaces, 'rb', &:read) }
  let(:size) { File.size(datafile) }

  context 'with a non-URI' do
    let(:spec) do
      {
        '0' => {
          'url' => '/some/dir/file.pdf',
          'file_name' => 'file.pdf',
          'file_size' => size.to_s
        }
      }
    end

    describe '#retrieve' do
      it 'raises an error' do
        expect { retriever.retrieve(spec['0']) }.to raise_error(URI::BadURIError)
      end
    end
  end

  context 'when retrieving using the HTTP' do
    let(:expiry_time) { (Time.current + 3600).xmlschema }
    let(:spec) do
      {
        '0' => {
          'url' => 'https://retrieve.cloud.example.com/some/dir/file.pdf',
          'auth_header' => { 'Authorization' => 'Bearer ya29.kQCEAHj1bwFXr2AuGQJmSGRWQXpacmmYZs4kzCiXns3d6H1ZpIDWmdM8' },
          'expires' => expiry_time,
          'file_name' => 'file.pdf',
          'file_size' => size.to_s
        }
      }
    end

    context 'when retrieving data using chunked-encoded streams' do
      it 'content' do
        content = +''
        retriever.retrieve(spec['0']) { |chunk, _retrieved, _total| content << chunk }
        expect(content).to eq(data)
      end

      it 'callbacks' do
        expect { |block| retriever.retrieve(spec['0'], &block) }.to yield_with_args(data, data.length, data.length)
      end
    end

    context 'when downloading content' do
      it 'content' do
        file = retriever.download(spec['0'])
        expect(File.open(file, 'rb', &:read)).to eq(data)
      end

      it 'callbacks' do
        expect { |block| retriever.download(spec['0'], &block) }.to yield_with_args(String, data.length, data.length)
      end
    end

    context 'when downloading content and a server error occurs' do
      let(:download_options) { spec['0'] }
      let(:response) { instance_double(HTTParty::Response) }
      let(:error) do
        {
          'error' =>
          {
            'errors' => [
              {
                'domain' => 'usageLimits',
                'reason' => 'dailyLimitExceededUnreg',
                'message' => 'Daily Limit for Unauthenticated Use Exceeded. Continued use requires signup.',
                'extendedHelp' => 'https://code.google.com/apis/console'
              }
            ],
            'code' => 403,
            'message' => 'Daily Limit for Unauthenticated Use Exceeded. Continued use requires signup.'
          }
        }
      end

      before do
        allow(response).to receive(:code).and_return(403)
        allow(response).to receive(:body).and_return(error)
        allow(HTTParty).to receive(:get).and_return(response)
      end
      it 'raises an exception' do
        expect { retriever.download(download_options) }.to raise_error(BrowseEverything::DownloadError, /BrowseEverything::Retriever: Failed to download/)
      end
    end
  end

  context 'when retrieving file content' do
    let(:spec) do
      {
        '0' => {
          'url' => "file://#{datafile}",
          'file_name' => 'file.pdf',
          'file_size' => size.to_s
        },
        '1' => {
          'url' => "file://#{datafile_with_spaces}",
          'file_name' => 'file.pdf',
          'file_size' => size.to_s
        }
      }
    end

    context 'when retrieving data using chunked-encoded streams' do
      it 'content' do
        content = +''
        retriever.retrieve(spec['0']) { |chunk, _retrieved, _total| content << chunk }
        expect(content).to eq(data)
      end

      it 'content with spaces' do
        content = +''
        retriever.retrieve(spec['1']) { |chunk, _retrieved, _total| content << chunk }
        expect(content).to eq(data_with_spaces)
      end

      it 'callbacks' do
        expect { |block| retriever.retrieve(spec['0'], &block) }.to yield_with_args(data, data.length, data.length)
      end
    end

    context 'when downloading content' do
      it 'content' do
        file = retriever.download(spec['0'])
        expect(File.open(file, 'rb', &:read)).to eq(data)
      end

      it 'callbacks' do
        expect { |block| retriever.download(spec['0'], &block) }.to yield_with_args(String, data.length, data.length)
      end
    end
  end
end
