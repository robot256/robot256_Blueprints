if not valid_contents then
  valid_contents={['water']=true,
                ['crude-oil']=true,
                ['coal']=true,
                ['stone']=true,
                ['iron-plate']=true,
                ['copper-plate']=true,
                ['steel-plate']=true,
                ['advanced-circuit']=true,
                ['processing-unit']=true,
                ['engine-unit']=true,
                ['low-density-structure']=true,
                ['rocket-fuel']=true,
                ['stone-brick']=true}
end
if not valid_wagons then
  valid_wagons={['ltn-position-any-cargo-wagon']='cargo-wagon',
              ['ltn-position-any-fluid-wagon']='fluid-wagon'}
end
local red = inputs[1].red
local yard = 1
local track = 1
local mask = 1
if red['dispatcher-station'] and red['dispatcher-station'] ~= 0 then
  track = red['dispatcher-station']
  mask = bit32.lshift(1, (track-1)%32)
end
if not state then
  state = 0
  outputs[1] = {}
  outputs[2] = {}
  contents = nil
  wagons = nil
  err = false
end
delay = 60
local green = inputs[1].green
if state == 0 then
  if green['signal-red'] and green['signal-red'] > 0 then
    -- Train just arrived. Act on its contents and send it away
    outputs[1] = {['signal-green'] = 1}
    outputs[2] = {}
    
    contents = nil
    wagons = nil
    err = false
    for signal,value in pairs(green) do
      if value > 0 then
        if valid_contents[signal] then
          if contents then
            err = true
            break
          else
            contents = signal
          end
        elseif valid_wagons[signal] then
          if wagons then
            err = true
            break
          else
            wagons = valid_wagons[signal]
          end
        elseif signal ~= "signal-red" and not string.find(signal,"ltn%-position") then
          err = true
          break
        end
      end
    end
    state = 1
  end
elseif state == 1 then
  if not green['signal-red'] or green['signal-red'] == 0 then
    delay = 1
    -- Train has left, we can change the stop names now
    if err then
      outputs[1] = string_to_signals('Y'..tostring(yard)..' ERROR')
      outputs[1]['signal-stopname']=1
      -- Don't enable any stations
      state = 2
    elseif contents then
      --rename stop to contents
      outputs[1] = string_to_signals('Y'..tostring(yard)..' PICKUP [item='..contents..'].'..tostring(track))
      outputs[1]['signal-stopname']=1
      outputs[1]['signal-stopname-richtext']=1
      -- Enable pickup stations
      state = 3
    elseif wagons then
      -- rename stop to wagons
      contents = wagons
      outputs[1] = string_to_signals('Y'..tostring(yard)..' PICKUP [item='..contents..'].'..tostring(track))
      outputs[1]['signal-stopname']=1
      outputs[1]['signal-stopname-richtext']=1
      -- Enable pickup stations
      state = 3
    else
      -- rename to empty
      outputs[1] = string_to_signals('Y'..tostring(yard)..' EMPTY')
      outputs[1]['signal-stopname']=1
      -- Enable dropoff stations
      state = 4
    end
  end
elseif state == 2 then
  -- Error state, all stops disabled
  outputs[1] = {['signal-red']=1}
  -- Send error signal to yard manager
  outputs[2] = {['signal-black']=mask}
  state = 0
  delay = 1
elseif state == 3 then
  -- Enable pickup stations
  outputs[1] = {['signal-cyan']=1,
                ['signal-couple']=1}
  -- Send inventory to the yard manager
  if contents then
    outputs[2] = {[contents]=mask}
  else
    outputs[2] = {['signal-black']=mask}
  end
  state = 0
  delay = 1
elseif state == 4 then
  -- Enable dropoff stations
  outputs[1] = {['signal-pink']=1,
                ['signal-decouple']=2}
  outputs[2] = {['signal-white']=mask}
  state = 0
  delay = 1
else
  state = 0
  outputs[1] = {}
  outputs[2] = {}
  contents = nil
  wagons = nil
  err = false
  delay = 1
end
