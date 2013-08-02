module Fluent
  class RedisOutput < BufferedOutput
    Fluent::Plugin.register_output('rediszadd', self)
    attr_reader :host, :port, :db_number, :redis, :key_prefix, :key_suffix, :key_name, :score_name, :value_name, :key_expire, :value_expire

    def initialize
      super
      require 'redis'
      require 'msgpack'
    end

    def configure(conf)
      super

      @host = conf.has_key?('host') ? conf['host'] : 'localhost'
      @port = conf.has_key?('port') ? conf['port'].to_i : 6379
      @db_number = conf.has_key?('db_number') ? conf['db_number'].to_i : nil

      if conf.has_key?('namespace')
        $log.warn "namespace option has been removed from fluent-plugin-redis 0.1.3. Please add or remove the namespace '#{conf['namespace']}' manually."
      end
      @key_prefix = conf.has_key?('key_prefix') ? conf['key_prefix'] : ''
      @key_suffix = conf.has_key?('key_suffix') ? conf['key_suffix'] : ''
      @key_name = conf['key_name']
      @score_name = conf['score_name']
      @value_name = conf['value_name']
      @key_expire = conf.has_key?('key_expire') ? conf['key_expire'].to_i : -1
      @value_expire = conf.has_key?('value_expire') ? conf['value_expire'].to_i : -1
    end

    def start
      super

      @redis = Redis.new(:host => @host, :port => @port,
                         :thread_safe => true, :db => @db_number)
    end

    def shutdown
      @redis.quit
    end

    def format(tag, time, record)
      identifier = [tag, time].join(".")
      [identifier, record].to_msgpack
    end

    def write(chunk)
      @redis.pipelined {
        chunk.open { |io|
          begin
            MessagePack::Unpacker.new(io).each { |message|
              begin
                (tag, record) = message
                now = Time.now.to_i
                k = traverse(record, @key_name).to_s
                if @score_name
                  s = traverse(record, @score_name)
                else
                  s = now
                end
                v = traverse(record, @value_name)
                sk = @key_prefix + k + @key_suffix
              
                @redis.zadd sk , s, v
                if @key_expire > 0
                  @redis.expire sk , @key_expire
                end
                if @value_expire > 0
                  @redis.zremrangebyscore sk , '-inf' , (now - @value_expire)
                end
              rescue NoMethodError => e
                puts e
              end
            }
          rescue EOFError
            # EOFError always occured when reached end of chunk.
          end
        }
      }
    end

    def traverse(data, key)
      val = data
      key.split('.').each{ |k|
        if val.has_key?(k)
          val = val[k]
        else
          return nil
        end
      }
      return val
    end 
  end
end
