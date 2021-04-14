class Cryptodiffbot::Coin
  property name, amount, spent, rate : Float64, current : Float64, profit : Float64

  def initialize(@name : String, @amount : Float64, @spent : Float64)
    @rate = 0
    @current = 0
    @profit = 0
  end

  def as_json
    [@name, @amount, @spent]
  end
end
