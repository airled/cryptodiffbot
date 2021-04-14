require "redis"

class Cryptodiffbot::Storage
  CONN   = Redis.new
  PREFIX = "cryptodiffbot"

  def set(key, value)
    CONN.set("#{PREFIX}#{key}", value)
  end

  def get(key)
    CONN.get("#{PREFIX}#{key}")
  end
end
