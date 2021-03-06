require 'spec_helper'

describe Sequel::Unicache::GlobalConfiguration do
  it 'should be true' do
    expect(Sequel::Unicache.config).to be_kind_of Sequel::Unicache::GlobalConfiguration
  end

  it 'can configure for unicache' do
    logger = Logger.new(STDERR)

    Sequel::Unicache.configure cache: memcache,
                               ttl: 30,
                               logger: logger

    expect(Sequel::Unicache.config.cache).to be memcache
    expect(Sequel::Unicache.config.ttl).to be 30
    expect(Sequel::Unicache.config.enabled).to be true
    expect(Sequel::Unicache.config.logger).to be logger

    serialize_proc = ->(model, opts) { Marshal.dump model }
    deserialize_proc = ->(cache, opts) { Marshal.load cache }
    key_proc = ->(hash, opts) { "id/#{hash[:id]}" }

    Sequel::Unicache.config.serialize = serialize_proc
    Sequel::Unicache.config.deserialize = deserialize_proc
    Sequel::Unicache.config.key = key_proc

    expect(Sequel::Unicache.config.serialize).to be serialize_proc
    expect(Sequel::Unicache.config.deserialize).to be deserialize_proc
    expect(Sequel::Unicache.config.key).to be key_proc

    expect(Sequel::Unicache.config.to_h).to eq cache: memcache,
                                               ttl: 30,
                                               enabled: true,
                                               logger: logger,
                                               serialize: serialize_proc,
                                               deserialize: deserialize_proc,
                                               key: key_proc
  end

  it 'can enable & disable unicache feature' do
    Sequel::Unicache.disable
    expect(Sequel::Unicache.enabled?).to be false
    Sequel::Unicache.enable
    expect(Sequel::Unicache.enabled?).to be true
  end

  it 'can suspend & unsuspend read-through' do
    Sequel::Unicache.suspend_unicache
    expect(Sequel::Unicache.unicache_suspended?).to be true
    Sequel::Unicache.unsuspend_unicache
    expect(Sequel::Unicache.unicache_suspended?).to be false
    Sequel::Unicache.suspend_unicache do
      expect(Sequel::Unicache.unicache_suspended?).to be true
    end
    expect(Sequel::Unicache.unicache_suspended?).to be false
  end
end
