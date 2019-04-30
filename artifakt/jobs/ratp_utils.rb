require 'net/http'
require 'json'

API_HOME = 'https://api-ratp.pierre-grimaud.fr/v3'.freeze

SINGLETONS_REPLACEMENTS = {
  "Train a l'approche" => 'Approche',
  "Train à l'approche" => 'Approche',
  "A l'approche" => 'Approche',
  'Train a quai' => 'Quai',
  'Train à quai' => 'Quai',
  'Train retarde' => 'Retardé',
  "A l'arret" => 'Arrêt',
  'Train arrete' => 'Arrêté',
  'Service Termine' => 'Terminé',
  'Service termine' => 'Terminé',
  'PERTURBATIONS' => 'Perturbé',
  'BUS SUIVANT DEVIE' => 'Dévié',
  'DERNIER PASSAGE' => 'Terminé',
  'PREMIER PASSAGE' => ''
}.freeze

PAIR_REPLACEMENTS = {
  ['INTERROMPU', 'ARRET NON DESSERVI'] => ['Interrompu', 'N/Desservi'],

  ['INTERROMPU', 'INTERROMPU'] => ['Interrompu', 'Interrompu'],
  ['INTERROMPU', 'MANIFESTATION'] => ['Interrompu', 'Manifestation'],
  ['INTERROMPU', 'INTEMPERIES'] => ['Interrompu', 'Intempéries'],

  ['ARRET NON DESSERVI', 'ARRET NON DESSERVI'] => ['N/Desservi', 'N/Desservi'],
  ['ARRET NON DESSERVI', 'MANIFESTATION'] => ['N/Desservi', 'Manifestation'],
  ['ARRET NON DESSERVI', 'DEVIATION'] => ['N/Desservi', 'Déviation'],
  ['ARRET NON DESSERVI', 'ARRET REPORTE'] => ['N/Desservi', 'Reporté'],
  ['ARRET NON DESSERVI', 'INTEMPERIES'] => ['N/Desservi', 'Intempéries'],

  ['NON ASSURE', 'NON ASSURE'] => ['Non Assuré', 'Non Assuré'],
  ['NON ASSURE', 'MANIFESTATION'] => ['Non Assuré', 'Manifestation'],
  ['NON ASSURE', 'INTEMPERIES'] => ['Non Assuré', 'Intempéries'],

  ['CIRCULATION DENSE', 'MANIFESTATION'] => ['Circul Dense', 'Manifestation'],

  ['INTEMPERIES', 'INTEMPERIES'] => ['Intempéries', 'Intempéries'],

  ['INFO INDISPO ....'] => ['Indispo', 'Indispo'],

  ['SERVICE TERMINE'] => ['Terminé', 'Terminé'],
  ['TERMINE'] => ['Terminé', 'Terminé'],

  ['SERVICE', 'NON COMMENCE'] => ['N/Commencé', 'N/Commencé'],
  ['SERVICE NON COMMENCE'] => ['N/Commencé', 'N/Commencé'],
  ['NON COMMENCE'] => ['N/Commencé', 'N/Commencé'],

  ['BUS PERTURBE', '59 mn'] => %w[Perturbé Perturbé]
}.freeze

NA_UI = '[ND]'.freeze

Transport = Struct.new(:type, :number, :stop, :destination)

class Type
  METRO = { api: 'metros', ui: 'metro' }.freeze
  BUS = { api: 'bus', ui: 'bus' }.freeze
  RER = { api: 'rers', ui: 'rer' }.freeze
  TRAM = { api: 'tramways', ui: 'tram' }.freeze
  NOCTILIEN = { api: 'noctiliens', ui: 'noctilien' }.freeze
end

class ConfigurationError < StandardError
end

private def line_key(transport)
  transport.type[:api] + '-' + transport.number
end

private def get_as_json(path)
  response = Net::HTTP.get_response(URI(path))
  JSON.parse(response.body)
end

def read_stations(type, id)
  url = "#{API_HOME}/stations/#{type}/#{id}?_format=json"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: Unable to read stations for #{type} #{id} (#{url}): #{e}")
    return nil
  end

  raise ConfigurationError, "#{type} #{id}: #{json['result']['message']}" if json['result']['code'] == 400

  stations = station_name_to_slug_mapping(json)

  stations
end

private def station_name_to_slug_mapping(json)
  stations = {}

  json['result']['stations'].each do |station|
    stations[station['name']] = station['slug']
  end

  stations
end

def read_directions(type, id, stations)
  url = "#{API_HOME}/destinations/#{type}/#{id}?_format=json"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: Unable to read directions for #{type} #{id} (#{url}): #{e}")
    return nil
  end

  raise ConfigurationError, "#{type} #{id}: #{json['result']['message']}" if json['result']['code'] == 400

  # Workaround a bug on RATP or API side - sometimes, only one direction is returned (https://api-ratp.pierre-grimaud.fr/v3/destinations/bus/72?_format=json)
  if type == 'bus' && json['result']['destinations'].length == 1
    alt_destinations = get_as_json("https://www.ratp.fr/api/getLine/busratp/#{id}")
    alt_destination_names = alt_destinations['name'].split('/')
    destinations = [{ name: alt_destination_names[0].strip, way: 'A' },
                    { name: alt_destination_names[1].strip, way: 'R' }]

    json['result']['destinations'] = destinations
    json = JSON.parse(JSON(json))
  end

  destinations = destination_name_to_way_mapping(json, type, id, stations)

  destinations
end

private def destination_name_to_way_mapping(json, type, id, stations)
  destinations = json['result']['destinations']

  if [Type::BUS[:api], Type::TRAM[:api]].include?(type)
    return find_bus_directions(destinations, stations, type, id)
  else
    return find_regular_directions(destinations)
  end
end

private def find_bus_directions(destinations, stations, type, id)
  # Bug on RATP side for buses & trams - not all directions are correct
  # We take one destination, and check for destination A
  # If we get ambiguous station (400), it means that A is the direction itself
  # Otherwise, it means that A is the other direction
  # Yet it happens, sometimes, that both return a timing

  possible_directions = %w[A R]

  destinations.each_index do |index_destination|
    destination = destinations[index_destination]
    other_destination = destinations[(index_destination + 1) % 2]
    slug = stations[destination['name']]

    possible_directions.each_index do |index_direction|
      direction = possible_directions[index_direction]
      other_direction = possible_directions[(index_direction + 1) % 2]

      schedule = get_as_json("#{API_HOME}/schedules/#{type}/#{id}/#{slug}/#{direction}?_format=json")

      if schedule['result']['code'] == 400
        return {
          destination['name'] => direction,
          other_destination['name'] => other_direction
        }
      end
    end
  end

  # Otherwise, fallback to default
  find_regular_directions(destinations)
end

private def find_regular_directions(destinations)
  directions = {}
  destinations.each do |destination|
    directions[destination['name']] = destination['way']
  end
  directions
end

def read_timings(type, id, stop, dir)
  url = "#{API_HOME}/schedules/#{type}/#{id}/#{stop}/#{dir}?_format=json"
  begin
    json = get_as_json(url)
  rescue StandardError => e
    warn("ERROR: Unable to fetch timings for #{type} #{id} (#{url}): #{e}")
    return [NA_UI, NA_UI,
            NA_UI, NA_UI]
  end

  if json['result']['schedules'].nil?
    warn("ERROR: Schedules not available for #{type} #{id} (#{url}), json = #{json}")
    return [NA_UI, NA_UI,
            NA_UI, NA_UI]
  end

  schedules = json['result']['schedules']

  if schedules.length >= 2
    [schedules[0]['destination'], schedules[0]['message'],
     schedules[1]['destination'], schedules[1]['message']]
  elsif schedules.length == 1
    if !schedules[0].key?('code')
      [schedules[0]['destination'], schedules[0]['message'],
       '',                          '']
    else
      warn("ERROR: #{schedules[0]['code']} for #{type} #{id} (#{url}), json = #{json}")
      [schedules[0]['destination'], NA_UI,
       schedules[0]['destination'], NA_UI]
    end
  else
    warn("ERROR: Unable to parse timings for #{type} #{id} (#{url}), json = #{json}")
    [schedules[0]['destination'], NA_UI,
     schedules[0]['destination'], NA_UI]
  end
end

private def reword(first_time, second_time)
  PAIR_REPLACEMENTS.each do |source_message, target_message|
    if (source_message.length == 1 &&
         (first_time == source_message[0] || second_time == source_message[0])) ||
       (source_message.length == 2 &&
         ((first_time == source_message[0] && second_time == source_message[1]) ||
          (first_time == source_message[1] && second_time == source_message[0])))
      return target_message
    end
  end

  first_time_parsed = shortcut(first_time)
  second_time_parsed = shortcut(second_time)
  [first_time_parsed, second_time_parsed]
end

private def shortcut(text)
  SINGLETONS_REPLACEMENTS[text] || text
end
