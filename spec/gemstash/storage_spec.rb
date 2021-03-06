require "spec_helper"
require "yaml"

describe Gemstash::Storage do
  before do
    @folder = Dir.mktmpdir
  end
  after do
    FileUtils.remove_entry(@folder) if File.exist?(@folder)
  end

  it "builds with a valid folder" do
    expect(Gemstash::Storage.new(@folder)).not_to be_nil
  end

  it "builds the path if it does not exists" do
    new_path = File.join(@folder, "other-path")
    expect(Dir.exist?(new_path)).to be_falsy
    Gemstash::Storage.new(new_path)
    expect(Dir.exist?(new_path)).to be_truthy
  end

  it "stores metadata about Gemstash and the storage engine version" do
    expect(Gemstash::Storage.metadata[:storage_version]).to eq(Gemstash::Storage::VERSION)
    expect(Gemstash::Storage.metadata[:gemstash_version]).to eq(Gemstash::VERSION)
  end

  it "prevents using storage engine if the storage version is too new" do
    metadata = {
      storage_version: 999_999,
      gemstash_version: Gemstash::VERSION
    }

    File.write(Gemstash::Env.current.base_file("metadata.yml"), metadata.to_yaml)
    expect { Gemstash::Storage.new(@folder) }.to raise_error(Gemstash::Storage::VersionTooNew)
  end

  context "with a valid storage" do
    let(:storage) { Gemstash::Storage.new(@folder) }

    it "can create a child storage from itself" do
      storage.for("gems")
      expect(Dir.exist?(File.join(@folder, "gems"))).to be_truthy
    end

    it "returns a non existing resource when requested" do
      resource = storage.resource("an_id")
      expect(resource).not_to be_nil
      expect(resource).not_to exist
    end

    it "auto sets gemstash version property, even when properties not saved" do
      resource = storage.resource("something")
      resource = resource.save(content: "some content").load(:content)
      expect(resource.properties).to eq(gemstash_storage_version: Gemstash::Storage::VERSION)
    end

    it "won't update gemstash version when already stored" do
      storage.resource("42").save({ content: "content" }, gemstash_storage_version: 0)
      expect(storage.resource("42").load(:content).properties[:gemstash_storage_version]).to eq(0)
      storage.resource("42").update_properties(key: "value")
      expect(storage.resource("42").load(:content).properties[:gemstash_storage_version]).to eq(0)
    end

    it "won't load a resource that is at a larger version than our current version" do
      storage.resource("42").save({ content: "content" }, gemstash_storage_version: 999_999)
      expect { storage.resource("42").load(:content) }.to raise_error(Gemstash::Storage::VersionTooNew)
    end

    context "with a simple resource" do
      let(:resource) { storage.resource("an_id") }

      it "can be saved" do
        resource.save(content: "content")
        expect(resource).to exist
      end

      it "can be read afterwards" do
        resource.save(content: "some content")
        expect(resource.content(:content)).to eq("some content")
      end

      it "can also save properties" do
        resource.save({ content: "some other content" }, "content-type" => "octet/stream")
        expect(resource.content(:content)).to eq("some other content")
        expect(resource.properties).to eq("content-type" => "octet/stream",
                                          gemstash_storage_version: Gemstash::Storage::VERSION)
      end

      it "can save nested properties" do
        resource.save({ content: "some other content" }, headers: { "content-type" => "octet/stream" })
        expect(resource.content(:content)).to eq("some other content")
        expect(resource.properties).to eq(headers: { "content-type" => "octet/stream" },
                                          gemstash_storage_version: Gemstash::Storage::VERSION)
      end
    end

    context "with a previously stored resource" do
      let(:resource_id) { "42" }
      let(:content) { "zapatito" }
      before do
        storage.resource(resource_id).save(content: content)
      end

      it "loads the content from disk" do
        resource = storage.resource(resource_id)
        resource.load(:content)
        expect(resource.content(:content)).to eq(content)
      end

      it "can have properties updated" do
        resource = storage.resource(resource_id)
        resource.update_properties(key: "value", other: :value)
        expect(storage.resource(resource_id).load(:content).properties).
          to eq(key: "value", other: :value, gemstash_storage_version: Gemstash::Storage::VERSION)
        resource = storage.resource(resource_id)
        resource.update_properties(key: "new", new: 42)
        expect(storage.resource(resource_id).load(:content).properties).
          to eq(key: "new", other: :value, new: 42, gemstash_storage_version: Gemstash::Storage::VERSION)
      end

      it "can be deleted" do
        resource = storage.resource(resource_id)
        resource.delete(:content)
        expect(resource.exist?(:content)).to be_falsey
        expect { resource.load(:content) }.to raise_error(/no content to load/)
        # Fetching the resource again will still prevent access
        resource = storage.resource(resource_id)
        expect(resource.exist?(:content)).to be_falsey
        expect { resource.load(:content) }.to raise_error(/no content to load/)

        # Ensure properties is deleted
        properties_filename = File.join(resource.folder, "properties.yml")
        expect(File.exist?(properties_filename)).to be_falsey
      end
    end

    context "storing multiple files in one resource" do
      let(:resource_id) { "42" }
      let(:content) { "zapatito" }
      let(:other_content) { "foobar" }

      it "can be done in 1 save" do
        resource = storage.resource(resource_id)
        resource.save(content: content, other_content: other_content)
        expect(resource.content(:content)).to eq(content)
        expect(resource.content(:other_content)).to eq(other_content)

        resource = storage.resource(resource_id)
        resource.load(:content).load(:other_content)
        expect(resource.content(:content)).to eq(content)
        expect(resource.content(:other_content)).to eq(other_content)
      end

      it "can be done in 2 saves" do
        resource = storage.resource(resource_id)
        resource.save(content: content).save(other_content: other_content)
        expect(resource.content(:content)).to eq(content)
        expect(resource.content(:other_content)).to eq(other_content)

        resource = storage.resource(resource_id)
        resource.load(:content).load(:other_content)
        expect(resource.content(:content)).to eq(content)
        expect(resource.content(:other_content)).to eq(other_content)
      end

      it "can be done in 2 saves with separate properties defined" do
        resource = storage.resource(resource_id)
        resource.save({ content: content }, foo: "bar").save({ other_content: other_content }, bar: "baz")
        expect(resource.properties).to eq(foo: "bar", bar: "baz", gemstash_storage_version: Gemstash::Storage::VERSION)

        resource = storage.resource(resource_id)
        resource.load(:content)
        expect(resource.properties).to eq(foo: "bar", bar: "baz", gemstash_storage_version: Gemstash::Storage::VERSION)
      end

      it "can be done in 2 saves with nil properties defined on second" do
        resource = storage.resource(resource_id)
        resource.save({ content: content }, foo: "bar").save(other_content: other_content)
        expect(resource.properties).to eq(foo: "bar", gemstash_storage_version: Gemstash::Storage::VERSION)

        resource = storage.resource(resource_id)
        resource.load(:content)
        expect(resource.properties).to eq(foo: "bar", gemstash_storage_version: Gemstash::Storage::VERSION)
      end

      it "can be done in 2 saves with separate properties defined from separate resource instances" do
        storage.resource(resource_id).save({ content: content }, foo: "bar")
        resource = storage.resource(resource_id)
        resource.save({ other_content: other_content }, bar: "baz")
        expect(resource.properties).to eq(foo: "bar", bar: "baz", gemstash_storage_version: Gemstash::Storage::VERSION)

        resource = storage.resource(resource_id)
        resource.load(:content)
        expect(resource.properties).to eq(foo: "bar", bar: "baz", gemstash_storage_version: Gemstash::Storage::VERSION)
      end

      it "supports 1 file being deleted" do
        storage.resource(resource_id).save({ content: content, other_content: other_content }, foo: "bar")
        resource = storage.resource(resource_id)
        resource.delete(:content)
        expect(resource.exist?(:content)).to be_falsey
        expect { resource.load(:content) }.to raise_error(/no content to load/)

        resource = storage.resource(resource_id).load(:other_content)
        expect(resource.content(:other_content)).to eq(other_content)
        expect(resource.properties).to eq(foo: "bar", gemstash_storage_version: Gemstash::Storage::VERSION)
        expect { resource.load(:content) }.to raise_error(/no content to load/)
      end

      it "supports both files being deleted" do
        storage.resource(resource_id).save({ content: content, other_content: other_content }, foo: "bar")
        resource = storage.resource(resource_id)
        resource.delete(:content).delete(:other_content)
        expect(resource.exist?(:content)).to be_falsey
        expect(resource.exist?(:other_content)).to be_falsey
        expect(resource).to_not exist
        expect { resource.load(:content) }.to raise_error(/no content to load/)
        expect { resource.load(:other_content) }.to raise_error(/no content to load/)

        resource = storage.resource(resource_id)
        expect(resource.exist?(:content)).to be_falsey
        expect(resource.exist?(:other_content)).to be_falsey
        expect(resource).to_not exist
        expect { resource.load(:content) }.to raise_error(/no content to load/)
        expect { resource.load(:other_content) }.to raise_error(/no content to load/)

        # Ensure properties is deleted
        properties_filename = File.join(resource.folder, "properties.yml")
        expect(File.exist?(properties_filename)).to be_falsey
      end
    end

    context "with resource name that is unique by case only" do
      let(:first_resource_id) { "SomeResource" }
      let(:second_resource_id) { "someresource" }

      it "stores the content separately" do
        storage.resource(first_resource_id).save(content: "first content")
        storage.resource(second_resource_id).save(content: "second content")
        expect(storage.resource(first_resource_id).load(:content).content(:content)).to eq("first content")
        expect(storage.resource(second_resource_id).load(:content).content(:content)).to eq("second content")
      end

      it "uses different downcased paths to avoid issues with case insensitive file systems" do
        first_resource = storage.resource(first_resource_id)
        second_resource = storage.resource(second_resource_id)
        expect(first_resource.folder.downcase).to_not eq(second_resource.folder.downcase)
      end
    end

    context "with resource name that includes odd characters" do
      let(:resource_id) { ".=$&resource" }

      it "stores and retrieves the data" do
        storage.resource(resource_id).save(content: "odd name content")
        expect(storage.resource(resource_id).load(:content).content(:content)).to eq("odd name content")
      end

      it "doesn't include the odd characters in the path" do
        expect(storage.resource(resource_id).folder).to_not match(/[.=$&]/)
      end
    end
  end
end
