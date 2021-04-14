require "./cryptodiffbot/bot"
require "./cryptodiffbot/secrets"

bot = Cryptodiffbot::Bot.new(bot_token: Cryptodiffbot::Secrets::BOT_KEY)
bot.poll
