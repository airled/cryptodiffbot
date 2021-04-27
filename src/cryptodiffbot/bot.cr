require "tourmaline"
require "json"
require "halite"
require "./storage"
require "./coin"
require "./secrets"

class Cryptodiffbot::Bot < Tourmaline::Client
  DB        = Storage.new
  URL       = "https://api.nomics.com/v1/currencies/ticker"
  OK        = "Ok"
  SPACER    = ' '
  JUSTIFIER = " "
  SPLITTER  = '|'
  DASH      = "-"
  HELP_TEXT = [
    "Доступные команды:",
    "/help - список всех команд с описанием",
    "/set - обновить значения для криптовалюты, параметры: кол-во валюты и общая стоимость покупки в $ (пример: /add BTC 0,1 5000). Если вы добавляете существующую криптовалюту, то новые значения перепишут старые",
    "/add - прибавить кол-во и стоимость к уже существующей валюте, параметры: кол-во валюты и общая стоимость покупки в $ (пример: /add ETH 0.5 2000). Если криптовалюта в портфеле отсутствует, то команда работает как /set",
    "/del - удалить криптовалюту из портфеля (пример: /del BTC)",
    "/s - показать портфель с текущими курсами. Курсы предоставляются сервисом https://nomics.com",
  ].join("\n")
  FLOAT_NUM_REGEX = /\d+([.,]\d+)?/
  INVALID         = "Неверные данные"

  @[Command("help")]
  def help_command(ctx)
    ctx.message.respond(HELP_TEXT)
  end

  @[Command("set")]
  def set_command(ctx)
    check_input_and_proceed(ctx) do |coin, amount, spent|
      coin.amount = amount
      coin.spent = spent
    end
  end

  @[Command("add")]
  def add_command(ctx)
    check_input_and_proceed(ctx) do |coin, amount, spent|
      coin.amount += amount
      coin.spent += spent
    end
  end

  @[Command("del")]
  def del_command(ctx)
    return ctx.message.respond("Не указана валюта") if ctx.text.to_s.strip.empty?
    coins = get_coins(ctx.message.chat.id).reject { |coin| coin.name == ctx.text }
    DB.set(ctx.message.chat.id, coins.map(&.as_json).to_json)
    ctx.message.respond(OK)
  end

  @[Command("s")]
  def show_command(ctx)
    coins = get_coins(ctx.message.chat.id)
    return ctx.message.respond("Портфель пуст") if (!coins || coins.empty?)
    coin_names = coins.map(&.name)
    rates = get_rates(coin_names)
    calculate(coins, rates)
    spent_all = coins.sum(&.spent).round(2)
    current_all = coins.sum(&.current).round(2)
    profit_all = (current_all - spent_all).round(2)

    max_name_size = coins.max_of(&.name.size)
    max_amount_size = coins.max_of(&.amount.to_s.size)
    max_spent_size = [coins.max_of(&.spent.round(2).to_s.size), spent_all.to_s.size].max
    max_rate_size = coins.max_of(&.rate.round(2).to_s.size)
    max_current_size = [coins.max_of(&.current.round(2).to_s.size), current_all.to_s.size].max
    max_profit_size = [coins.max_of(&.profit.round(2).to_s.size), profit_all.to_s.size].max

    rows = [] of String

    dash_row = [
      max_name_size,
      max_amount_size,
      max_spent_size,
      max_rate_size,
      max_current_size,
      max_profit_size,
    ].map { |size| DASH * size }.join(SPLITTER)

    # header row
    rows << [
      "#".ljust(max_name_size, SPACER),
      "Ед.".ljust(max_amount_size, SPACER),
      "@".rjust(max_spent_size, SPACER),
      "≈".rjust(max_rate_size, SPACER),
      "$".rjust(max_current_size, SPACER),
      "±".rjust(max_profit_size, SPACER),
    ].join(SPLITTER)

    rows << dash_row

    coins.each do |coin|
      rows << [
        coin.name.ljust(max_name_size, SPACER),
        coin.amount.to_s.ljust(max_amount_size, SPACER),
        coin.spent.round(2).to_s.rjust(max_spent_size, SPACER),
        coin.rate.round(2).to_s.rjust(max_rate_size, SPACER),
        coin.current.round(2).to_s.rjust(max_current_size, SPACER),
        coin.profit.round(2).to_s.rjust(max_profit_size, SPACER),
      ].join(SPLITTER)
    end

    rows << dash_row

    # sum row
    rows << [
      "∑".ljust(max_name_size, SPACER),
      JUSTIFIER * max_amount_size,
      spent_all.to_s.rjust(max_spent_size, SPACER),
      JUSTIFIER * max_rate_size,
      current_all.to_s.rjust(max_current_size, SPACER),
      profit_all.to_s.rjust(max_profit_size, SPACER),
    ].join(SPLITTER)

    ctx.message.respond("```\n#{rows.join("\n")}\n```", parse_mode: "MarkdownV2")
  end

  private def check_input_and_proceed(ctx, &block)
    params = ctx.text.split(SPACER, 3).map(&.strip)
    return ctx.message.respond(INVALID) if params.size != 3
    return ctx.message.respond(INVALID) if params.any?(&.empty?)
    name, amount, bought = params
    return ctx.message.respond(INVALID) unless amount.matches?(FLOAT_NUM_REGEX)
    return ctx.message.respond(INVALID) unless bought.matches?(FLOAT_NUM_REGEX)
    amount_float = amount.gsub(',', '.').to_f64
    spent_float = bought.gsub(',', '.').to_f64
    coins = get_coins(ctx.message.chat.id)
    coin_index = coins.index { |coin| coin.name == name }
    if coin_index
      yield coins[coin_index], amount_float, spent_float
    else
      coins << Coin.new(name, amount_float, spent_float)
    end
    DB.set(ctx.message.chat.id, coins.map(&.as_json).to_json)
    ctx.message.respond(OK)
  end

  private def get_coins(id)
    cached = DB.get(id)
    infos = if (!cached || cached.empty?)
              [] of Array(String | Float64)
            else
              Array(Array(String | Float64)).from_json(cached)
            end
    infos.map do |coin|
      Coin.new(
        coin[0].as(String),
        coin[1].as(Float64),
        coin[2].as(Float64)
      )
    end
  end

  private def get_rates(coin_names)
    json = Halite.get(URL, params: {
      key:      Cryptodiffbot::Secrets::NOMICS_API_KEY,
      ids:      coin_names.join(','),
      convert:  "USD",
      interval: "1d",
    }).body
    resp = Array(Hash(String, JSON::Any)).from_json(json)
    resp.each_with_object({} of String => Float64) do |coin, rates|
      rates[coin["id"].as_s] = coin["price"]? ? coin["price"].as_s.to_f64 : 0.0
    end
  end

  private def calculate(coins, rates)
    coins.each do |coin|
      rate = rates[coin.name]? || 0.0
      coin.rate = rate
      coin.current = coin.amount * rate
      coin.profit = coin.current - coin.spent
    end
  end
end
