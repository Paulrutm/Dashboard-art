class Dashing.Ratp extends Dashing.Widget
  onData: (data) ->
    for result in data.results
      transportId = result.key
      currentResult = result.value
      
      transportId1 = transportId + '-1'
      transportId2 = transportId + '-2'

      element = $("##{transportId}-1").val()
      if not element?
        # First time, build the table
        $('.widget-ratp table')
          .append(@createRow(currentResult.type, currentResult.id, transportId1))
          .append(@createRow(currentResult.type, currentResult.id, transportId2))

      @update(transportId1, currentResult.d1, currentResult.t1)
      @update(transportId2, currentResult.d2, currentResult.t2)

  createRow: (type, id, transportId) ->
    cellIcon = $ '<td>'
    cellIcon.addClass 'transport'

    imgIcon = $ '<img>'
    imgIcon.attr 'src', "https://www.ratp.fr/sites/default/files/network/#{type}/ligne#{id}.svg"
    imgIcon.addClass type
    imgIcon.addClass 'icon'
    imgIcon.on 'error', ->
      console.log "Unable to retrieve #{imgIcon.attr 'src'}"
      cellIcon.html id # If image is not available, fall back to text

    cellIcon.append imgIcon

    cellDest = $ '<td>'
    cellDest.addClass 'dest'
    cellDest.attr 'id', transportId + '-dest'

    spanDest = $ '<span>'
    spanDest.attr 'id', transportId + '-dest-span'

    cellDest.append spanDest

    cellTime = $ '<td>'
    cellTime.addClass 'time'
    cellTime.attr 'id', transportId + '-time'

    spanTime = $ '<span>'
    spanTime.attr 'id', transportId + '-time-span'

    cellTime.append spanTime

    row = $ '<tr>'
    row.attr 'id', transportId
    row.append cellIcon
    row.append cellDest
    row.append cellTime

    return row

  update: (id, newDest, newTime) ->
    @fadeUpdate(id, 'dest', newDest, 15)
    @fadeUpdate(id, 'time', newTime, 10)

  fadeUpdate: (id, type, newValue, minSize) ->
    spanId = "##{id}-#{type}-span"

    if newValue == '[ND]'
      $(spanId).addClass 'grayed'
    else
      $(spanId).removeClass 'grayed'

      tdId = "##{id}-#{type}"
      oldValue = $(spanId).html()

      if oldValue != newValue
        $(spanId).fadeOut(->
          $(tdId).css('font-size', '')
          $(this).html(newValue).fadeIn(->
            while $(tdId)[0]?.offsetWidth < $(tdId)[0]?.scrollWidth && $(tdId).css('font-size').replace('px','') > minSize
              $(tdId).css('font-size','-=0.5')
          )
        )

    
