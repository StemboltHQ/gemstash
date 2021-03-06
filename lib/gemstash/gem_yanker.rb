require "gemstash"

module Gemstash
  # Class that supports yanking a gem from the private repository of gems.
  class GemYanker
    include Gemstash::Env::Helper

    # This error is thrown when yanking a non-existing gem name.
    class UnknownGemError < StandardError
    end

    # This error is thrown when yanking a non-existing gem version.
    class UnknownVersionError < StandardError
    end

    # This error is thrown when yanking an already yanked gem version.
    class YankedVersionError < StandardError
    end

    def initialize(auth_key, gem_name, slug)
      @auth_key = auth_key
      @gem_name = gem_name
      @slug = slug
    end

    def yank
      check_auth
      update_database
      invalidate_cache
    end

  private

    def storage
      @storage ||= Gemstash::Storage.for("private").for("gems")
    end

    def full_name
      @full_name ||= "#{@gem_name}-#{@slug}"
    end

    def check_auth
      Gemstash::Authorization.check(@auth_key, "yank")
    end

    def update_database
      gemstash_env.db.transaction do
        raise UnknownGemError, "Cannot yank an unknown gem!" unless Gemstash::DB::Rubygem[name: @gem_name]
        version = Gemstash::DB::Version.find_by_full_name(full_name)
        raise UnknownVersionError, "Cannot yank an unknown version!" unless version
        raise YankedVersionError, "Cannot yank an already yanked version!" unless version.indexed
        version.deindex
        storage.resource(version.storage_id).update_properties(indexed: false)
      end
    end

    def invalidate_cache
      gemstash_env.cache.invalidate_gem("private", @gem_name)
    end
  end
end
