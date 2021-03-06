require 'spec_helper'

describe Sequel::Unicache::Write do
  let!(:user_id) { User.first.id }

  before :each do
    Sequel::Unicache.configure cache: memcache
  end

  context 'read through' do
    it 'should read through cache into memcache' do
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: user.values, version: 1
    end

    it 'should serialize model into specified format' do
      User.instance_exec { unicache :id, serialize: ->(values, _) { values.to_yaml } }
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(YAML.load(cache)).to eq values: user.values, version: 1
    end

    it 'should not read through cache if unicache is not enabled for this key' do
      User.instance_exec { unicache :id, enabled: false }
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      user = User.find user_id
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should not read through cache if unicache is not enabled' do
      User.instance_exec { unicache :id, enabled: true }
      Sequel::Unicache.disable
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      user = User.find user_id
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should not read through cache if read-through is suspended' do
      User.instance_exec { unicache :id, enabled: true }
      user = Sequel::Unicache.suspend_unicache { User[user_id] }
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      user = Sequel::Unicache.suspend_unicache { User.find user_id }
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should not read through cache if condition is not permitted' do
      User.instance_exec { unicache :id, if: ->(model, _) { model.company_name != 'EMC' } }
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should set expiration time as you wish' do
      User.instance_exec { unicache :id, ttl: 1 }
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      sleep 1
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should not read from cache when unicache is disabled' do
      User[user_id] # cache data
      Sequel::Unicache.disable
      User[user_id].set(company_name: 'VMware').save
      user = User.find user_id
      expect(user.company_name).to eq 'VMware'
    end

    it 'should not read from cache when reload' do
      user = User[user_id]
      Sequel::Unicache.disable
      User[user_id].set(company_name: 'VMware').save
      Sequel::Unicache.enable
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      user.reload
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      expect(user.company_name).to eq 'VMware'
    end

    it 'should update cache when version doesn\'t match' do
      user = User[user_id]
      Sequel::Unicache.disable
      User[user_id].set(company_name: 'VMware').save
      User.unicache_model_configuration.version = 3
      Sequel::Unicache.enable
      expect(User[user_id].company_name).to eq 'VMware'
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)[:values][:company_name]).to eq 'VMware'
    end
  end

  context 'expire when update' do
    let!(:user) { User[user_id] }

    it 'should expire cache' do
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      user.set(company_name: 'VMware').save
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      user = User[user_id]
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: user.values, version: 1
    end

    it 'should not expire cache until transaction is committed' do
      User.db.transaction auto_savepoint: true do
        user.set(company_name: 'VMware').save
        cache = memcache.get "User:id:#{user.id}"
        expect(cache).not_to be_nil
      end
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should not expire cache if transaction is rollbacked' do
      origin = user.values.dup
      User.db.transaction rollback: :always do
        user.set(company_name: 'VMware').save
      end
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: origin, version: 1
    end

    it 'should not expire cache even if unicache is not enabled for that key' do
      User.unicache_for(:id).enabled = false
      origin = user.values.dup
      user.set(company_name: 'VMware').save
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: origin, version: 1
    end

    it 'should not expire cache even if unicache is not enabled' do
      Sequel::Unicache.disable
      origin = user.values.dup
      user.set(company_name: 'VMware').save
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: origin, version: 1
    end

    it 'should still expire cache even if read-through is suspended' do
      Sequel::Unicache.suspend_unicache { user.set(company_name: 'VMware').save }
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should still expire all cache even if model is not completed' do
      memcache.flush_all # Clear all cache first
      User.instance_exec { unicache :username, key: ->(values, _) { "User/username/#{values[:username]}" } }
      user = User[user_id]
      cache = memcache.get "User/username/bachue@gmail.com"
      expect(cache).not_to be_nil
      user = User.select(:id, :company_name)[user_id]
      user.set(company_name: 'VMware').save
      cache = memcache.get "User/username/bachue@gmail.com"
      expect(cache).to be_nil
    end

    it 'should expire obsolate cache if any value of the unicache key is changed' do
      User.instance_exec { unicache :username }
      user = User[user_id]
      User.db.transaction auto_savepoint: true do
        user.set(username: 'bachue@emc.com').save
        user.set(username: 'bachue@vmware.com', company_name: 'VMware').save
      end
      cache = memcache.get "User:username:bachue@gmail.com"
      expect(cache).to be_nil
    end

    it 'should still get currect value during a transaction' do
      user = User[user_id]
      expect(Sequel::Unicache.unicache_suspended?).not_to be true
      User.db.transaction auto_savepoint: true do
        expect(Sequel::Unicache.unicache_suspended?).to be true
        user.set(username: 'bachue@emc.com').save
        expect(User[user_id].username).to eq 'bachue@emc.com'
      end
      expect(Sequel::Unicache.unicache_suspended?).not_to be true
    end
  end

  context 'expire when delete' do
    let!(:user) { User[user_id] }

    it 'should expire cache' do
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      user.destroy
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should expire cache' do
      User.instance_exec { unicache :username }
      user = User.select(:id).first
      user.destroy
      cache = memcache.get "User:username:#{user.username}"
      expect(cache).to be_nil
    end

    it 'should not expire cache until transaction is committed' do
      User.db.transaction auto_savepoint: true do
        user.destroy
        cache = memcache.get "User:id:#{user.id}"
        expect(cache).not_to be_nil
      end
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end

    it 'should not expire cache even if unicache is not enabled for that key' do
      User.unicache_for(:id).enabled = false
      user.destroy
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: user.values, version: 1
    end

    it 'should not expire cache even if unicache is not enabled' do
      Sequel::Unicache.disable
      user.destroy
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      expect(Marshal.load(cache)).to eq values: user.values, version: 1
    end

    it 'should still expire cache even if read-through is suspended' do
      Sequel::Unicache.suspend_unicache { user.destroy }
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
    end
  end

  context 'expire by #expire_unicache' do
    let(:user) { User[user_id] }

    before :each do
      User.instance_exec do
        unicache :username
        unicache :company_name, :department, :employee_id
      end
    end

    it 'should expire all keys' do
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).not_to be_nil
      cache = memcache.get "User:username:bachue@gmail.com"
      expect(cache).not_to be_nil
      cache = memcache.get "User:company_name:EMC:department:Mozy:employee_id:12345"
      expect(cache).not_to be_nil
      user.expire_unicache
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      cache = memcache.get "User:username:bachue@gmail.com"
      expect(cache).to be_nil
      cache = memcache.get "User:company_name:EMC:department:Mozy:employee_id:12345"
      expect(cache).to be_nil
    end

    it 'should expire all keys even unicache is disabled' do
      Sequel::Unicache.disable
      user.expire_unicache
      cache = memcache.get "User:id:#{user.id}"
      expect(cache).to be_nil
      cache = memcache.get "User:username:bachue@gmail.com"
      expect(cache).to be_nil
      cache = memcache.get "User:company_name:EMC:department:Mozy:employee_id:12345"
      expect(cache).to be_nil
    end
  end
end
