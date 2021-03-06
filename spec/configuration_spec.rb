require 'spec_helper'

describe Sequel::Unicache::Configuration do
  before :each do
    Sequel::Unicache.configure cache: memcache, enabled: true, ttl: 120
  end

  it 'should configure primary key as unicache' do
    expect(User.unicache_for(:id)).to be_kind_of Sequel::Unicache::Configuration
    expect(User.unicache_for(:id).cache).to be memcache
    expect(User.unicache_for(:id).enabled).to be true
    expect(User.unicache_for(:id).ttl).to be 120
    expect(User.unicache_for(:id).model_class).to be User
    expect(User.unicache_for(:id).unicache_keys).to be :id
  end

  it 'should let class-level configuration override global-level configuration' do
    User.instance_exec { unicache :id, ttl: 150 }
    expect(User.unicache_for(:id).cache).to be memcache
    expect(User.unicache_for(:id).enabled).to be true
    expect(User.unicache_for(:id).ttl).to be 150
    expect(User.unicache_for(:id).model_class).to be User
    expect(User.unicache_for(:id).unicache_keys).to be :id
  end

  it 'should configure primary key as unicache even primary key is changed' do
    User.set_primary_key [:company_name, :department, :employee_id]
    expect(User.unicache_for(:company_name, :department, :employee_id)).to be_kind_of Sequel::Unicache::Configuration
    expect(User.unicache_for(:department, :company_name, :employee_id).cache).to be memcache
    expect(User.unicache_for(:employee_id, :department, :company_name).enabled).to be true
    expect(User.unicache_for(:department, :employee_id, :company_name).ttl).to be 120
    expect(User.unicache_for(:company_name, :employee_id, :department).model_class).to be User
    expect(User.unicache_for(:employee_id, :company_name, :department).unicache_keys).to eq [:company_name, :department, :employee_id]
  end

  it 'can configure for primary key manually' do
    condition_proc = ->(model, opts) { model.deleted? }
    User.instance_exec { unicache :id, enabled: false, if: condition_proc }
    expect(User.unicache_for(:id)).to be_kind_of Sequel::Unicache::Configuration
    expect(User.unicache_for(:id).cache).to be memcache
    expect(User.unicache_for(:id).enabled).to be false
    expect(User.unicache_for(:id).ttl).to be 120
    expect(User.unicache_for(:id).if).to be condition_proc
    expect(User.unicache_for(:id).model_class).to be User
    expect(User.unicache_for(:id).unicache_keys).to be :id
  end

  it 'can configure for another unicache' do
    serialize_proc = ->(values, opts) { JSON.dump values }
    deserialize_proc = ->(cache, opts) { JSON.load cache }
    User.instance_exec {
      unicache :department, :employee_id, :company_name, ttl: 60,
               serialize: serialize_proc, deserialize: deserialize_proc
    }
    expect(User.unicache_for(:company_name, :department, :employee_id)).to be_kind_of Sequel::Unicache::Configuration
    expect(User.unicache_for(:department, :company_name, :employee_id).cache).to be memcache
    expect(User.unicache_for(:employee_id, :department, :company_name).enabled).to be true
    expect(User.unicache_for(:department, :employee_id, :company_name).serialize).to be serialize_proc
    expect(User.unicache_for(:company_name, :employee_id, :department).deserialize).to be deserialize_proc
    expect(User.unicache_for(:employee_id, :company_name, :department).model_class).to be User
    expect(User.unicache_for(:company_name, :department, :employee_id).unicache_keys).to eq [:company_name, :department, :employee_id]
  end

  it 'can configure key-level, class-level and global level' do
    condition_proc = ->(model, opts) { model.deleted? }
    serialize_proc = ->(values, opts) { JSON.dump values }
    deserialize_proc = ->(cache, opts) { JSON.load cache }
    User.instance_exec {
      unicache if: condition_proc, enabled: false
      unicache :department, :employee_id, :company_name, ttl: 60, enabled: true,
               serialize: serialize_proc, deserialize: deserialize_proc
    }
    expect(User.unicache_for(:id)).to be_kind_of Sequel::Unicache::Configuration
    expect(User.unicache_for(:id).cache).to be memcache
    expect(User.unicache_for(:id).enabled).to be false
    expect(User.unicache_for(:id).if).to be condition_proc
    expect(User.unicache_for(:id).ttl).to be 120
    expect(User.unicache_for(:id).model_class).to be User
    expect(User.unicache_for(:id).unicache_keys).to be :id
    expect(User.unicache_for(:company_name, :department, :employee_id)).to be_kind_of Sequel::Unicache::Configuration
    expect(User.unicache_for(:department, :company_name, :employee_id).cache).to be memcache
    expect(User.unicache_for(:employee_id, :department, :company_name).enabled).to be true
    expect(User.unicache_for(:employee_id, :department, :company_name).ttl).to be 60
    expect(User.unicache_for(:department, :employee_id, :company_name).serialize).to be serialize_proc
    expect(User.unicache_for(:company_name, :employee_id, :department).deserialize).to be deserialize_proc
    expect(User.unicache_for(:employee_id, :company_name, :department).model_class).to be User
    expect(User.unicache_for(:company_name, :department, :employee_id).unicache_keys).to eq [:company_name, :department, :employee_id]
  end

  it 'can set cache version for each model' do
    User.instance_exec { unicache version: 3 }
    expect(User.unicache_version).to be 3
  end

  it 'cannot get or set cache version for any key' do
    expect(User.unicache_for(:id).respond_to?(:version)).to be false
    expect(User.unicache_for(:id).respond_to?(:version=)).to be false
  end

  it 'Model\'s default version is always 1' do
    expect(User.unicache_version).to be 1
  end

  it 'can enable & disable any unicache key' do
    User.instance_exec { unicache enabled: false }
    expect(User.unicache_for(:id).enabled).to be false
    expect(User.unicache_enabled_for?(:id)).to be false
    User.unicache_for(:id).enabled = true
    expect(User.unicache_for(:id).enabled).to be true
    expect(User.unicache_enabled_for?(:id)).to be true
  end

  it 'can fuzzy search for unicache keys' do
    User.instance_exec { unicache :department, :employee_id, :company_name }
    expect(User.unicache_for(:id, :department)).to be_nil
    expect(User.unicache_for(:id, :department, fuzzy: true)).to be User.unicache_for(:id)
    expect(User.unicache_for(:id, :department, :employee_id, :company_name, fuzzy: true)).to be User.unicache_for(:id)
    User.unicache_for(:id).enabled = false
    expect(User.unicache_for(:id, :department, fuzzy: true)).to be_nil
    expect(User.unicache_for(:id, :department, :employee_id, :company_name, fuzzy: true)).to be User.unicache_for(:department, :employee_id, :company_name)
  end

  it 'should disable unicache key if cache store is not specified' do
    reset_global_configuration
    Sequel::Unicache.configure enabled: true, ttl: 120
    expect(User.unicache_enabled_for?(:id)).to be nil
    cache = memcache
    User.instance_exec { unicache :id, cache: cache }
    expect(User.unicache_enabled_for?(:id)).to be true
  end

  it 'should always give default value for serialize, deserialize & key' do
    expect(User.unicache_for(:id).serialize).not_to be_nil
    expect(User.unicache_for(:id).deserialize).not_to be_nil
    expect(User.unicache_for(:id).key).not_to be_nil
  end
end
