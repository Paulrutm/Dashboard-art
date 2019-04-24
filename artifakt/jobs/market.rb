# jobs/market.rb
SCHEDULER.every "10s", first_in: 0 do |job|
  data = [
    { "x" => 1980, "y" => 1323 },
    { "x" => 1981, "y" => 53234 },
    { "x" => 1982, "y" => 2344 }
  ]
  send_event(:market_value, points: data, displayedValue: data.first["y"])
end



